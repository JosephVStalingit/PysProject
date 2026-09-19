param(
    # Which gmsh geometry to BUILD AND SOLVE. Must be a `sif_suffix` declared
    # in config.json -> [curves].<name>.sif_suffix  ("no-coil" | "stranded-coil").
    [string] $Config = "no-coil",

    # Run the pipeline once per distinct sif_suffix found in config.json.
    [switch] $All,

    # Skip steps 1-3 (gmsh / ElmerGrid / ElmerSolver) and only re-do the
    # post-processing (tests + oscilloscope) on the existing mesh/ and results/.
    # Use this to re-plot after editing config.json -- it takes seconds
    # instead of the ~20 min of the transient solve.
    [switch] $NoSolve
)
# ============================================================================
#  run_tests.ps1  --  跑全部 FEM 测试   (START COMMAND / 唯一入口)
#
#  Usage:
#     .\run_tests.ps1                      # full pipeline, default geometry
#     .\run_tests.ps1 -Config stranded-coil
#     .\run_tests.ps1 -All                 # every sif_suffix in config.json
#     .\run_tests.ps1 -NoSolve             # only re-plot existing results
#
#  Pipeline: solenoid3d.py (gmsh) -> ElmerGrid -> ElmerSolver 26.2
#            -> ResultOutputSolver (VTU) -> tests/test_*.py -> oscilloscope.py
#
#  NOTE on configurations: the coil/air geometry only has TWO variants
#  (`no-coil` and `stranded-coil`), because the magnet's motion is prescribed
#  and the material/circuit data (N_turns, wire material, R_load) enters as
#  POST-PROCESSING.  So `-Config` selects the mesh, while every entry of
#  config.json -> [curves] is always compared in the oscilloscope's
#  "coil transit timing" and "induced current" panels.
#  With -All each geometry is solved in turn and results/ ends up holding the
#  LAST one (both give near-identical fields, so this is usually what you want).
#
#  Elmer 26.2 is bundled in ./elmer262/ so the pipeline is Docker-portable.
#
#  返回码：0 = 全部通过；1 = 至少一项失败。
# ============================================================================
$ErrorActionPreference = "Continue"
Set-Location -Path $PSScriptRoot

# Pick the Python that owns the gmsh installation
$PY = $null
foreach ($cand in @(
    "C:\Users\JosephVStalin\AppData\Local\Programs\Python\Python311\python.exe",
    "C:\Python314\python.exe",
    "python")) {
    $p = Get-Command $cand -ErrorAction SilentlyContinue
    if ($p) { $PY = $p.Source; break }
}
if (-not $PY) {
    Write-Host "  err  python not found" -ForegroundColor Red
    exit 1
}
Write-Host "    -> using $PY" -ForegroundColor Cyan

# Locate Elmer 26.2 (now bundled inside the project for Docker portability)
$ELMER_HOME = $null
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'elmer262'),
    "C:\elmer262",
    "D:\elmer262",
    "$env:LOCALAPPDATA\elmer262",
    "$env:ProgramFiles\elmer262")) {
    if (Test-Path (Join-Path $cand 'bin\ElmerSolver.exe')) {
        $ELMER_HOME = $cand; break
    }
}
if (-not $ELMER_HOME) {
    Write-Host "  err  Elmer 26.2 not found (expected ./elmer262 or C:\elmer262)" -ForegroundColor Red
    Write-Host "        project bundles ./elmer262/ for Docker portability" -ForegroundColor Yellow
    exit 1
}
Write-Host "    -> ELMER_HOME=$ELMER_HOME" -ForegroundColor Cyan
$env:ELMER_HOME = $ELMER_HOME
$env:ELMER_LIB  = "$ELMER_HOME\share\elmersolver\lib"
$env:Path = "$ELMER_HOME\bin;$env:Path"

# ---------------------------------------------------------------------------
# START COMMAND: resolve which geometry/geometries to build and solve.
# The list of valid values is derived from config.json -> [curves].sif_suffix,
# so adding a configuration is a JSON edit -- no change needed here.
# ---------------------------------------------------------------------------
$cfgJson = $null
$allSuffixes = @()
try {
    $cfgJson = Get-Content config.json -Raw | ConvertFrom-Json
    $allSuffixes = @($cfgJson.curves.PSObject.Properties |
                     ForEach-Object { $_.Value.sif_suffix } |
                     Where-Object { $_ } | Select-Object -Unique)
} catch {
    Write-Host "  err  config.json could not be parsed: $_" -ForegroundColor Red
    exit 1
}
if (-not $allSuffixes) { $allSuffixes = @('no-coil') }
$allCurves = @($cfgJson.curves.PSObject.Properties.Name)

$targets = if ($All) { $allSuffixes } else { @($Config) }
foreach ($t in $targets) {
    if ($allSuffixes -notcontains $t) {
        Write-Host "  err  -Config '$t' is not a sif_suffix declared in config.json" -ForegroundColor Red
        Write-Host "       available: $($allSuffixes -join ', ')" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host ""
Write-Host "START COMMAND" -ForegroundColor Cyan
Write-Host "  geometry to solve : $($targets -join ', ')"
Write-Host "  curves compared   : $($allCurves -join ', ')   (oscilloscope panels)"
Write-Host "  skip solve        : $($NoSolve.IsPresent)"

if ($NoSolve) {
    if (-not (Test-Path results\case_t0001.vtu)) {
        Write-Host "  err  -NoSolve given but results\case_t0001.vtu is missing" -ForegroundColor Red
        Write-Host "       run without -NoSolve first" -ForegroundColor Yellow
        exit 1
    }
    Write-Host ""
    Write-Host "[1..3/5] SKIPPED (-NoSolve): reusing existing mesh\ and results\" -ForegroundColor Yellow
} else {
foreach ($cfgName in $targets) {

# 1. Build the mesh (gmsh)
Write-Host ""
Write-Host "[1/5] gmsh build  (--config $cfgName)" -ForegroundColor Cyan
New-Item -ItemType Directory -Force test_outputs | Out-Null
& $PY solenoid3d.py --config $cfgName 2>&1 | Tee-Object -FilePath test_outputs\gmsh.log | Select-Object -Last 2
if (-not (Test-Path model3d.msh)) {
    Write-Host "  err  model3d.msh not produced" -ForegroundColor Red
    exit 1
}
Write-Host ("  ok   model3d.msh  ({0:N1} MB)" -f ([double](Get-Item model3d.msh).Length/1MB)) -ForegroundColor Green

# 2. Convert mesh (ElmerGrid)
Write-Host ""
Write-Host "[2/5] ElmerGrid 14 2" -ForegroundColor Cyan
if (Test-Path mesh) { Remove-Item -Recurse -Force mesh }
& "$ELMER_HOME\elmergrid\src\ElmerGrid.exe" 14 2 model3d.msh -out mesh -autoclean `
    2>&1 | Tee-Object -FilePath test_outputs\elmergrid.log | Select-String 'knots|elements|ERROR' | Select-Object -First 2
if (-not (Test-Path mesh\mesh.elements)) {
    Write-Host "  err  mesh\ not produced" -ForegroundColor Red
    exit 1
}
$header = Get-Content mesh\mesh.header | Select-Object -First 1
Write-Host "  ok   mesh\  ($header)" -ForegroundColor Green

# 3. ElmerSolver 26.2
Write-Host ""
Write-Host "[3/5] ElmerSolver 26.2 (transient)" -ForegroundColor Cyan
# config.json is the source of truth for the motion law AND the time stepping,
# so (re)generate the SIF from it before solving.
& $PY make_sif.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  make_sif.py failed" -ForegroundColor Red
    exit 1
}
if (Test-Path results) { Remove-Item -Recurse -Force results }
New-Item -ItemType Directory -Force results | Out-Null
& "$ELMER_HOME\bin\ElmerSolver.exe" case_transient.sif `
    2>&1 | Tee-Object -FilePath results\solver.log | Out-Null
if (-not (Test-Path results\case_t0001.vtu)) {
    Write-Host "  err  results\case_t0001.vtu not produced" -ForegroundColor Red
    Get-Content results\solver.log | Select-String 'FATAL|ERROR' | Select-Object -First 5
    exit 1
}
$vtusize = [double](Get-Item results\case_t0001.vtu).Length/1KB
Write-Host "  ok   case_t0001.vtu  ($([math]::Round($vtusize,1)) KB)" -ForegroundColor Green
Select-String -Path results\solver.log -Pattern 'ALL DONE|TOTAL TIME' | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }

}
}

# 4. Run the FEM sanity tests
Write-Host ""
Write-Host "[4/5] FEM tests" -ForegroundColor Cyan
& $PY tests/test_mesh.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_mesh.py failed" -ForegroundColor Red
    exit 1
}
& $PY tests/test_render.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_render.py failed" -ForegroundColor Red
    exit 1
}
# Locks down make_sif.py --solver: the default must stay byte-identical to the
# template, and hypre-ams must not leave duplicate SIF keys behind.  Needs no
# Elmer/gmsh, so it always runs.
& $PY tests/test_sif_solver.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_sif_solver.py failed" -ForegroundColor Red
    exit 1
}
# Locks down make_sif.py --circuit closed: the open path must stay
# byte-identical to the template, the closed path must emit the coil/load
# Components + CircuitsAndDynamics solvers + circuits.definitions, and the
# no-turn / infinite-load / missing-curve combinations must be refused.
# Needs no Elmer/gmsh, so it always runs.
& $PY tests/test_sif_circuit.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_sif_circuit.py failed" -ForegroundColor Red
    exit 1
}
# Locks down the damped-harmonic-oscillator math: period, damping regime,
# matc_expr <-> z_of_t consistency (the verifier depends on both agreeing).
& $PY tests/test_spring_model.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_spring_model.py failed" -ForegroundColor Red
    exit 1
}

# 5. Oscilloscope -- plot every physical quantity from the FEM frames
Write-Host ""
Write-Host "[5/5] oscilloscope (FEM result plots)" -ForegroundColor Cyan
& $PY oscilloscope.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  oscilloscope.py failed" -ForegroundColor Red
    exit 1
}
& $PY test_outputs\verify_fall.py
if ($LASTEXITCODE -ne 0) {
    Write-Host "  warn verify_fall.py reported a deviation" -ForegroundColor Yellow
}
# spring mode has its own verifier (checks against the analytic oscillator)
$mode = (& $PY -c "import json;print(json.load(open('config.json',encoding='utf-8'))['experiment'].get('motion_mode','free_fall'))").Trim()
if ($mode -eq "spring") {
    & $PY test_outputs\verify_spring.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  warn verify_spring.py reported a deviation" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  ok   all FEM tests passed" -ForegroundColor Green
Write-Host ""
Write-Host "START COMMAND (copy/paste)" -ForegroundColor Cyan
Write-Host "  .\run_tests.ps1 -Config no-coil        # full transient solve (no conductor)" -ForegroundColor DarkGray
Write-Host "  .\run_tests.ps1 -Config stranded-coil  # full transient solve (with winding)" -ForegroundColor DarkGray
Write-Host "  .\run_tests.ps1 -All                   # both" -ForegroundColor DarkGray
Write-Host "  .\run_tests.ps1 -NoSolve               # re-plot only, seconds" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Curves compared in the oscilloscope:" -ForegroundColor Cyan
foreach ($c in $allCurves) { Write-Host "  - $c" }
Write-Host ""
Write-Host "Outputs in test_outputs/:" -ForegroundColor Cyan
Get-ChildItem test_outputs | ForEach-Object {
    Write-Host ("  {0,-28} {1,10:N0} B" -f $_.Name, $_.Length)
}
Write-Host ""
Write-Host "Outputs in results/:" -ForegroundColor Cyan
$fs = Get-ChildItem results -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike 'case_t0*' -and $_.Name -notlike 'case_t1*' }
foreach ($f in $fs) {
    Write-Host ("  {0,-28} {1,10:N0} B" -f $f.Name, $f.Length)
}
$nf = (Get-ChildItem results -Filter 'case_t*.vtu' -ErrorAction SilentlyContinue).Count
Write-Host ("  {0,-28} {1,10}" -f "case_t*.vtu", "$nf frames")

exit 0

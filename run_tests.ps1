# ============================================================================
#  run_tests.ps1  --  跑全部 FEM 测试
#
#  流水线：solenoid3d.py (gmsh) -> ElmerGrid -> ElmerSolver 26.2
#  -> ResultOutputSolver (VTU) -> tests/test_*.py
#
#  Elmer 26.2 是从 MSYS2 mingw64 工具链编译并安装到 C:\elmer262\，
#  完全独立于已弃用的 26.1 安装 (D:\Program Files\Elmer 26.1-Release)。
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

# 1. Build the mesh (gmsh)
Write-Host ""
Write-Host "[1/5] gmsh build" -ForegroundColor Cyan
New-Item -ItemType Directory -Force test_outputs | Out-Null
& $PY solenoid3d.py --config no-coil 2>&1 | Tee-Object -FilePath test_outputs\gmsh.log | Select-Object -Last 2
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
Write-Host "[3/5] ElmerSolver 26.2" -ForegroundColor Cyan
if (Test-Path results) { Remove-Item -Recurse -Force results }
New-Item -ItemType Directory -Force results | Out-Null
& "$ELMER_HOME\bin\ElmerSolver.exe" case_simple.sif `
    2>&1 | Tee-Object -FilePath results\solver.log | Out-Null
if (-not (Test-Path results\case_t0001.vtu)) {
    Write-Host "  err  results\case_t0001.vtu not produced" -ForegroundColor Red
    Get-Content results\solver.log | Select-String 'FATAL|ERROR' | Select-Object -First 5
    exit 1
}
$vtusize = [double](Get-Item results\case_t0001.vtu).Length/1KB
Write-Host "  ok   case_t0001.vtu  ($([math]::Round($vtusize,1)) KB)" -ForegroundColor Green
Select-String -Path results\solver.log -Pattern 'ALL DONE|TOTAL TIME' | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }

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

# 5. Oscilloscope tests (spring-magnet damping 3-config)
Write-Host ""
Write-Host "[5/5] Oscilloscope tests" -ForegroundColor Cyan
& $PY -c "import sys; sys.path.insert(0, '.'); from tests.test_oscilloscope import test_config_loaded, test_damping_monotonic, test_passage_time_monotonic, test_peak_velocity_decreasing, test_magnet_actually_falls, test_vacuum_reference, test_oscilloscope_png, test_summary_txt; test_config_loaded(); test_damping_monotonic(); test_passage_time_monotonic(); test_peak_velocity_decreasing(); test_magnet_actually_falls(); test_vacuum_reference(); test_oscilloscope_png(); test_summary_txt(); print('all oscilloscope tests passed')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  err  test_oscilloscope.py failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  ok   all FEM tests passed" -ForegroundColor Green
Write-Host ""
Write-Host "Outputs in test_outputs/:" -ForegroundColor Cyan
Get-ChildItem test_outputs | Format-Table Name, Length -AutoSize
Write-Host ""
Write-Host "Outputs in results/:" -ForegroundColor Cyan
Get-ChildItem results -ErrorAction SilentlyContinue | Format-Table Name, Length -AutoSize

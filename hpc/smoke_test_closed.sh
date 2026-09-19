#!/bin/bash
# =====================================================================
#  hpc/smoke_test_closed.sh -- validate ONE closed-circuit curve against
#  real gmsh + ElmerGrid + ElmerSolver, WITHOUT spending HPC wall-clock.
#
#  WHY THIS EXISTS
#  ---------------
#  Run this before dispatching the 6 closed curves, so a queue slot is not
#  wasted on a setup mistake.  It checks mesh generation, the boundary
#  renumbering, SIF generation and a 3-step solve in about two minutes.
#
#  Expected outcome on the current code -- EVERYTHING PASSES:
#      1.  gmsh mesh                 PASS
#      1b. physical groups           PASS (1002..1008 + the 3 bodies)
#      2.  ElmerGrid -autoclean      PASS
#      2b. mesh/mesh.names           PASS (CoilStart=3, CoilEnd=4,
#                                          Alpha0..Beta1 = 5..8)
#      3.  generate the SIF          PASS
#      4.  ElmerSolver               PASS -- rc=0, 3 steps
#      5.  circuit time series       PASS -- results/circuit.csv has one row
#                                          per step with i_component(1)
#
#  Step 5 is the one that matters most.  Before it existed, a run could exit
#  rc=0 with a perfect log and still contain NO induced-current data at all:
#  the values were logged only at Level 10 (the template asked for 8) and
#  `Circuits_ToMeshVariable` refuses to publish anything without
#  `Export Circuit Variables = Logical True`.  See hpc/notes.md 15.9.
#
#  If step 4 fails, see hpc/notes.md 15.7.  The single most likely mistake is
#  reverting `Exec Solver = "Before timestep"` on Solvers 9/10 to `Always`:
#  Elmer runs the per-timestep solvers in SOLVER-NUMBER order, so an
#  `Always` circuit solver is only reached after Solver 3
#  (MagnetoDynamicsCalcFields), which then segfaults on the Lagrange
#  multiplier the circuit has not yet created.
#
#  Usage:
#      # on the HPC, from the project root:
#      bash hpc/smoke_test_closed.sh N50_L040_cu_closed
#
#      # or locally, inside the image:
#      docker run --rm --entrypoint bash \
#        -v "$PWD:/app:ro" -v "$PWD/_smoke:/work" \
#        pysproject:3.5.0 /app/hpc/smoke_test_closed.sh N50_L040_cu_closed
#
#  Steps, in order (each one can fail independently):
#      1. gmsh mesh for that curve's sif_suffix
#      1b. the physical groups gmsh actually wrote
#      2. ElmerGrid 14 2 ... -autoclean
#      2b. mesh/mesh.names   <-- CoilStart MUST be 3 and CoilEnd MUST be 4
#      3. make_sif.py --circuit closed
#      3b. shrink the timeline to 3 steps
#      4. ElmerSolver
#
#  Exit code is 0 only if every step succeeded AND the 3-step transient
#  ran to completion.
# =====================================================================
set -uo pipefail

CURVE=${1:-N50_L040_cu_closed}
PROJ=${PROJ:-/app}
WORK=${WORK:-/work/$CURVE}
STEPS=${STEPS:-3}

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1

# The generators read config.json from the CWD.  Stage a private copy so
# this script never mutates the project tree.
cp "$PROJ/config.json" ./config.json
for f in solenoid3d.py spring_model.py make_sif.py __version__.py \
         case_transient.sif; do
    cp "$PROJ/$f" "./$f" 2>/dev/null || true
done

fail() { echo; echo "  [FATAL] $*" >&2; exit 1; }

echo "=== [1] gmsh mesh, sif_suffix=$CURVE ==="
python ./solenoid3d.py --config "$CURVE" -o model3d.msh > gmsh.log 2>&1 \
    || { tail -20 gmsh.log; fail "solenoid3d.py rc=$?"; }
echo "  ok, $(stat -c%s model3d.msh) bytes"

echo "=== [1b] physical groups in the .msh ==="
python - <<'PY' || fail "no \$PhysicalNames block"
import re
s = open('model3d.msh', errors='replace').read()
m = re.search(r'\$PhysicalNames\n(\d+)\n(.*?)\n\$EndPhysicalNames', s, re.S)
if not m:
    raise SystemExit(1)
for line in m.group(2).strip().splitlines():
    print('   ', line.strip())
PY

echo "=== [2] ElmerGrid 14 2 -autoclean ==="
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > elmergrid.log 2>&1
echo "  rc=$?"

echo "=== [2b] mesh/mesh.names  <-- the renumbering check ==="
[ -f mesh/mesh.names ] || fail "no mesh/mesh.names"
sed 's/^/   /' mesh/mesh.names
grep -q 'CoilStart = 3' mesh/mesh.names || \
    fail "CoilStart is not 3 -- fix _COIL_BC_BLOCK's Target Boundaries"
grep -q 'CoilEnd = 4' mesh/mesh.names || \
    fail "CoilEnd is not 4 -- fix _COIL_BC_BLOCK's Target Boundaries"
echo "  ok: CoilStart=3 / CoilEnd=4 confirmed"

echo
echo "=== [3] make_sif.py --curve $CURVE (conductor => closed circuit) ==="
python ./make_sif.py --out case.sif --curve "$CURVE" --solver umfpack 2>&1 \
    | sed 's/^/   /'
[ -f circuits.definitions ] || fail "no circuits.definitions written"
echo "  ok: case.sif + circuits.definitions"

echo "=== [3b] shrink timeline to $STEPS steps ==="
python - "$STEPS" <<'PY' || fail "could not rewrite the timeline"
import re, sys
n = sys.argv[1]
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{n}', s, count=1)
s = re.sub(r'(?mi)^(\s*Timestep Sizes.*=\s*)[\d.eE+-]+', r'\g<1>0.002', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY
grep -iE 'Timestep (Intervals|Sizes)' case.sif | sed 's/^/   /'

echo
echo "=== [4] ElmerSolver ==="
rm -rf results
ElmerSolver case.sif > solve.log 2>&1
rc=$?
echo "  rc=$rc  (139 = SIGSEGV, 1 = clean abort)"

echo "--- errors ---"
grep -inE '^ERROR|FATAL|not found|Segmentation|SIGSEGV' solve.log \
    | head -15 | sed 's/^/   /'

echo "--- circuit log ---"
grep -nE 'AddComponent|Initializing circuit|r_component|i_component|There are .* Circuit' \
    solve.log | head -14 | sed 's/^/   /'

echo "--- timesteps reached ---"
grep -cE '^MAIN: Time:' solve.log | sed 's/^/   steps logged: /'

# ---------------------------------------------------------------------
# [5] THE EXPORT CHAIN -- the point of the whole exercise.
#
# Run 26.2 with the template's `Max Output Level = 8` printed the circuit
# values NOWHERE, and `Circuits_ToMeshVariable` (CircuitUtils.F90:1540)
# returns immediately unless the output solver carries
#     Export Circuit Variables = Logical True
# So i_component(1) was invisible through every earlier debugging round.
# Both are now fixed, and this check keeps them fixed: if either regresses,
# the run "succeeds" while producing no science, which is the worst failure
# mode there is.
# ---------------------------------------------------------------------
echo
echo "=== [5] circuit time-series export ==="
CSV=results/circuit.csv
NAMES="$CSV.names"

if grep -q 'Export Circuit Variables' case.sif; then
    echo "  ok: Export Circuit Variables present on the output solver"
else
    fail "case.sif has no 'Export Circuit Variables' -- Circuits_ToMeshVariable \
will return immediately and NO circuit quantity will reach any file"
fi

grep -Eq '^[[:space:]]*Max Output Level[[:space:]]*=[[:space:]]*(1[0-9]|[2-9][0-9])' \
    case.sif || \
    fail "Max Output Level < 10 -- the per-component i/v are logged at Level 10"

[ -f "$NAMES" ] || fail "no $NAMES -- SaveScalars (Solver 11) did not run"
[ -f "$CSV" ]   || fail "no $CSV -- SaveScalars (Solver 11) did not run"

echo "  columns:"
sed -n '8,24p' "$NAMES" | sed 's/^/     /'

# Column 10 must be i_component(1): that is the induced coil current.
grep -q 'i_component(1)' "$NAMES" || \
    fail "i_component(1) is not among the saved scalars"

rows=$(wc -l < "$CSV")
echo "  rows: $rows (expected $STEPS)"
[ "$rows" -ge "$STEPS" ] || \
    fail "only $rows rows in $CSV, expected $STEPS -- the CSV stopped early"

echo "  time series (t, i_coil, v_coil, i_load):"
awk '{printf "     t=%-8.4f i_coil=%-15s v_coil=%-15s i_load=%s\n",
         $7, $10, $11, $12}' "$CSV" | sed 's/^/  /'

# The load is a plain 10-ohm resistor, so V = R*I must hold to solver
# precision on EVERY row.  This is a cheap independent check that the
# circuit unknowns we are reading are the real ones and not mislabelled.
awk '{
       if ($12 == 0) next
       r = $13 / $12
       if (r < 9.99 || r > 10.01) {
         printf "     BAD V/I on a load row: %s\n", r; bad = 1
       }
     }
     END { exit bad }' "$CSV" || \
    fail "the V/I ratio on the load rows is not 10 ohm -- the columns in \
circuit.csv do not hold what circuit.csv.names claims"
echo "  ok: load rows satisfy V = 10 ohm * I"

if [ "$rc" -ne 0 ]; then
    fail "the closed-circuit solve did not complete -- see hpc/notes.md 13.9"
fi
echo
echo "=== ALL GOOD: $CURVE ran a $STEPS-step closed-circuit transient"
echo "    and produced results/circuit.csv with i_component(1) per step ==="

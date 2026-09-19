#!/bin/bash
# _prod_probe.sh <curve> <nsteps>
#   Full production pipeline for ONE curve at the real mesh resolution, with
#   the timestep count overridden so we can time it.  Prints mesh/solver
#   timings, the component voltages and currents, and the physics check.
set -uo pipefail
CURVE=${1:-N50_L040_cu_closed}
STEPS=${2:-10}
SOLVER=${3:-umfpack}
WORK=/work/probe
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

t0=$(date +%s)
python ./solenoid3d.py --config "$CURVE" -o model3d.msh > gmsh.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -6 gmsh.log; exit 1; }
t1=$(date +%s)
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > eg.log 2>&1
t2=$(date +%s)
NEL=$(grep -oiE '[0-9]+[[:space:]]+elements' eg.log | head -1 | grep -oE '^[0-9]+')
[ -z "$NEL" ] && NEL=$(grep -oiE 'elements[^0-9]*[0-9]+' eg.log | head -1 | grep -oE '[0-9]+$')

python ./make_sif.py --out case.sif --curve "$CURVE" --solver "$SOLVER" \
    > mk.log 2>&1 || { echo "  [FAIL] make_sif"; tail -6 mk.log; exit 1; }

python - "$STEPS" <<'PY'
import re, sys
n = sys.argv[1]
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{n}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY

# S2_ITER=1 -> force Solver 2 (WhitneyAVSolver) to BiCGStab+ILU0 instead of the
# direct factorisation.  Only a timing experiment.
if [ "${S2_ITER:-0}" = "1" ]; then
  python - <<'PY'
import re
s = open('case.sif', encoding='utf-8').read()
s, n = re.subn(
    r'(?mi)^([ \t]*)Linear System Solver[ \t]*=[ \t]*Direct[ \t]*$',
    r'\g<1>Linear System Solver = Iterative\n'
    r'\g<1>Linear System Iterative Method = BiCGStab\n'
    r'\g<1>Linear System Preconditioning = ILU0',
    s, count=1)
assert n == 1, 'Solver 2 direct block not found'
open('case.sif', 'w', encoding='utf-8').write(s)
print('  [patched] Solver 2 -> BiCGStab + ILU0')
PY
fi
t3=$(date +%s)

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
RC=$?
t4=$(date +%s)

STEPS_DONE=$(grep -cE '^MAIN: Time:' solve.log)
echo "  elements      : ${NEL:-?}"
echo "  gmsh / grid   : $((t1-t0)) s / $((t2-t1)) s"
echo "  solve         : $((t4-t3)) s"
[ "$STEPS_DONE" -gt 0 ] && echo "  per step      : $(python -c "print(f'{(${t4}-${t3})/${STEPS_DONE}:.2f}')") s"
echo "  rc=$RC  steps=$STEPS_DONE"
echo "  --- solvers that ran ---"
grep -oE 'SolveInit:[^,]*' solve.log | sort -u | head -12 | sed 's/^/    /'
echo "  --- circuit ---"
grep -E 'r_component|i_component|v_component|e_component' solve.log \
    | tail -8 | sed 's/^/    /'
echo "  --- VTU payload ---"
if [ -d results ]; then
    CNT=$(ls results/*.vtu 2>/dev/null | wc -l)
    SZ=$(du -sm results 2>/dev/null | cut -f1)
    echo "    $CNT vtu, ${SZ} MB  -> ${SZ} MB/step"
else
    echo "    (no results dir)"
fi
echo "  --- problems ---"
grep -inE '^ERROR|FATAL|Segmentation|Not found|cannot find' solve.log \
    | head -5 | sed 's/^/    /'

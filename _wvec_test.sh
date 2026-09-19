#!/bin/bash
# _wvec_test.sh <steps> <coarse-factor>
#
# Switch the coil to the W-VECTOR route and see what changes.
#
# WHY.  CircuitsAndDynamics.F90:696-700 has two ways to build `w`:
#     CoilUseWvec = .FALSE.  ->  w = -MATMUL(WBase, dBasisdx)      (scalar W)
#     CoilUseWvec = .TRUE.   ->  w = ListGetElementVectorSolution('W Vector E')
# and WPotentialSolver.F90:549-556 stores that vector as
#     wvec = MATMUL(wpot, dBasisdx)        ! = +grad(W), opposite sign
#     wvecvar % Values(...) = wvec(k)/Wnorm
# i.e. the VECTOR route divides by Wnorm = the volume average of |w|
# (WPotentialSolver.F90:684-685,636-637), while the SCALAR route does not.
#
# The sign difference is harmless (w enters both coupling terms linearly, so
# the self-inductance ~ N_j^2 (w,.)(w,.) is sign-blind).  The 1/Wnorm factor
# is NOT: it rescales |w| and therefore R = N_j^2 INTEGRAL |w|^2/sigma.
#
# So r_component(1) is an instant read-out of Wnorm:
#     unchanged  => Wnorm == 1 and the two routes are equivalent
#     scaled by Wnorm^2 => the routes differ, and we have our magnitude bug
set -uo pipefail
STEPS=${1:-20}
COARSE=${2:-2}
WORK=/work/wv
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

python - "$COARSE" <<'PY'
import json, sys
k = float(sys.argv[1])
d = json.load(open('config.json', encoding='utf-8'))
m = d['mesh']
for key in ('lc_min_m', 'lc_coil_m', 'lc_magnet_m', 'lc_slit_m'):
    m[key] = float(m[key]) * k
m['lc_max_m'] = max(float(m['lc_max_m']), float(m['lc_min_m']))
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
PY

python ./solenoid3d.py --config N50_L040_cu_closed -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -5 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
python ./make_sif.py --out case.sif --curve N50_L040_cu_closed --solver umfpack \
    > m.log 2>&1 || { echo "  [FAIL] make_sif"; tail -5 m.log; exit 1; }

python - "$STEPS" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)

# --- the switch, exactly as the upstream reference does it ---------------
#     fem/tests/circuits_transient_stranded_wvector/sif/6480.sif:197-198
#       Coil Use W Vector = Logical True
#       W Vector Variable Name = String "W Vector E"
s, n1 = re.subn(
    r'(?m)^(\s*Coil Type\s*=\s*String\s+stranded\s*)$',
    r'\1\n  Coil Use W Vector = Logical True\n'
    r'  W Vector Variable Name = String "W Vector E"',
    s, count=1)
print(f'  [patch] coil w-vector keys added: {n1}')
assert n1 == 1, 'could not find the stranded Coil Type line'
open('case.sif', 'w', encoding='utf-8').write(s)
PY

echo "  --- the coil component now reads ---"
sed -n '/^Component 1/,/^End/p' case.sif | sed 's/^/    /'

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  rc=$?  steps=$(grep -ac '^MAIN: Time:' solve.log)"

echo "  --- W Vector E created? ---"
grep -anE 'W Vector E|WPotential.*Vector|Creating variable' solve.log \
    | head -8 | sed 's/^/    /'

python - <<'PY'
import math
rows = []
for line in open('results/circuit.csv'):
    f = line.split()
    if len(f) >= 17:
        rows.append((float(f[6]), float(f[9]), float(f[13]), float(f[15])))
if not rows:
    print('  [FAIL] no circuit.csv rows'); raise SystemExit(1)
Rc, Rl = rows[0][2], rows[0][3]
print(f'  r_component(1) = {Rc:.9g}    (scalar route gave 3.016937402020E-01)')
print(f'  r_component(2) = {Rl:.9g}')
if Rc > 0:
    print(f'  implied Wnorm  = sqrt(R_new/R_old) = '
          f'{math.sqrt(Rc/3.016937402020e-01):.6f}')
print('  t(s)       i(A)              ratio')
prev = None
for t, i, _, _ in rows[:26]:
    r = f'{i/prev:8.4f}' if prev else '       -'
    print(f'  {t:<10.4f} {i:<18.6e} {r}')
    prev = i
PY

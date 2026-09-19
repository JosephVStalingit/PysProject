#!/bin/bash
# _renumber_test.sh <R_load_ohm> <steps> <coarse>
#
# LAST structural hypothesis (notes.md 15.12).  The upstream reference numbers
# its circuit solver BELOW the field solver:
#
#     Solver 5  CircuitsAndDynamics   Exec Solver = Always
#     Solver 6  WhitneyAVSolver
#     Solver 7  MagnetoDynamicsCalcFields
#
# Ours is inverted (WhitneyAVSolver = 2, CircuitsAndDynamics = 9) and we
# compensate with `Before timestep`.  This test renumbers the whole SIF to
# match the reference and drops the compensation:
#
#     old -> new   1->1 RigidMeshMapper, 5->2, 6->3 (Direction),
#                  7->4 RotM, 8->5 WPotential, 9->6 Circuits,
#                  10->7 CircuitsOutput, 2->8 WhitneyAVSolver,
#                  3->9 CalcFields, 4->10 ResultOutput, 11->11 SaveScalars
#
# If i then tracks 1/R_total, that was the bug.
set -uo pipefail
RLOAD=${1:-10}
STEPS=${2:-40}
COARSE=${3:-3}
WORK=/work/rn
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

python - "$RLOAD" "$COARSE" <<'PY'
import json, sys
want, k = float(sys.argv[1]), float(sys.argv[2])
d = json.load(open('config.json', encoding='utf-8'))
m = d['mesh']
for key in ('lc_min_m', 'lc_coil_m', 'lc_magnet_m'):
    m[key] = float(m[key]) * k
m['lc_max_m'] = max(float(m['lc_max_m']), float(m['lc_min_m']))
for v in d['curves'].values():
    if isinstance(v, dict) and v.get('N_turns', 0) > 0:
        v['R_load_ohm'] = want
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
print(f'  R_load={want}')
PY

python ./solenoid3d.py --config N50_L040_cu_closed -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -5 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
python ./make_sif.py --out case.sif --curve N50_L040_cu_closed --solver umfpack \
    > m.log 2>&1 || echo "  [FAIL] make_sif"

python - "$STEPS" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()

# timestep count
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)

MAP = {1: 1, 5: 2, 6: 3, 7: 4, 8: 5, 9: 6, 10: 7, 11: 11, 2: 8, 3: 9, 4: 10}

# 1. solver headers:  ^Solver N   ->   ^Solver M   (two-pass via placeholder)
def _blk(m):
    n = int(m.group(1))
    return f'Solver @@{MAP.get(n, n)}@@'
s = re.sub(r'(?m)^Solver (\d+)\s*$', _blk, s)
assert '@@' in s, 'no solver headers were renumbered'
s = re.sub(r'@@(\d+)@@', r'\1', s)

# 2. Active Solvers list, now in ascending numeric order
s = re.sub(r'(?m)^(\s*Active Solvers\()\d+(\)\s*=\s*)[0-9 \t]+$',
           r'\g<1>11\g<2>1 2 3 4 5 6 7 8 9 10 11', s, count=1)

# 3. the circuit pair goes back to `Always` -- numeric order now guarantees
#    they run before WhitneyAVSolver
s = s.replace('Exec Solver = "Before timestep"', 'Exec Solver = "Always"')
open('case.sif', 'w', encoding='utf-8').write(s)
PY

echo "  --- new solver layout ---"
grep -nE '^Solver [0-9]+|^Active Solvers|Procedure *=|Exec Solver *=' case.sif \
    | grep -vE '^\s*[0-9]+: *!' | head -40 | sed 's/^/    /'

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  rc=$?"

python - <<'PY'
rows = []
try:
    for line in open('results/circuit.csv'):
        f = line.split()
        if len(f) >= 17:
            try: rows.append([float(x) for x in f])
            except ValueError: pass
except FileNotFoundError:
    print('  [FAIL] no circuit.csv'); raise SystemExit(1)
if not rows:
    print('  [FAIL] no rows'); raise SystemExit(1)
r = rows[0]
print(f'  r_component(1)={r[13]:.6g}   r_component(2)={r[15]:.6g}')
t=[x[6] for x in rows]; i=[x[9] for x in rows]
k=max(range(len(i)), key=lambda n: abs(i[n]))
print(f'  peak |i| = {abs(i[k]):.6e} A at t={t[k]:.4f} s')
print(f'  i at t={t[-1]:.3f} s = {i[-1]:+.6e} A')
PY

#!/bin/bash
# _nomt_test.sh <R_load_ohm>
#
# HYPOTHESIS (notes.md 15.12): the circuit matrix never reaches the solved
# system because our Solver 9 is missing the two keys the upstream reference
# `circuits_transient_stranded_wvector/sif/6480.sif:87-93` carries:
#
#     Solver 5
#        Exec Solver = Always
#        Equation = Circuits
#        Variable = X                 <-- we do not set this
#        No Matrix = Logical True     <-- we do not set this
#        Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics"
#     End
#
# `No Matrix` tells Elmer that this solver drives the circuit matrix through
# the AddMatrix mechanism instead of the standard per-solver matrix.  Without
# it the circuit block -- resistances included -- can be silently dropped
# while `Comp % Resistance` keeps its accumulated value and `r_component(1)`
# is still reported correctly.  That is EXACTLY the observed signature.
set -uo pipefail
RLOAD=${1:-10}
STEPS=${2:-40}
COARSE=${3:-3}
WORK=/work/nm
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
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)

# --- the two keys from the upstream reference -----------------------------
# anchor on the Procedure line of the ASSEMBLING solver (the one without
# "CircuitsOutput"), since comment lines sit between `Solver 9` and the keys.
s, n = re.subn(
    r'(?m)^(\s*)(Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics")',
    r'\1Variable = X\n\1No Matrix = Logical True\n\1\2',
    s, count=1)
print(f'  [patch] Solver 9 Variable/No Matrix: {n}')
assert n == 1, 'could not find the CircuitsAndDynamics Procedure line'
open('case.sif', 'w', encoding='utf-8').write(s)
PY

echo "  --- Solver 9 as patched ---"
sed -n '/^Solver 9/,/^End/p' case.sif | head -12 | sed 's/^/    /'

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  rc=$?"

python - <<'PY'
rows = []
for line in open('results/circuit.csv'):
    f = line.split()
    if len(f) >= 17:
        try: rows.append([float(x) for x in f])
        except ValueError: pass
if not rows:
    print('  [FAIL] no rows'); raise SystemExit(1)
r = rows[0]
print(f'  r_component(1)={r[13]:.6g}   r_component(2)={r[15]:.6g}')
t=[x[6] for x in rows]; i=[x[9] for x in rows]
k=max(range(len(i)), key=lambda n: abs(i[n]))
print(f'  peak |i| = {abs(i[k]):.6e} A at t={t[k]:.4f} s')
print(f'  i at t={t[-1]:.3f} s = {i[-1]:+.6e} A')
PY

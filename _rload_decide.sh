#!/bin/bash
# _rload_decide.sh <R_load_ohm> <steps> <coarse>
#
# DECISIVE TEST for the "circuit does not constrain i" hypothesis (notes 15.12).
#
# A correct model has i = eps/(R_coil + R_load), so comparing
#     R_load = 10  ohm   (R_total =  10.3)
#     R_load = 1e6 ohm   (R_total = 1e6)   <- a near-open circuit
# must give currents differing by a factor ~1e5.  If the two curves are the
# same, the circuit unknowns are NOT feeding back into the field and every
# induced-current number from this model is meaningless.
#
# Coarsened mesh: the suspected decoupling (if real) is a structural property
# of the circuit assembly, not a discretisation effect, so a coarse mesh
# reproduces it in minutes instead of tens of minutes.
set -uo pipefail
RLOAD=${1:-10}
STEPS=${2:-60}
COARSE=${3:-2}
CURVE=${CURVE:-N50_L040_cu_closed}
WORK=/work/rl
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

python - "$RLOAD" "$COARSE" <<'PY'
import json, sys
want, k = float(sys.argv[1]), float(sys.argv[2])
d = json.load(open('config.json', encoding='utf-8'))
# coarsen everything EXCEPT the slit ratio: keep lc_slit >= slit_width so we
# do not re-enter the 15.11 instability
m = d['mesh']
for key in ('lc_min_m', 'lc_coil_m', 'lc_magnet_m'):
    m[key] = float(m[key]) * k
m['lc_max_m'] = max(float(m['lc_max_m']), float(m['lc_min_m']))
for kk, v in d['curves'].items():
    if isinstance(v, dict) and v.get('N_turns', 0) > 0:
        v['R_load_ohm'] = want
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
print(f"  R_load={want}  lc_coil={m['lc_coil_m']:.4f}  lc_slit={m['lc_slit_m']:.4f}")
PY

python ./solenoid3d.py --config $CURVE -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -5 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
NEL=$(grep -oiE '[0-9]+[[:space:]]+elements' e.log | head -1 | grep -oE '^[0-9]+')
python ./make_sif.py --out case.sif --curve $CURVE --solver umfpack \
    > m.log 2>&1 || echo "  [FAIL] make_sif"

echo "  --- the SIF load ---"
grep -aE '^ *(Resistance|Component Type) =' case.sif | sed 's/^/    /'

python - "$STEPS" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  elements=$NEL rc=$?"

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
print(f'  peak |i| = {abs(i[k]):.6e} A  at t={t[k]:.4f} s')
print(f'  i at t={t[-1]:.3f} s = {i[-1]:.6e} A')
print('  t      i(A)')
for n in range(0, len(rows), max(1, len(rows)//12)):
    print(f'  {t[n]:<8.4f} {i[n]:+.6e}')
PY

#!/bin/bash
# _coilr_test.sh <component1_resistance_ohm>
#
# FINAL DECISIVE TEST.  Setting `Resistance` on the coil Component flips
# `Comp % UseCoilResistance` to TRUE, which reroutes the coil's resistance
# through AddComponentEquationsAndCouplings:465-471 instead of
# Add_stranded:705, and makes `r_component(1)` report the given value.
#
# If the circuit really constrains the current, a 1e6 ohm coil in series with
# the 10 ohm load MUST collapse i by ~1e5.  If i does not move, the resistive
# circuit block is definitively not reaching the solve.
set -uo pipefail
RCOIL=${1:-1000000}
STEPS=${2:-40}
COARSE=${3:-3}
WORK=/work/cr
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

python - "$COARSE" <<'PY'
import json, sys
k = float(sys.argv[1])
d = json.load(open('config.json', encoding='utf-8'))
m = d['mesh']
for key in ('lc_min_m', 'lc_coil_m', 'lc_magnet_m'):
    m[key] = float(m[key]) * k
m['lc_max_m'] = max(float(m['lc_max_m']), float(m['lc_min_m']))
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
PY

python ./solenoid3d.py --config N50_L040_cu_closed -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -5 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
python ./make_sif.py --out case.sif --curve N50_L040_cu_closed --solver umfpack \
    > m.log 2>&1 || echo "  [FAIL] make_sif"

python - "$STEPS" "$RCOIL" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)
# add an explicit Resistance to the COIL component (the one with Coil Type)
s, n = re.subn(
    r'(?m)^(\s*)(Coil Type\s*=\s*String\s+stranded\s*)$',
    rf'\1\2\n\1Resistance = Real {sys.argv[2]}',
    s, count=1)
print(f'  [patch] coil Resistance = {sys.argv[2]}  ({n})')
assert n == 1
open('case.sif', 'w', encoding='utf-8').write(s)
PY

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  rc=$?"
grep -aE 'Using coil resistance|Writing resistor equation' solve.log | head -3 | sed 's/^/    /'

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
PY

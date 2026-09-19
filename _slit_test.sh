#!/bin/bash
# _slit_test.sh <lc_slit_m> <steps>
#
# Isolate the SLIT.  Everything stays at the production mesh EXCEPT lc_slit_m,
# which is the only thing that controls whether the 3.5 mm slit is resolved:
#
#     lc_slit   slit resolved?   observed per-step gain
#     10 mm     no (10 > 3.5)    1.000   STABLE
#      5 mm     marginal         1.007
#    2.5 mm     yes              1.777   EXPLOSIVE   <- production
#
# If coarsening ONLY the slit removes the growth while lc_coil/lc_magnet stay
# at production resolution, the instability lives in the slit region (bad
# elements, or the W-potential's jump across the cut).  If the growth stays,
# it is the coil resolution as a whole and the slit is a red herring.
set -uo pipefail
LCSLIT=${1:-0.008}
STEPS=${2:-14}
WORK=/work/slit
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

python - "$LCSLIT" <<'PY'
import json, sys
d = json.load(open('config.json', encoding='utf-8'))
m = d['mesh']
m['lc_slit_m'] = float(sys.argv[1])
m['lc_min_m'] = min(float(m['lc_min_m']), float(sys.argv[1]))
print(f"  production mesh kept; lc_slit_m = {m['lc_slit_m']} "
      f"(lc_coil={m['lc_coil_m']}, lc_magnet={m['lc_magnet_m']}, "
      f"lc_min={m['lc_min_m']})")
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
PY

python ./solenoid3d.py --config N50_L040_cu_closed -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -5 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
NEL=$(grep -oiE '[0-9]+[[:space:]]+elements' e.log | head -1 | grep -oE '^[0-9]+')
python ./make_sif.py --out case.sif --curve N50_L040_cu_closed --solver umfpack \
    > m.log 2>&1 || { echo "  [FAIL] make_sif"; tail -5 m.log; exit 1; }

python - "$STEPS" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY

T0=$(date +%s)
rm -rf results
ElmerSolver case.sif > solve.log 2>&1
RC=$?
T1=$(date +%s)
echo "  elements=$NEL  rc=$RC  wall=$((T1-T0))s"

python - <<'PY'
import math
rows = []
for line in open('results/circuit.csv'):
    f = line.split()
    if len(f) >= 17:
        rows.append((float(f[6]), float(f[9]), float(f[13]), float(f[15])))
if len(rows) < 4:
    print('  [FAIL] no rows'); raise SystemExit(1)
print(f'  r_component(1) = {rows[0][2]:.9g}')
print('  t(s)       i(A)              ratio')
prev = None
for t, i, _, _ in rows:
    r = f'{i/prev:9.5f}' if prev else '        -'
    print(f'  {t:<10.4f} {i:<18.6e} {r}')
    prev = i
# growth per STEP (not per second) is the mesh-only fingerprint
i0, i1 = rows[3][1], rows[-1][1]
n = len(rows) - 4
if i0 > 0 and i1 > 0 and n > 0:
    g = (i1 / i0) ** (1.0 / n)
    print(f'  per-step gain = {g:.6f}')
    print('  VERDICT: ' + ('STABLE (gain ~ 1)' if g < 1.02
                           else 'UNSTABLE'))
PY

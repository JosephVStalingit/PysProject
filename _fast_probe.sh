#!/bin/bash
# _fast_probe.sh <curve> <steps> [coarsen-factor]
#
# A COARSE-MESH diagnostic harness.  The instability we are chasing is a
# property of the circuit<->field coupling, NOT of the mesh, so a coarse
# mesh reproduces it in ~2 s/step instead of 28 s/step.  That gives a fast
# iteration loop for testing hypotheses.
#
# It prints the i_component(1) series and fits the exponential rate, then
# reports the implied |L| = R_total / rate so it can be compared against the
# analytical coil inductance.
set -uo pipefail
CURVE=${1:-N50_L040_cu_closed}
STEPS=${2:-60}
COARSE=${3:-4}
WORK=/work/fast
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
print(f"  coarsened x{k}: lc_min={m['lc_min_m']:.4f} lc_coil={m['lc_coil_m']:.4f} "
      f"lc_slit={m['lc_slit_m']:.4f}")
PY

python ./solenoid3d.py --config "$CURVE" -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -6 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
NEL=$(grep -oiE '[0-9]+[[:space:]]+elements' e.log | head -1 | grep -oE '^[0-9]+')
python ./make_sif.py --out case.sif --curve "$CURVE" --solver umfpack \
    > m.log 2>&1 || { echo "  [FAIL] make_sif"; tail -6 m.log; exit 1; }

python - "$STEPS" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', rf'\g<1>{sys.argv[1]}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY

# DT=<seconds> -> override the timestep.  If the instability rate in /s is
# proportional to dt it is a TIME-discretisation problem; if it stays fixed
# it is a spatial (mesh) one.
if [ -n "${DT:-}" ]; then
  python - "$DT" <<'PY'
import re, sys
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Sizes\s*=\s*)[\d.eE+-]+', rf'\g<1>{sys.argv[1]}', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
print(f'  [patched] Timestep Sizes = {sys.argv[1]}')
PY
fi

# NJ_SCALE=<factor> -> scale `Stranded Coil N_j` in the generated SIF.
# The coil's self-inductance goes as N_j^2, so IF the instability is really
# the L of an unstable L-R loop its rate must scale as R_total/N_j^2.  If it
# does not move at all, the growth is NOT the coil inductance.
if [ -n "${NJ_SCALE:-}" ]; then
  python - "$NJ_SCALE" <<'PY'
import re, sys
k = float(sys.argv[1])
s = open('case.sif', encoding='utf-8').read()

def scale(m):
    return f'{m.group(1)}{float(m.group(2)) * k:.6e}'

s, n = re.subn(r'(?m)^(\s*Stranded Coil N_j\s*=\s*Real\s*)([\d.eE+-]+)',
               scale, s)
open('case.sif', 'w', encoding='utf-8').write(s)
print(f'  [patched] Stranded Coil N_j x{k} ({n} occurrences)')
PY
  grep -in 'Stranded Coil N_j' case.sif | sed 's/^/    /'
fi

# BDF_ORDER=1 -> force backward Euler.  CircuitsAndDynamics.F90:642 does
#     IF (Solver % Order < 2 .OR. GetTimeStep() <= 2) THEN tscl = 1.0
#     ELSE                                             tscl = 1.5
# so with BDF2 the EMF coefficient JUMPS 50% at step 3 -- a spurious kick
# that the fine mesh amplifies into an instability.
if [ -n "${BDF_ORDER:-}" ]; then
  python - "$BDF_ORDER" <<'PY'
import re, sys
order = sys.argv[1]
s = open('case.sif', encoding='utf-8').read()
if re.search(r'(?mi)^\s*BDF Order\s*=', s):
    s = re.sub(r'(?mi)^(\s*BDF Order\s*=\s*)\d+', rf'\g<1>{order}', s, count=1)
else:
    s, n = re.subn(r'(?m)^(\s*Timestepping Method\s*=.*)$',
                   rf'\1\n  BDF Order = {order}', s, count=1)
    assert n == 1, 'no Timestepping Method line to anchor on'
open('case.sif', 'w', encoding='utf-8').write(s)
print(f'  [patched] BDF Order = {order}')
PY
  grep -inE 'Timestepping|BDF Order' case.sif | sed 's/^/    /'
fi

T0=$(date +%s)
rm -rf results
ElmerSolver case.sif > solve.log 2>&1
RC=$?
T1=$(date +%s)

echo "  elements=${NEL:-?}  rc=$RC  wall=$((T1-T0))s"

python - <<'PY'
import math, re

rows = []
for line in open('results/circuit.csv'):
    f = line.split()
    if len(f) >= 17:
        rows.append((float(f[6]), float(f[9]), float(f[10]), float(f[13]), float(f[14])))
if not rows:
    print('  [FAIL] no data rows')
    raise SystemExit(1)

print(f"  rows={len(rows)}")
R_coil, R_load = rows[0][3], None
# r_component(2) is column 16 (0-based 15)
rows = []
for line in open('results/circuit.csv'):
    f = line.split()
    if len(f) >= 17:
        rows.append((float(f[6]), float(f[9]), float(f[10]),
                     float(f[13]), float(f[14]), float(f[15])))
R_coil, R_load = rows[0][3], rows[0][5]
R_tot = R_coil + R_load
print(f"  R_coil={R_coil:.6g}  R_load={R_load:.6g}  R_total={R_tot:.6g}")

print('  t(s)       i_coil(A)          ratio    |L|implied(H)')
prev = None
for (t, i, v, rc, pc, rl) in rows[:40]:
    r = f'{i/prev:7.4f}' if prev not in (None, 0.0) else '      -'
    l = f'{R_tot/math.log(i/prev):.6f}' if prev not in (None, 0.0) and i > 0 and prev > 0 else '-'
    print(f'  {t:<10.4f} {i:<18.6e} {r}   {l}')
    prev = i

n = len(rows) - 1
if n >= 4:
    i0, i1 = rows[2][1], rows[-1][1]
    t0, t1 = rows[2][0], rows[-1][0]
    if i0 > 0 and i1 > 0:
        rate = math.log(i1 / i0) / (t1 - t0)
        print(f"  fitted rate = {rate:.1f} /s  ->  |L| = R_total/rate = "
              f"{R_tot/rate*1000:.4f} mH")
        # A 50-turn 22.5 mm-mean-radius 40 mm coil is ~20 mH, NOT 2 mH.
        print(f"  M_vs_N2      : |L|/N^2 = {R_tot/rate/2500*1e9:.4f} nH/turn^2")
PY

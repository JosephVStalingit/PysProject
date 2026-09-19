#!/bin/bash
# DECISIVE TEST: freeze the magnet (zero amplitude) so there is NO external
# EMF.  A correct circuit must then hold i == 0 for ever.  If the current
# still grows exponentially, the growth is NOT motion-driven -- it is a
# sign/feedback problem in the coil-circuit coupling.
set -uo pipefail
WORK=/work/frozen
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
for f in config.json solenoid3d.py spring_model.py make_sif.py \
         case_transient.sif __version__.py; do cp "/app/$f" . ; done

# A = |z_release - z_eq| = 0  =>  z(t) = z_eq, the magnet never moves.
python - <<'PY'
import json
d = json.load(open('config.json', encoding='utf-8'))
d['spring']['z_release_m'] = d['spring']['z_eq_m']
json.dump(d, open('config.json', 'w', encoding='utf-8'), indent=2)
print(f"  z_release set to z_eq = {d['spring']['z_eq_m']} -> amplitude 0")
PY

python ./solenoid3d.py --config N50_L040_cu_closed -o model3d.msh > g.log 2>&1 \
    || { echo "  [FAIL] gmsh"; tail -6 g.log; exit 1; }
ElmerGrid 14 2 model3d.msh -out mesh -autoclean > e.log 2>&1
python ./make_sif.py --out case.sif --curve N50_L040_cu_closed --solver umfpack \
    > m.log 2>&1 || { echo "  [FAIL] make_sif"; tail -6 m.log; exit 1; }

python - <<'PY'
import re
s = open('case.sif', encoding='utf-8').read()
s = re.sub(r'(?mi)^(\s*Timestep Intervals.*=\s*)\d+', r'\g<1>30', s, count=1)
open('case.sif', 'w', encoding='utf-8').write(s)
PY

rm -rf results
ElmerSolver case.sif > solve.log 2>&1
echo "  rc=$?"
echo "  --- i_component(1), FIRST 6 and LAST 6 of 30 steps ---"
echo "  t(s)       i_coil(A)"
awk '{printf "    %-10.4f %s\n", $7, $10}' results/circuit.csv 2>/dev/null \
    | head -6 | sed 's/^/  /'
echo "     ..."
awk '{printf "    %-10.4f %s\n", $7, $10}' results/circuit.csv 2>/dev/null \
    | tail -6 | sed 's/^/  /'
echo "  --- verdict ---"
awk 'BEGIN{m=0} {v=$10+0; if(v<0)v=-v; if(v>m)m=v} END{
       printf "    max |i| over 30 static steps = %.6e A\n", m;
       if (m < 1e-9) print "    FROZEN TEST: i stays ~0 -> the coupling is STABLE";
       else print "    FROZEN TEST: i GROWS with NO motion -> the growth is an INSTABILITY";}' \
    results/circuit.csv 2>/dev/null

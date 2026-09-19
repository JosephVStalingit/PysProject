#!/bin/bash
#SBATCH --job-name=csolver
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:45:00
#SBATCH --output=csolver-%j.out
#SBATCH --error=csolver-%j.err
#
# test_coilsolver_modern.sh -- variant D: use UPSTREAM's W VECTOR method.
#
# WHAT WE KNOW NOW (2026-09-16 evening)
# ------------------------------------
#   eps_FEM * N = 0.960 / 1.155 / 1.172 / 1.206 V  for N = 1 / 25 / 50 / 100
#       => eps_FEM = 1.16/N volts, exact 1/N over four orders of magnitude,
#          where it must be proportional to N.  The current follows it.
#   sigma scan on the production setup (900 steps):
#       sigma x312  =>  r_component(1) x312  but i unchanged to 5 digits
#       => the loop impedance is entirely NON-OHMIC.
#   `Stranded Coil N_j` in our SIF is IGNORED by Add_stranded; Elmer computes
#       Comp % N_j = NofTurns / A_coil internally.  Proven by the N1 pair:
#       turns=1 in both, N_j and sigma both x25,
#           r_component(1) = 6.034e-3 -> 2.41e-4   (= 1/25, not 25)
#       and 2.41e-4 = ((1/2.0e-4)**2 / 2.8671e6) * 2.768e-5  exactly.
#
# THE ONE PATH NOT YET TESTED
# ---------------------------
# CircuitsAndDynamics.F90:641-648 branches on `Coil Use W Vector`:
#     FALSE -> w = -grad W     (scalar W potential, WPotentialSolver/Wsolve)
#     TRUE  -> w = W vector    (modern CoilSolver)
# We use the FIRST.  Upstream's own circuits_transient_stranded_full_coil
# uses the SECOND (`Procedure = "CoilSolver" "CoilSolver"` +
# `Coil Use W Vector = Logical True` + `W Vector Variable Name`).
#
# The earlier A/B (job 122244593) tried the second path but only changed the
# COMPONENT keys, leaving Solver 8 on Wsve -- so no `CoilCurrent e` vector
# existed, w came back zero, and the coil decoupled entirely (i = 0,
# r_comp1 = 0).  THAT IS WHY IT PROVED NOTHING.
#
# This test changes Solver 8 itself to `CoilSolver`, adds the upstream
# Component keys and the CoilSolver normalisation keys, and runs N=25 on the
# existing production mesh for 30 steps.
#
# PREDICTION if the W-vector path is the correct one:
#     i stops falling as 1/N -- at N=25 it should be of order
#     eps_ana/R_total ~ 0.18/10.15 ~ 18 mA, not 4.55 mA.
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

SRC=$HOME/pysproject/cases/N25_L040_cu_closed
R=$HOME/csolver
rm -rf "$R"; mkdir -p "$R/N25"
V=$R/N25
cp "$SRC/case.sif" "$SRC/circuits.definitions" "$SRC/config.json" \
   "$SRC/model3d.msh" "$V/" 2>/dev/null
cp -r "$SRC/mesh" "$V/mesh" 2>/dev/null

echo "host    : $(hostname)"
echo "started : $(date)"
echo

# available CoilSolver-ish procedures in the installed Elmer
echo "=== Procedure lines the installed module offers ==="
strings $HOME/elmer262/share/elmersolver/lib/CoilSolver.so 2>/dev/null \
    | grep -iE '^(CoilSolver|Wsolve|CoilSolverUtils)' | sort -u | head
ls -la $HOME/elmer262/share/elmersolver/lib/ | grep -i coil
echo

# 1) swap Solver 8 from Wsolve to CoilSolver + upstream keys
awk '
  /^  Procedure = "WPotentialSolver" "Wsolve"/ {
      print "  Procedure = \"CoilSolver\" \"CoilSolver\""; swapped++; next }
  # 2) 30 steps
  /^  Timestep Intervals/ {print "  Timestep Intervals     = 30"; next}
  # 3) CoilSolver normalisation keys, inserted after the CG line
  /^  Linear System Iterative Method = CG/ {print; if (done==0) {
      print "  Normalize Coil Current = Logical True";
      print "  Fix Input Current Density = True";
      print "  Coil Closed = Logical True";
      print "  Narrow Interface = Logical True";
      print "  Save Coil Set = Logical True";
      print "  Save Coil Index = Logical True";
      print "  Calculate Elemental Fields = Logical True";
      done=1 } ; next }
  # 4) upstream Component keys
  /^  Coil Type/ {print;
      print "  Coil Use W Vector = Logical True";
      print "  W Vector Variable Name = String \"CoilCurrent e\"";
      print "  Desired Current Density = Real 1";
      print "  Electrode Area = Real 1"; next }
  {print}
  END { printf "  [awk] Solver-8 procedure swapped: %d\n", swapped > "/dev/stderr" }
' "$SRC/case.sif" > "$V/case.sif"

echo "=== variant D changed lines ==="
grep -nE 'Procedure =|Normalize Coil Current|Fix Input|Coil Closed|Narrow|Save Coil|Calculate Elemental|Coil Use W Vector|W Vector Variable|Desired Current|Electrode Area|Timestep Intervals' \
     "$V/case.sif" | sed 's/^/  /'
echo

cd "$V" || exit 1
echo "=== running ==="
$HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
rc=$?
echo "ElmerSolver rc=$rc   steps done: $(grep -c 'MAIN: Time' solve.log)"
if [ -f results/circuit.csv ]; then
    echo "  step   i_component(1)   v_component(1)   r_component(1)"
    awk 'NR>1{printf "  %4d   %14.6e   %14.6e   %12.6e\n", NR, $10, $11, $14}' \
        results/circuit.csv | head -20
    awk 'NR>1{f=($10<0?-$10:$10); if(f>m)m=f} END{printf "  peak |i| = %.6e A\n", m}' \
        results/circuit.csv
    echo "  (compare: Wsolve path gives peak |i| = 4.549755e-03 A,"
    echo "   r_comp1 = 1.508469e-01 ohm)"
else
    echo "[err] no circuit.csv -- tail of solve.log:"
    tail -40 solve.log
fi
echo
echo "=== errors/warnings worth reading ==="
grep -nE 'ERROR|FATAL|WARNING|Segmentation|not obtain' solve.log | head -20
echo "finished : $(date)"

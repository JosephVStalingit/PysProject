#!/bin/bash
#SBATCH --job-name=csolv3
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:45:00
#SBATCH --output=csolv3-%j.out
#SBATCH --error=csolv3-%j.err
#
# test_coilsolver_v2.sh -- variant E: the UPSTREAM full-coil CoilSolver path.
#
# Job history on this script:
#   122247342  died in LoadInputFile: `Number of Equations: 4 / Entry missing
#              for: Equation 2` -- the extra Equation block was numbered 4 and
#              Elmer requires the numbered blocks to be contiguous.
#   (this run) renumbered to Equation 2, `Variable = W` deleted (CoilSolver
#              owns it, F90:73) and Equation 2 confirmed present.
#
# WHY (job 122245457, variant D, got us 90% of the way)
# ----------------------------------------------------
# Variant D swapped Solver 8 to `Procedure = "CoilSolver" "CoilSolver"` and
# CoilSolver_Init ran -- then died on:
#
#   ERROR:: CoilSolver_init: "Electrode Boundaries(1)" not consistent with
#           given "Coil Start" in bc 3
#
# That message is CoilSolver.F90:140-142.  Reading 130-154 shows the
# semantics are the OPPOSITE of what our SIF assumes:
#
#   ElBCs => ListGetIntegerArray(Params,'Electrode Boundaries',Found)   ! 130
#   BC => CurrentModel % BCs(ElBCs(1)) % Values                         ! 138
#   IF( ListGetLogical(BC,'Coil Start',Found) ) CALL Fatal(...)         ! 140-142
#   CALL ListAddLogical( BC,'Coil End',.TRUE.)                          ! 144
#   BC => CurrentModel % BCs(ElBCs(2)) % Values                         ! 146
#   IF( ListGetLogical(BC,'Coil End',Found) ) CALL Fatal(...)           ! 148-150
#   CALL ListAddNewLogical( BC,'Coil Start',.TRUE.)                     ! 152
#
# i.e. Electrode Boundaries(1) becomes *Coil End* and (2) becomes
# *Coil Start*, and CoilSolver REFUSES to run if we pre-set them.  Our
# template writes `Integer 3 4` with `Coil Start` on bc 3 -> instant Fatal.
# So: STRIP `Coil Start`/`Coil End` from bc 3/4 and let CoilSolver own them.
#
# Three more things variant D was missing, all now read off the source and
# off upstream's own full-coil test
# (fem/tests/circuits_transient_stranded_full_coil/sif/coil.sif):
#
#  1. CoilSolver.F90:387 Fatals when a body is active in an Equation with
#     CoilSolver but is not in any Component.  Our SIF puts ALL THREE bodies
#     on `Equation 1` with `Active Solvers(10) = 5 6 7 8 1 9 2 3 10 11`, so
#     Solver 8 must move to an Equation used ONLY by Body 1.  Upstream does
#     exactly this: Eq 1 = "for coil", Eq 2 = "for air", Body 1 -> Eq 1.
#
#  2. CoilSolver.F90:358-359 Fatals if `Coil Normal` sits in the SOLVER --
#     it must be on the COMPONENT (upstream coil.sif:62, with the Solver
#     copy commented out at :112).
#
#  3. `CoilSolver.F90:2378  NormCoeff = DesiredCurrentDensity /
#     SQRT(SUM(GradPot**2))` -- CoilSolver normalises the wire vector to a
#     UNIT field whose magnitude is `Desired Current Density` (default 1.0).
#     That independently confirms the |w| = 1 we had only inferred from the
#     2.1%-accurate resistance fit
#         R = N_j**2 * V_coil / sigma_eff
#     (2.827e-5 * (1.25e5)**2 / 2.8671e6 = 0.1541 vs measured 0.1508).
#
# WHAT MAKES THIS WORTH A RUN
# ---------------------------
# This path needs NO radial slit, NO DirectionSolver, NO RotMSolver and NO
# Alpha/Beta frame -- all four of which are OUR OWN constructions and the
# only remaining N-dependent geometry in the model.  Upstream's own comment
# (coil.sif:5-6) says the W-vector exists precisely so you can do a full
# coil "without cuts".
#
# PREDICTION
#   i ~ 18 mA at N=25 (order eps_ana/R_total = 0.18/10.15)  -> our frame/W
#       construction was the bug
#   i ~ 4.5 mA (unchanged)                                 -> the two paths
#       agree, and the error is inside the shared flux term
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

R=$HOME/csolv2
rm -rf "$R"

run_case() {
  local CASE=$1 SRC V
  SRC=$HOME/pysproject/cases/$CASE
  V=$R/$CASE
  mkdir -p "$V"
  cp "$SRC/case.sif" "$SRC/circuits.definitions" "$SRC/config.json" \
     "$SRC/model3d.msh" "$V/" 2>/dev/null
  cp -r "$SRC/mesh" "$V/mesh" 2>/dev/null

  echo
  echo "##################### $CASE #####################"
  echo "host: $(hostname)   start: $(date)"
  echo
  awk '
  # ---- 0b. Equation 1 needs the solver Equation string as a LOGICAL KEY.
  #      MainUtils.F90:1622-1636 looks the solver Equation string up as a
  #      logical key inside the numbered Equation blocks and Fatals otherwise:
  #          "Variable > coiltmp < exists but it is not associated to any
  #           equation"
  #      Verified locally: renaming the solver Equation string to the block
  #      Name does NOT work; adding the key here DOES.
  /^Equation 1$/ { ineq1 = 1 }
  ineq1 && !eq1done && /^  Name = / {
      print
      print "  Wire direction = Logical True";
      eq1done = 1
      next }

  # ---- 1. Solver 8 -> CoilSolver, normalisation keys --------------------
  /^  Procedure = "WPotentialSolver" "Wsolve"/ {
      print "  Procedure = \"CoilSolver\" \"CoilSolver\""; next }
  /^  Equation = "Wire direction"/ { ins8 = 1 }
  # CoilSolver sets its OWN scratch variable:
  #   CoilSolver.F90:73  ListAddNewString(Params, Variable, -nooutput CoilTmp)
  # and exports CoilPot / CoilPotB itself (F90:75-88).  So the line must be
  # DELETED, not renamed -- Variable = CoilPot would shadow the internal
  # scratch variable and VariableGet(CoilPot) at F90:272 would then point at
  # the wrong field.
  # NOTE: never write an apostrophe or a backtick inside this awk program --
  # a single quote closes the shell string and awk then tries to open the
  # remaining text as a FILE (job 122248196 died exactly that way, silently
  # turning a 561-line SIF into a 14-line one).
  /^  Variable = W$/ { if (ins8 && !v8) { v8=1; next } }
  /^  Linear System Iterative Method = CG/ {
      print
      if (ins8 && !done8) {
          print "  Normalize Coil Current = Logical True";
          print "  Fix Input Current Density = True";
          # NO `Coil Closed` -- that asks CoilSolver for the no-cuts CLOSED
          # loop treatment (upstream coil.sif:5-6) and our coil body has a
          # radial slit.  With it, CoilSolver dies with
          #     WARNING  No negative current sources on coil 1 end!
          #     WARNING  Crappy potentials in coil 1
          #     ERROR    Scaling of potential failed!
          # We DO give `Electrode Boundaries`, so the cut-mode path is fully
          # specified.  Dropping this line made the whole path run locally.
          print "  Narrow Interface = Logical True";
          print "  Save Coil Set = Logical True";
          print "  Save Coil Index = Logical True";
          print "  Calculate Elemental Fields = Logical True";
          print "  Nonlinear System Consistent Norm = True";
          done8 = 1
      }
      next }

  # ---- 2. Component 1: CoilSolver keys (Coil Normal ONLY here) ----------
  /^  Number of Turns = Real/ {
      print
      if (insc == 0) {
          print "  Coil Use W Vector = Logical True";
          print "  W Vector Variable Name = String \"CoilCurrent e\"";
          print "  ! CoilSolver.F90:358-359 Fatals if Coil Normal is also in";
          print "  ! the SOLVER section -- it must live here, on the component.";
          print "  Coil Normal(3) = Real 0.0 0.0 1.0";
          print "  Desired Current Density = Real 1";
          print "  Electrode Area = Real 1";
          insc = 1
      }
      next }

  # ---- 3. CoilSolver owns Coil Start / Coil End: strip our pre-set ones --
  /^  Coil Start = Logical True/ { nst++; next }
  /^  Coil End = Logical True/   { nen++; next }

  # ---- 4. Equation split: Solver 8 must not be active outside Body 1 ----
  #      NOTE: no `next` on the Body rule -- the Body line itself must still
  #      reach the final { print }.
  /^Body [0-9]+/ { bodynr = $2 }
  /^  Equation = 1$/ { if (bodynr+0 > 1) { print "  Equation = 2"; nb++; next } }
  /^  Active Solvers\(10\) = 5 6 7 8 1 9 2 3 10 11$/ {
      print "  Active Solvers(9) = 5 6 7 1 9 2 3 10 11"; neq++; next }

  # ---- 5. 30 steps ------------------------------------------------------
  /^  Timestep Intervals/ { print "  Timestep Intervals     = 30"; next }
  { print }
  END {
      printf "  [awk] procedure/keys=%d variable=%d strippedCoilStart=%d strippedCoilEnd=%d bodiesToEq4=%d eq1Trimmed=%d\n", \
          done8, v8, nst, nen, nb, neq > "/dev/stderr"
  }
' "$SRC/case.sif" > "$V/case.sif"

# Guard: an awk program embedded in a single-quoted shell string dies SILENTLY
# if it contains an apostrophe (the quote closes early and awk treats the rest
# as input FILE names), leaving a 0-byte SIF.  Job 122248196 did exactly that
# and still printed a "SUMMARY".  Never trust a transformation without an
# output-size assertion.
nout=$(wc -l < "$V/case.sif")
if [ "$nout" -lt 100 ]; then
    echo "ABORT: awk produced only $nout lines from $SRC/case.sif"
    echo "       (check $SRC for apostrophes inside the awk program)"
    exit 1
fi
if ! grep -q '^Equation 2' "$V/case.sif"; then
    echo "ABORT: Equation 2 missing from $V/case.sif"
    exit 1
fi
if ! grep -q 'Wire direction = Logical True' "$V/case.sif"; then
    echo "ABORT: Wire direction flag missing (MainUtils.F90:1633)"
    exit 1
fi
echo "  [check] transformed SIF has $nout lines, Equation 2 and the flag present"

# append Equation 2 -- everything EXCEPT the coil body (upstream coil.sif
# splits exactly this way: "for coil" vs "for air").
#
# The NUMBER matters: Elmer's LoadInputFile derives Model % NumberOfEquations
# from the highest `Equation <n>` suffix it sees, then insists that 1..n all
# exist (job 122247342 died with `Number of Equations: 4 /
# Entry missing for: Equation 2` when this block was numbered 4).  Our base
# SIF has only `Equation 1`, so the second one must be 2.
cat >> "$V/case.sif" <<'EOF'

! ============================================================
!  Equation 2 -- added by test_coilsolver_v2.sh
!    Everything EXCEPT Body 1.  CoilSolver (Solver 8) deliberately
!    absent: CoilSolver.F90:387 Fatals when a body that is active in an
!    Equation carrying CoilSolver does not belong to a Component.
!    Identical to Equation 1 minus Solver 8.  Numbered 2, not 4, because
!    Elmer requires the numbered Equation blocks to be contiguous.
! ============================================================
Equation 2
  Name = "MagneticsNoCoilSolver"
  Active Solvers(9) = 5 6 7 1 9 2 3 10 11
  Mesh Update = Logical True
End
EOF

echo "=== variant E changes ==="
grep -nE 'Procedure =|^  Variable =|Normalize Coil Current|Fix Input|Coil Closed|Narrow|Save Coil|Calculate Elemental|Nonlinear System Consistent|Number of Turns|Coil Use W Vector|W Vector Variable|Coil Normal|Desired Current|Electrode Area|Active Solvers|^Body |^  Equation =|Coil Start|Coil End|Timestep Intervals' \
     "$V/case.sif" | sed 's/^/  /'
echo

cd "$V" || return 1
echo "=== running ==="
$HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
rc=$?
echo "ElmerSolver rc=$rc   steps done: $(grep -c 'MAIN: Time' solve.log)"
echo
echo "=== CoilSolver startup messages ==="
grep -nE 'CoilSolver|Coil Start|Coil End|Electrode|Coil Closed|coil normal|normali' solve.log | head -25
echo
if [ -f results/circuit.csv ]; then
    echo "  step   i_component(1)   v_component(1)   r_component(1)"
    awk 'NR>1{printf "  %4d   %14.6e   %14.6e   %12.6e\n", NR, $10, $11, $14}' \
        results/circuit.csv | head -20
    awk 'NR>1{f=($10<0?-$10:$10); if(f>m)m=f} END{printf "  peak |i| = %.6e A\n", m}' \
        results/circuit.csv
    echo "  (Wsolve path reference: peak |i| = 4.549755e-03 A, r_comp1 = 1.508469e-01)"
else
    echo "[err] no circuit.csv -- tail of solve.log:"
    tail -50 solve.log
fi
echo
echo "=== errors / warnings worth reading ==="
grep -nE 'ERROR|FATAL|WARNING|Segmentation|not obtain|Unlisted keyword' solve.log | head -25
echo "finished : $(date)"
}

# The N=1 / N=25 PAIR is the decisive test.  With the Wsolve path it gives
#     i = 9.596190e-02 (N=1)  vs  4.549755e-03 (N=25)     ratio 21.1
# i.e. i ~ 1/N, and eps*N = 0.960 / 1.155 V is constant.  If the W-vector
# path restores the physics, i must instead GROW with N.
for C in N1_L040_cu_closed N25_L040_cu_closed; do
  run_case "$C"
done

echo
echo "########## SUMMARY ##########"
for C in N1_L040_cu_closed N25_L040_cu_closed; do
  f=$R/$C/results/circuit.csv
  if [ -f "$f" ]; then
    awk -v c="$C" 'NR>1{q=($10<0?-$10:$10); if(q>m)m=q; vv=$11; rr=$14}
      END{printf "  %-22s peak|i|=%.6e A   v_last=%.6e   r_comp1=%.6e\n", c, m, vv, rr}' "$f"
  else
    echo "  $C : NO RESULT (see $R/$C/solve.log)"
  fi
done
echo "  Wsolve reference : N1 9.596190e-02   N25 4.549755e-03   ratio 21.1  (=1/N, WRONG)"
echo "  want             : i(N=25) ~ 25x i(N=1)"
echo "all finished: $(date)"
echo "started : $(date)"
echo

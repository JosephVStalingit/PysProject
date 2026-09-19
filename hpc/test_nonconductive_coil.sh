#!/bin/bash
#SBATCH --job-name=nccoil
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:50:00
#SBATCH --output=nccoil-%j.out
#SBATCH --error=nccoil-%j.err
#
# test_nonconductive_coil.sh -- TEST THE EDDY-CURRENT CONTAMINATION HYPOTHESIS
#
# HYPOTHESIS
# ----------
# We set the COIL BODY's material `Electric Conductivity` to the homogenised
# sigma_eff = f*sigma_wire.  That value exists ONLY to make the stranded
# coil's own resistance integral
#       localR = N_j**2 * Integral(|w|**2 / sigma) dV
# reproduce the true wire resistance R_wire = N*L_turn/(sigma_wire*A_wire)
# (which it does, to 2.1%).
#
# BUT the SAME number is also a REAL conductivity as far as the
# WhitneyAVSolver A-formulation is concerned.  The coil body therefore
# carries EDDY CURRENTS in addition to being circuit-coupled as a stranded
# coil.  Evidence that they are present:
#     circuit.csv column 5, `eddy current power` = 3.12e-06 W  != 0
# while the whole circuit dissipates only
#     p_dc_component(1) = i^2 R = 1.2e-13 W
# i.e. the coil body dissipates 2e7 times more than the coil's own wire.
#
# Those eddy currents need a time constant
#     tau_eddy ~ L_ring/R_ring ~ 1.8e-04 s
# which is SMALLER than the timestep 3.3e-04 s, so the sub-problem is
# under-resolved and can corrupt A inside the coil -- and lambda is built
# entirely from A inside the coil.
#
# UPSTREAM'S OWN TEST avoids this: its coil `Material 1` is called "Dummy"
# and has NO `Electric Conductivity`, while the coil's lumped resistance is
# instead given EXPLICITLY on the component:
#     Component 1 : Resistance = Real 0
# and CircuitsAndDynamics.F90:693 reads
#     IF (.NOT. Comp % UseCoilResistance) THEN  <compute from sigma>
# so an explicit `Resistance` makes it SKIP the material integral.
#
# THIS TEST
# ---------
# For each N in 25/50/100 on the existing production mesh, 30 steps:
#     C = coil body sigma -> 1e-12 (non-conductive, like upstream's Dummy)
#         + Component 1 : Resistance = Real <the R that sigma_eff used to give>
# and prints i/v/r.  r_comp1 should come out identical to the current runs
# (same lumped R) while the eddy currents are gone.
#
# PREDICTION if the hypothesis is right:
#     i is no longer proportional to 1/N and grows substantially
#     (the study gives 4.550 / 2.275 / 1.138 mA -- expected to become
#      roughly N-proportional, i.e. ~4.5/9.1/18.2 mA).
# If i is unchanged, the eddy currents are NOT the cause and we look on.
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

R=$HOME/nccoil
rm -rf "$R"; mkdir -p "$R"
echo "host    : $(hostname)"
echo "started : $(date)"

# the lumped R that the sigma_eff path currently produces (from the study
# runs' r_component(1)); variant C hard-codes it on the component instead.
lumpedR () {
    case "$1" in
        25)  echo 0.1508468701 ;;
        50)  echo 0.3016937402 ;;
        100) echo 0.6033874805 ;;
    esac
}

for N in 25 50 100; do
    SRC=$HOME/pysproject/cases/N${N}_L040_cu_closed
    V=$R/N$N
    mkdir -p "$V"
    cp "$SRC/case.sif" "$SRC/circuits.definitions" "$SRC/config.json" \
       "$SRC/model3d.msh" "$V/" 2>/dev/null
    cp -r "$SRC/mesh" "$V/mesh" 2>/dev/null

    RC=$(lumpedR $N)
    awk -v rc="$RC" '
        # 30 steps
        /^  Timestep Intervals/ {print "  Timestep Intervals     = 30"; next}
        # inside Material 1 only, force the conductivity to ~zero
        /^Material 1[ \t]*$/ {inmat=1; print; next}
        inmat && /^ *Electric Conductivity/ {
            print "  Electric Conductivity = 1.0e-12"; next}
        /^End[ \t]*$/ {if (inmat) inmat=0; print; next}
        # add the explicit lumped resistance inside Component 1
        incomp && /^ *Coil Type/ {
            print; print "  Resistance = Real " rc; next}
        /^Component 1[ \t]*$/ {incomp=1; print; next}
        incomp && /^End[ \t]*$/ {incomp=0; print; next}
        {print}
    ' "$SRC/case.sif" > "$V/case.sif"

    echo
    echo "=== N=$N  variant C: coil body made non-conductive, R lumped = $RC ohm"
    grep -nE 'Electric Conductivity|Number of Turns|Stranded Coil N_j|Resistance =|Timestep Intervals' \
         "$V/case.sif" | sed 's/^/    /'
done

echo
echo "################ results ################"
printf '  %5s %8s %16s %16s %16s\n' N steps 'i_pk[C]' 'r_comp1' 'vs study'
for N in 25 50 100; do
    V=$R/N$N
    cd "$V" || continue
    $HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
    rc=$?
    st=$(grep -c 'MAIN: Time' solve.log)
    if [ -f results/circuit.csv ]; then
        ipk=$(awk 'NR>1{f=($10<0?-$10:$10); if(f>m)m=f} END{printf "%.6e", m}' \
              results/circuit.csv)
        rc1=$(awk 'NR==2{printf "%.6e", $14}' results/circuit.csv)
        epk=$(awk 'NR>1{f=($5<0?-$5:$5); if(f>m)m=f} END{printf "%.4e", m}' \
              results/circuit.csv)
        case $N in
            25) base=4.549755e-03 ;;
            50) base=2.275400e-03 ;;
            100) base=1.137800e-03 ;;
        esac
        printf '  %5d %8s %16s %16s %16s   eddyP_pk=%s rc=%s\n' \
               "$N" "$st" "$ipk" "$rc1" "x$(echo "$ipk $base" | awk '{printf "%.3f", $1/$2}')" "$epk" "$rc"
    else
        printf '  %5d %8s   [err] no circuit.csv (rc=%s)\n' "$N" "$st" "$rc"
        tail -20 solve.log | sed 's/^/      /'
    fi
    echo
done
echo "reference (current sigma_eff runs):  4.5498e-03 / 2.2754e-03 / 1.1378e-03 A"
echo "finished : $(date)"

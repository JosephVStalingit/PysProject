#!/bin/bash
#SBATCH --job-name=wvecab
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:40:00
#SBATCH --output=wvecab-%j.out
#SBATCH --error=wvecab-%j.err
#
# test_wvec_path.sh -- A/B test of the TWO `w` code paths in Add_stranded,
# using ONLY SIF edits.  NO COMPILATION, NO SOURCE PATCH.
#
# WHY
# ---
# CircuitsAndDynamics.F90:641-648 branches on the Component key
# `Coil Use W Vector`:
#
#   CoilUseWvec = GetLogical(CompParams,'Coil Use W Vector',Found)
#   IF (.NOT.Found) CoilUseWvec = CoilUseWvec0
#   IF (.NOT.CoilUseWvec) CALL GetLocalSolution(Wbase, UVariable=Wpot)  <- -grad W
#   ELSE                  w = ListGetElementVectorSolution(Wvec_h,...)  <- W vector
#
# OUR generated SIF does NOT set `Coil Use W Vector` (nor the
# `W Vector Variable Name`, `Desired Current Density` or `Electrode Area`
# that upstream's circuits_transient_stranded_full_coil test sets), so we
# take whichever path CoilUseWvec0 defaults to.
#
# The unexplained anomaly is that the coil's assembled flux linkage comes
# out proportional to 1/N when it must be proportional to N (measured from
# KVL on the finished study runs).  The resistance integral out of the SAME
# `w` is correct to 2.1%, so the two paths are the prime suspect.
#
# WHAT THIS DOES
# --------------
# builds two copies of the N25 closed case on the EXISTING mesh, 30 steps:
#   A = as-is                       (whatever path we have been using)
#   B = + Coil Use W Vector = Logical True
#            W Vector Variable Name = String "CoilCurrent e"
#            Desired Current Density = Real 1
#            Electrode Area = Real 1
#       i.e. exactly what upstream's own test sets
# and prints i_component(1) / v_component(1) / r_component(1) for both, so
# the two EMFs can be compared directly.
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

SRC=$HOME/pysproject/cases/N25_L040_cu_closed
R=$HOME/wvecab
rm -rf "$R"; mkdir -p "$R"

echo "host    : $(hostname)"
echo "started : $(date)"
echo
echo "=== our CoilSolver / W-potential solver block ==="
awk '/^Solver [0-9]+ *!.*Coil/,/^End/' "$SRC/case.sif" | head -60
echo
echo "=== every CoilSolver-ish keyword we DO set ==="
grep -nE 'CoilSolver|W Potential|WPotential|Normalize|Fix Input|Narrow|Save Coil|Coil Closed|Desired Current|Electrode' \
     "$SRC/case.sif" | sed 's/^/  /'
echo

build () {           # $1 = variant letter, $2 = 1 to add the upstream keys
    local v="$R/$1"
    mkdir -p "$v"
    cp "$SRC/case.sif" "$SRC/circuits.definitions" "$SRC/config.json" \
       "$SRC/model3d.msh" "$v/" 2>/dev/null
    cp -r "$SRC/mesh" "$v/mesh" 2>/dev/null
    # 30 steps instead of 900
    awk '/^  Timestep Intervals/ {print "  Timestep Intervals     = 30"; next}
         {print}' "$v/case.sif" > "$v/case.tmp" && mv -f "$v/case.tmp" "$v/case.sif"
    if [ "$2" = "1" ]; then
        # insert the upstream keys right after `Coil Type`
        awk '/^  Coil Type/ {print; print "  Coil Use W Vector = Logical True";
                             print "  W Vector Variable Name = String \"CoilCurrent e\"";
                             print "  Desired Current Density = Real 1";
                             print "  Electrode Area = Real 1"; next} {print}' \
            "$v/case.sif" > "$v/case.tmp" && mv -f "$v/case.tmp" "$v/case.sif"
    fi
    echo "--- $1 inserted keys:"
    grep -nE 'Coil Type|Coil Use W Vector|W Vector Variable|Desired Current|Electrode Area' \
         "$v/case.sif" | sed 's/^/    /'
}

build A 0
echo
build B 1
echo

for v in A B; do
    echo "=== running variant $v ==="
    cd "$R/$v" || continue
    $HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
    rc=$?
    echo "  ElmerSolver rc=$rc   steps done: $(grep -c 'MAIN: Time' solve.log)"
    if [ -f results/circuit.csv ]; then
        echo "  step   i_component(1)   v_component(1)   r_component(1)"
        awk 'NR>1 && NR<32 {printf "  %4d   %14.6e   %14.6e   %12.6e\n",
                            NR, $10, $11, $14}' results/circuit.csv
        echo "  r_comp1   = $(awk 'NR==2{printf "%.6e", $14}' results/circuit.csv) ohm"
    else
        echo "  [err] no circuit.csv -- tail of solve.log:"
        tail -25 solve.log
    fi
    echo
done

echo "finished : $(date)"

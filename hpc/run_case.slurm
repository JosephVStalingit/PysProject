#!/bin/bash
#SBATCH --job-name=elmer
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=110G
#SBATCH --time=24:00:00
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err
#
# run_case.slurm -- solve ONE study case directory on the HPC.
#
# Submit from inside a case directory (the one holding case.sif + mesh/):
#     cd ~/pysproject/cases/L040_ri020_fine
#     sbatch ~/pysproject/run_case.slurm
#
# ElmerSolver with UMFPACK is a SERIAL direct solve, so ntasks=1 is correct.
# Parallelism comes from running MANY cases (and many time windows) at once --
# see submit_all.sh.
#
# Optional env overrides when submitting:
#     TIME_OFFSET=0.02  sbatch --export=ALL,TIME_OFFSET=0.02 run_case.slurm
# picks up a different part of the timeline (the EM problem is quasi-static,
# so every timestep is independent and the timeline can be cut arbitrarily).

set -euo pipefail

ELMER_HOME=${ELMER_HOME:-$HOME/elmer262}
export PATH="$ELMER_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ELMER_HOME/lib:${LD_LIBRARY_PATH:-}"

cd "${SLURM_SUBMIT_DIR:-$PWD}"

if [ ! -f case.sif ]; then
    echo "[err] no case.sif in $PWD -- submit from a case directory"
    exit 1
fi

# A closed-circuit SIF does `INCLUDE circuits.definitions`.  Check it NOW:
# otherwise ElmerSolver dies on the include several minutes into the job
# instead of here.  (make_sif.py writes it next to case.sif for any curve
# with N_turns > 0; run_all_curves.sh also guards this at generate time.)
if grep -q 'INCLUDE circuits.definitions' case.sif && [ ! -f circuits.definitions ]; then
    echo "[err] case.sif includes circuits.definitions but the file is"
    echo "      not in $PWD -- regenerate with:"
    echo "          python make_sif.py --out case.sif --curve <curve>"
    exit 1
fi

# ElmerGrid converts the gmsh .msh into Elmer's native mesh/ layout.
# Done HERE (on the compute node) so only model3d.msh has to be uploaded
# instead of the larger converted mesh/ tree.
if [ ! -d mesh ]; then
    if [ ! -f model3d.msh ]; then
        echo "[err] neither mesh/ nor model3d.msh present in $PWD"
        exit 1
    fi
    echo "converting model3d.msh -> mesh/ with ElmerGrid"
    "$ELMER_HOME/bin/ElmerGrid" 14 2 model3d.msh -out mesh -autoclean
fi

echo "host        : $(hostname)"
echo "case        : $PWD"
echo "elmer       : $ELMER_HOME"
echo "started     : $(date)"
echo "TIME_OFFSET : ${TIME_OFFSET:-0}"

"$ELMER_HOME/bin/ElmerSolver" case.sif > solve.log 2>&1 || {
    echo "[err] ElmerSolver failed -- last 40 lines:"
    tail -40 solve.log
    exit 1
}

n=$(ls results/case_t*.vtu 2>/dev/null | wc -l)
echo "frames      : $n"

# results/circuit.csv is the actual science output: one row per step with
# i_component(1) (the induced coil current) in column 10 and v_component(1)
# in column 11.  It is written by Solver 11 (SaveScalars) reading the `crt i`
# / `crt v` mesh variables that Solver 10 creates -- which only happens
# because Solver 10 carries `Export Circuit Variables = Logical True`.
# A missing CSV means the export chain broke, so treat it as a failure even
# though ElmerSolver exited 0.
if [ -f results/circuit.csv ]; then
    rows=$(wc -l < results/circuit.csv)
    echo "circuit.csv : $rows rows"
    echo "columns     : $(sed -n '8,24p' results/circuit.csv.names \
                            | sed 's/^ *//' | tr '\n' '|')"
    echo "last row    : $(tail -1 results/circuit.csv)"
else
    echo "[err] results/circuit.csv is MISSING -- the circuit export chain"
    echo "      (Export Circuit Variables on Solver 10 + Solver 11 SaveScalars)"
    echo "      did not run.  The i_component(1) time series was NOT produced."
    exit 1
fi

grep -E "ALL DONE|TOTAL TIME" solve.log || true
echo "finished    : $(date)"

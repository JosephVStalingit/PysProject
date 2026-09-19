#!/bin/bash
#SBATCH --job-name=elwin
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
# the UMFPACK direct solve is SERIAL, but the queue caps memory per core:
#     DefMemPerCPU = 3569   (scontrol show partition kshctest02)
# so a large --mem must be paired with enough --cpus-per-task, otherwise
# sbatch rejects it with "too much memory requested relative to the number of
# CPUs".  The big meshes need ~25 GB for the LU factorisation, so we ask for
# 69 GB / 20 cpus ( 20 x 3500 ).  The extra cores simply idle -- there are
# 431 free nodes, so this is cheap.
#SBATCH --cpus-per-task=20
#SBATCH --mem=69000M
#SBATCH --time=24:00:00
#SBATCH --output=slurm-%j.out
#SBATCH --error=slurm-%j.err
#
# run_window.slurm -- solve ONE TIME WINDOW of a study case.
#
# WHY THIS IS EXACT
# -----------------
# Every body in the model has `Electric Conductivity ~ 0` (coil 0.0,
# air/magnet 1e-12), so the transient A-formulation loses its sigma*dA/dt
# term and each timestep is an INDEPENDENT magnetostatic solve.  The timeline
# therefore carries no information between steps and can be cut into as many
# independent jobs as we like.
#
# A window covering frames [W0, W0+NW) is produced by offsetting the linear
# motion law:  displacement(t) = -v*(t + W0*dt)
# so that the job-local first step lands exactly on global frame W0+1.
#
# Submit with, e.g.:
#     cd ~/pysproject/cases/L160_ri020_fine
#     for w in 0 1 2 3 4 5 6 7; do
#         sbatch --export=ALL,W0=$((w*16)),NW=16 run_window.slurm
#     done
# (see submit_windows.sh, which does this automatically)

set -euo pipefail

ELMER_HOME=${ELMER_HOME:-$HOME/elmer262}
export PATH="$ELMER_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$ELMER_HOME/lib:$ELMER_HOME/share/elmersolver/lib:${LD_LIBRARY_PATH:-}"

: "${W0:?set W0 (0-based first frame of this window)}"
: "${NW:?set NW (number of frames in this window)}"
V=${V:-1.0}
DT=${DT:-0.002}

cd "${SLURM_SUBMIT_DIR:-$PWD}"

TOFF=$(awk -v w="$W0" -v d="$DT" 'BEGIN{printf "%.12g", w*d}')

echo "window      : W0=$W0  NW=$NW  toff=$TOFF  v=$V  dt=$DT"
echo "host        : $(hostname)  started $(date)"

if [ ! -d mesh ]; then
    "$ELMER_HOME/bin/ElmerGrid" 14 2 model3d.msh -out mesh -autoclean
fi

# per-window working SIF (never clobber the pristine case.sif)
cp case.sif "case_w${W0}.sif"
SIF="case_w${W0}.sif"
sed -i "s|Timestep Intervals     = [0-9]*|Timestep Intervals     = $NW|" "$SIF"
sed -i "s|Real MATC \"[^\"]*\"|Real MATC \"-${V}*(tx+${TOFF})\"|"       "$SIF"
sed -i "s|Output File Name = case|Output File Name = case_w${W0}|"      "$SIF"

"$ELMER_HOME/bin/ElmerSolver" "$SIF" > "solve_w${W0}.log" 2>&1 || {
    echo "[err] window $W0 failed; last 30 lines:"; tail -30 "solve_w${W0}.log"; exit 1
}

# Move this window's frames into results/ under GLOBAL indices so the
# post-processing can simply concatenate them in order.
mkdir -p results
n=0
for f in case_w${W0}_t*.vtu; do
    [ -e "$f" ] || continue
    idx=$(echo "$f" | sed -E 's/.*_t0*([0-9]+)\.vtu/\1/')
    gidx=$((W0 + idx))
    printf -v out "results/case_w%05d.vtu" "$gidx"
    mv "$f" "$out"
    n=$((n + 1))
done
echo "window $W0: stored $n frames (global indices starting at $((W0+1)))"
grep -E "ALL DONE|TOTAL TIME" "solve_w${W0}.log" || true

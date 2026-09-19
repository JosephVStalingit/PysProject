#!/bin/bash
# submit_plan.sh -- submit study cases as BALANCED time windows.
#
# The queue enforces a hard per-user limit of 20 concurrent jobs:
#     "qos max submit job limit exceeded 20 ... QOSMaxSubmitJobPerUserLimit"
# so we cannot simply fire one job per window over the whole matrix.  Instead
# each case gets a NUMBER OF WINDOWS proportional to its estimated cost, so
# every job takes roughly the same wall time and the total stays under 20.
#
# Estimated serial cost is (frames x step_time), step_time ~ n_nodes^2 for the
# UMFPACK direct solve.  See the header of run_window.slurm for why splitting
# the timeline is exact.

set -uo pipefail
cd "$(dirname "$0")"
ELMER=${HOME}/elmer262
export PATH="$ELMER/bin:$PATH"
export LD_LIBRARY_PATH="$ELMER/lib:$ELMER/share/elmersolver/lib:${LD_LIBRARY_PATH:-}"

# case -> number of windows (tuned so all jobs land in the 6-10 h range)
declare -A PLAN=(
    [L020_ri020_coarse]=1
    [L020_ri020_fine]=1
    [L040_ri020_fine]=1
    [L080_ri020_fine]=3
    [L040_ri017_fine]=4
    [L160_ri020_fine]=6
)

if [ "${1:-}" = "--cancel" ]; then
    scancel -u "$USER"; echo "cancelled all jobs"
    rm -f cases/*/windows.submitted cases/*/slurm.submitted
    rm -rf cases/*/results cases/*/case_w*.sif cases/*/case_w*.vtu
    exit 0
fi

sub=0
for name in "${!PLAN[@]}"; do
    d="cases/$name/"
    [ -f "$d/case.sif" ] || { echo "skip $name (missing case.sif)"; continue; }
    NV=$(grep -E "Timestep Intervals" "$d/case.sif" | grep -oE "[0-9]+" | tail -1)
    DT=$(grep -E "Timestep Sizes" "$d/case.sif" | grep -oE "[0-9.eE+-]+" | tail -1)
    NW=${PLAN[$name]}
    W=$(( (NV + NW - 1) / NW ))
    echo "$name: $NV frames -> $NW window(s) of <=$W   (dt=$DT)"
    w=0
    for (( w=0; w<NW; w++ )); do
        w0=$(( w * W ))
        rem=$(( NV - w0 )); [ $rem -gt $W ] && rem=$W
        [ $rem -le 0 ] && break
        ( cd "$d" && sbatch --export=ALL,W0=$w0,NW=$rem,DT=$DT \
              "$HOME/pysproject/run_window.slurm" >/dev/null ) \
            || { echo "  [err] window $w failed"; break; }
        sub=$(( sub + 1 ))
    done
    touch "$d/windows.submitted"
done

echo
echo "submitted $sub window job(s)"
squeue -u "$USER" -h -o "%T" | sort | uniq -c

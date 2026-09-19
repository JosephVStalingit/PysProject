#!/bin/bash
# submit_windows.sh -- split every study case into independent TIME WINDOWS
# and submit them all at once.
#
#     bash submit_windows.sh              # all cases, default window size
#     bash submit_windows.sh 16           # 16 frames per window
#     bash submit_windows.sh 16 L160      # only cases matching a token
#
# Each window is a separate Slurm job and they all run CONCURRENTLY, so the
# wall-clock time of a case is roughly  (total_steps / n_windows) * step_time
# instead of total_steps * step_time.  This is legitimate because the EM
# problem is quasi-static: see the header of run_window.slurm.

set -uo pipefail
cd "$(dirname "$0")"

W=${1:-16}
shift || true
TOKENS=("$@")

sub=0
for d in cases/*/; do
    [ -f "$d/case.sif" ] || continue
    name=$(basename "$d")
    if [ ${#TOKENS[@]} -gt 0 ]; then
        keep=0
        for t in "${TOKENS[@]}"; do [[ "$name" == *"$t"* ]] && keep=1; done
        [ "$keep" = 1 ] || continue
    fi
    if [ -f "$d/windows.submitted" ]; then
        echo "skip $name (windows already submitted)"
        continue
    fi

    NV=$(grep -E "Timestep Intervals" "$d/case.sif" | grep -oE "[0-9]+" | tail -1)
    DT=$(grep -E "Timestep Sizes" "$d/case.sif" | grep -oE "[0-9]+\.?[0-9]*[eE]?-?[0-9]*" | tail -1)
    [ -n "${NV:-}" ] && [ "$NV" -gt 0 ] 2>/dev/null || {
        echo "skip $name (cannot read Timestep Intervals)"; continue; }
    [ -n "${DT:-}" ] || DT=0.002

    nw=$(( (NV + W - 1) / W ))
    echo "$name: $NV frames -> $nw window(s) of $W"
    w=0
    while [ $w -lt $nw ]; do
        w0=$(( w * W ))
        rem=$(( NV - w0 )); [ $rem -gt $W ] && rem=$W
        ( cd "$d" && sbatch --export=ALL,W0=$w0,NW=$rem,DT=$DT \
              "$OLDPWD/run_window.slurm" >/dev/null ) || {
            echo "  [err] submit failed for window $w"; break; }
        w=$(( w + 1 ))
    done
    touch "$d/windows.submitted"
    sub=$(( sub + nw ))
done

echo
echo "submitted $sub window job(s)"
squeue -u "$USER" -h -o "%T" | sort | uniq -c

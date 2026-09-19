#!/bin/bash
# submit_all.sh -- submit every study case under cases/ as its own Slurm job.
#
# Run this ON THE HPC, from the directory that contains cases/ and
# run_case.slurm (i.e. ~/pysproject):
#
#     bash submit_all.sh              # all cases
#     bash submit_all.sh L160 L040    # only cases whose name contains a token
#
# Each case is a directory containing case.sif + mesh/.  Because the EM
# problem is quasi-static, cases are INDEPENDENT of each other and of the
# timeline, so there is no reason to run them sequentially.

set -uo pipefail
cd "$(dirname "$0")"

TOKENS=("$@")
sub=0
for d in cases/*/; do
    [ -f "$d/case.sif" ] || continue
    # mesh/ is not required: run_case.slurm runs ElmerGrid on the compute node
    # from model3d.msh, so either one will do.
    if [ ! -d "$d/mesh" ] && [ ! -f "$d/model3d.msh" ]; then
        echo "skip $name (neither mesh/ nor model3d.msh)"
        continue
    fi
    if [ ${#TOKENS[@]} -gt 0 ]; then
        keep=0
        for t in "${TOKENS[@]}"; do
            [[ "$name" == *"$t"* ]] && keep=1
        done
        [ "$keep" = 1 ] || continue
    fi
    if [ -f "$d/slurm.submitted" ]; then
        echo "skip $name (already submitted)"
        continue
    fi
    ( cd "$d" && sbatch "$OLDPWD/run_case.slurm" ) && touch "$d/slurm.submitted"
    sub=$((sub + 1))
done

echo
echo "submitted $sub job(s); queue:"
squeue -u "$USER" -o "%.10i %.28j %.10P %.8T %.10M %.6D %R" || true

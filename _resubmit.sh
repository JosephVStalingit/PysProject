#!/bin/bash
# resubmit.sh -- submit all 7 cases from their own directories.
set -uo pipefail
CASES="N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty"
SLURM=$HOME/pysproject/run_case.slurm
JOBIDS=""
for d in $CASES; do
    dir=$HOME/pysproject/cases/$d
    [ -f "$dir/case.sif" ] || { echo "  skip $d"; continue; }
    jid=$( cd "$dir" && sbatch --parsable "$SLURM" 2>/dev/null )
    if [ -n "$jid" ]; then
        echo "  $d -> job $jid"
        JOBIDS="$JOBIDS $jid"
    else
        echo "  [err] sbatch failed for $d"
    fi
done
echo
echo "JOBIDS=$JOBIDS"
echo "$JOBIDS" > "$HOME/pysproject/_jobids.txt"
sleep 3
echo "=== queue ==="
squeue -u "$USER" -o '%i %T %M %R' 2>&1 | head -12

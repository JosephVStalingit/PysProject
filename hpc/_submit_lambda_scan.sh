#!/bin/bash
# _submit_lambda_scan.sh -- submit the STATIC Lambda_mot(z) scan (HPC side).
#
# Each point is 4 timesteps of a small (16.7 k element) mesh -- about a minute
# on this cluster -- so the 29 points are packed into arrays of <=10 tasks
# instead of 29 separate jobs: `QOSMaxSubmitJobPerUserLimit = 20` counts every
# pending/running entry, and 3 arrays always stay well inside that.
#
# Usage:  bash _submit_lambda_scan.sh [N] [START]
#         N     = staged points (default 29)
#         START = first task index (default 0); use it to submit the REST after
#                 the first batch drains, because `QOSMaxSubmitJobPerUserLimit = 20`
#                 counts EVERY ARRAY TASK, not every array job:
#                     array 0-9 + array 10-19  -> 20 tasks -> the third sbatch is
#                     refused with "qos max submit job limit exceeded 20".
#                 Then:  bash _submit_lambda_scan.sh 29 20
set -uo pipefail
cd ~

N=${1:-29}
START=${2:-0}
CHUNK=${CHUNK:-10}
if ! bash -n run_lambda_scan.sh; then echo "FATAL: run_lambda_scan.sh has a syntax error"; exit 1; fi
echo "bash -n OK"

rows=$(wc -l < "$HOME/pysproject/lambda_scan/manifest.tsv")
echo "manifest rows: $rows   submitting: $N   from task: $START"

export LAMSCAN_OUT=${LAMSCAN_OUT:-$HOME/hpc_lambda_scan}
mkdir -p "$LAMSCAN_OUT"
echo "output root: $LAMSCAN_OUT"

i=$START
while [ "$i" -lt "$N" ]; do
    hi=$((i + CHUNK - 1))
    if [ "$hi" -ge "$N" ]; then hi=$((N - 1)); fi
    printf 'array %3d-%-3d id: ' "$i" "$hi"
    sbatch --parsable --job-name="lam$i" --time=01:00:00 \
        --array="${i}-${hi}" \
        --export=ALL,LAMSCAN_OUT="$LAMSCAN_OUT" \
        run_lambda_scan.sh
    i=$((hi + 1))
done

sleep 8
echo
echo "--- queue ---"
squeue -u "$USER" -o '%.10i %.12j %.10P %.8T %.10M %R' | head -20

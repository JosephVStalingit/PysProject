#!/bin/bash
for d in /public/home/josephvstalin/hpc_lambda_scan/e*; do
  echo "### $d"
  ls "$d"
  echo "--- solve.log (head 10, tail 8) ---"
  head -10 "$d/solve.log" 2>/dev/null
  echo "..."
  tail -8 "$d/solve.log" 2>/dev/null
  echo "--- slurm out files ---"
  ls "$d"/slurm-*.out 2>/dev/null
  for s in "$d"/slurm-*.out; do
    [ -f "$s" ] || continue
    echo "--- $s ---"
    head -5 "$s"
    echo "..."
    tail -15 "$s"
  done
  echo
done
#!/bin/bash
# diag900 -- per-case progress report for the z900 sweep.
echo "=== jobs ==="
squeue -u "$USER" -o '%.10i %.8j %.8T %.9M' | tail -n +2
echo
echo "=== circuit.csv row counts ==="
for c in /public/home/josephvstalin/hpc_results_z900/*/results/circuit.csv; do
    [ -f "$c" ] || continue
    printf '  %-50s lines=%d\n' "$c" "$(wc -l < "$c")"
done
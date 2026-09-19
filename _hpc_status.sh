#!/bin/bash
# hpc_status.sh -- one-shot status: queue, per-case steps, timestamps.
cd ~/pysproject/cases || exit 1
echo "now: $(date)"
echo
echo "=== queue ==="
squeue -u "$USER" -o '%i %T %M %R' 2>&1 | head -20
echo
echo "=== per-case progress ==="
printf "%-24s %8s %10s %s\n" CASE STEPS CSVROWS LAST_VTU_TIME NEWEST_VTU
for d in N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty; do
    log="$d/solve.log"
    steps=$(grep -c 'MAIN: Time' "$log" 2>/dev/null || echo 0)
    if [ -f "$d/results/circuit.csv" ]; then
        csv=$(wc -l < "$d/results/circuit.csv")
    else
        csv="-"
    fi
    nvtu=$(ls "$d/results/"case_t*.vtu 2>/dev/null | wc -l)
    newest=$(ls -t "$d/results/"case_t*.vtu 2>/dev/null | head -1)
    newest_t=$(date -r "$newest" +%H:%M:%S 2>/dev/null || echo "-")
    printf "%-24s %8s %10s %s %s\n" "$d" "$steps" "$csv" "$newest_t" "$(basename ${newest:-none})"
done
echo
echo "=== newest solve.log mtimes ==="
ls -lt --time-style=+%H:%M:%S cases/*/solve.log 2>/dev/null | head -10

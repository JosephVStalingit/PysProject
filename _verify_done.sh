#!/bin/bash
# verify_done.sh -- confirm every case has 900 frames and a full circuit.csv.
set -uo pipefail
cd ~/pysproject/cases || exit 1
echo "now: $(date '+%m-%d %H:%M:%S')"
echo "queue: $(squeue -u "$USER" -h -o '%T' | sort | uniq -c | tr '\n' ' ')"
printf "%-24s %6s %8s %12s %s\n" CASE VTU CSVROWS LAST_T LAST_CIRCUIT
for d in N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed \
         N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty; do
    nv=$(ls "$d/results/"case_t*.vtu 2>/dev/null | wc -l)
    cv=$([ -f "$d/results/circuit.csv" ] && wc -l < "$d/results/circuit.csv" || echo 0)
    lt=$(grep -oE 'MAIN: Time: [0-9]+/[0-9]+' "$d/solve.log" 2>/dev/null | tail -1)
    last=""
    if [ -f "$d/results/circuit.csv" ]; then
        last=$(tail -1 "$d/results/circuit.csv" | awk '{printf "t=%.3f i1=%.4e v1=%.4e", $7, $10, $11}')
    fi
    printf "%-24s %6s %8s %12s %s\n" "$d" "$nv" "$cv" "$lt" "$last"
done
echo
echo "=== errors in logs? ==="
for d in N*_L040_*_closed empty; do
    e=$(grep -c -E 'ERROR|STOP 1|Segmentation' "$d/solve.log" 2>/dev/null || echo 0)
    printf "  %-24s %s\n" "$d" "$e"
done
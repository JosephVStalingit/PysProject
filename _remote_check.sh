#!/bin/bash
# _remote_check.sh -- runs ON the HPC.  Report live progress for every case.
cd "$HOME/pysproject/cases" || exit 1
printf '  %-22s %6s %8s %8s  %s\n' CURVE STEPS ERRORS CSVROWS LAST-I
for c in empty N25_L040_al_closed N25_L040_cu_closed N50_L040_al_closed \
         N50_L040_cu_closed N100_L040_al_closed N100_L040_cu_closed; do
    log="$c/solve.log"
    csv="$c/results/circuit.csv"
    steps=$(grep -c 'MAIN: Time:' "$log" 2>/dev/null || true)
    errs=$(grep -icE '^ERROR|FATAL|Segmentation' "$log" 2>/dev/null || true)
    rows=$(wc -l < "$csv" 2>/dev/null || true)
    last=$(tail -1 "$csv" 2>/dev/null | awk '{print $10}')
    printf '  %-22s %6s %8s %8s  %s\n' "$c" "${steps:-0}" "${errs:-0}" \
        "${rows:-0}" "${last:-none}"
done
echo
echo "  === last lines of N50_L040_cu_closed/solve.log ==="
tail -5 N50_L040_cu_closed/solve.log 2>/dev/null | sed 's/^/    /'

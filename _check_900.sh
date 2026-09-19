#!/bin/bash
# _check_900.sh -- verify the 900-step closed-circuit sweep.
set -uo pipefail
cd ~
R=$HOME/hpc_results_z900
CASES="empty N25_L040_cu_closed N50_L040_cu_closed N100_L040_cu_closed N25_L040_al_closed N50_L040_al_closed N100_L040_al_closed"

echo "== SIF parameters printed by each job =="
for j in 122445913 122445919 122445925 122445929 122445934 122445940 122445948; do
    f=csweep-$j.out
    [ -f "$f" ] || continue
    echo "--- $f ---"
    grep -a -E 'CASE:|sif:|equations=' "$f" | head -4
done

echo
echo "== progress (MAIN: Time lines / target 900) =="
for c in $CASES; do
    csv=$R/$c/results/circuit.csv
    nrow=0; [ -f "$csv" ] && nrow=$(wc -l < "$csv")
    ntime=0
    [ -f "$R/$c/solve.log" ] && ntime=$(grep -a -c 'MAIN: Time' "$R/$c/solve.log")
    nvtu=0
    ls $R/$c/results/*.vtu >/dev/null 2>&1 && nvtu=$(ls $R/$c/results/*.vtu | wc -l)
    printf "  %-24s main_time=%-5s csv=%-5s vtu=%s\n" "$c" "$ntime" "$nrow" "$nvtu"
done

echo
echo "== last SIF actually used (N25_Cu) =="
grep -E '^ *Timestep (Intervals|Sizes)|^ *Output Intervals' $R/N25_L040_cu_closed/case.sif 2>/dev/null

echo
echo "== queue =="
squeue -u "$USER" 2>&1 | head -10

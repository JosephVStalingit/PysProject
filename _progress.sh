#!/bin/bash
# progress.sh -- compact progress + wall-clock estimate.
set -uo pipefail
cd ~/pysproject/cases || exit 1
echo "now: $(date '+%m-%d %H:%M:%S')"
echo "=== queue ==="
squeue -u "$USER" -o '%i %T %M %R' 2>&1 | head -12
echo "=== progress ==="
printf "%-24s %6s %5s %8s %7s %s\n" CASE STEP% VTU CSVROWS RATE NODE
for d in N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed \
         N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty; do
    s=$(grep -c 'MAIN: Time' "$d/solve.log" 2>/dev/null || echo 0)
    nv=$(ls "$d/results/"case_t*.vtu 2>/dev/null | wc -l)
    cv=$([ -f "$d/results/circuit.csv" ] && wc -l < "$d/results/circuit.csv" || echo 0)
    pct=$(( s * 100 / 900 ))
    # rate from the two newest VTU mtimes
    a=$(ls -t "$d/results/"case_t*.vtu 2>/dev/null | head -1)
    b=$(ls -t "$d/results/"case_t*.vtu 2>/dev/null | sed -n 11p)
    rate="-"
    if [ -n "$a" ] && [ -n "$b" ]; then
        ta=$(stat -c %Y "$a" 2>/dev/null || echo 0)
        tb=$(stat -c %Y "$b" 2>/dev/null || echo 0)
        if [ "$ta" -gt "$tb" ] && [ "$tb" -gt 0 ]; then
            rate="$(( (ta - tb) / 10 ))s/step"
        fi
    fi
    echo "$(printf '%-24s %5s%% %5s %8s %7s' "$d" "$pct" "$nv" "$cv" "$rate")"
done
echo "=== disk ==="
df -h ~/pysproject 2>/dev/null | tail -1

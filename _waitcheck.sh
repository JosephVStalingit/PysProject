#!/bin/bash
# waitcheck.sh -- sleep N seconds (arg 1, default 255) then print one compact
# progress line per case.  Kept tiny so a single ssh call stays under 5 min.
set -uo pipefail
N=${1:-255}
sleep "$N"
cd ~/pysproject/cases || exit 1
printf "%s  " "$(date '+%H:%M:%S')"
q=$(squeue -u "$USER" -h -o '%T' | sort | uniq -c | tr '\n' ' ')
printf "[%s]\n" "$q"
for d in N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed \
         N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty; do
    s=$(grep -c 'MAIN: Time' "$d/solve.log" 2>/dev/null || echo 0)
    printf "  %-22s %4d/900  %3d%%\n" "$d" "$s" "$((s*100/900))"
done

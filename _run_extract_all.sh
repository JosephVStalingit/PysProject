#!/bin/bash
# run_extract_all.sh -- after every case finishes, measure the magnet z(t)
# from all 900 VTU frames and write one small CSV per case.
set -uo pipefail
source ~/_pyenv.sh
cd ~/pysproject/cases || exit 1
CASES="N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty"
mkdir -p ~/pysproject/z_results
for d in $CASES; do
    n=$(ls "$d/results/"case_t*.vtu 2>/dev/null | wc -l)
    echo "=== $d ($n frames) ==="
    if [ "$n" -lt 800 ]; then
        echo "  skip -- solve not finished yet"
        continue
    fi
    out=~/pysproject/z_results/${d}_magnet_z.csv
    "$PY" ~/hpc_extract_z.py "$d" "$out" 2>&1 | tail -8
done
echo
echo "=== z_results ==="
ls -la ~/pysproject/z_results/


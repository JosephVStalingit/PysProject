#!/bin/bash
# run_extract2.sh -- re-measure z(t) with the displacement-clustering method.
set -uo pipefail
source ~/_pyenv.sh
cd ~/pysproject/cases || exit 1
CASES="N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty"
mkdir -p ~/pysproject/z_results2
for d in $CASES; do
    echo "=== $d ==="
    "$PY" ~/hpc_extract_z2.py "$d" ~/pysproject/z_results2/${d}_magnet_z.csv 2>&1
done
echo
ls -la ~/pysproject/z_results2/

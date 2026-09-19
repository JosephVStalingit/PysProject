#!/bin/bash
# clean_and_verify.sh -- verify the patched SIFs, then clean the MIXED
# results/ dirs (left over from the cancelled run) so the re-run starts
# from a clean slate.
set -uo pipefail
cd ~/pysproject/cases || exit 1

CASES="N25_L040_cu_closed N25_L040_al_closed N50_L040_cu_closed N50_L040_al_closed N100_L040_cu_closed N100_L040_al_closed empty"

echo "=== 1. verify SIF integrity ==="
for d in $CASES; do
    sif="$d/case.sif"
    [ -f "$sif" ] || { echo "  MISSING $sif"; continue; }
    ti=$(grep -E '^  Timestep Intervals' "$sif" | grep -oE '[0-9]+' | tail -1)
    ts=$(grep -E '^  Timestep Sizes' "$sif" | sed 's/.*= *//')
    matc=$(grep -oE 'Real MATC "\([-0-9.]+\) \+ \([0-9.]+\)' "$sif" | head -1)
    ncomp=$(grep -c '^Component ' "$sif")
    mesh=$([ -d "$d/mesh" ] && echo yes || echo NO)
    msh=$([ -f "$d/model3d.msh" ] && echo yes || echo NO)
    printf "  %-24s steps=%-4s dt=%-12s %s comps=%s mesh=%s msh=%s\n" \
        "$d" "$ti" "$ts" "$matc" "$ncomp" "$mesh" "$msh"
done

echo
echo "=== 2. clean results/ (stale VTUs + partial csv) ==="
STAMP=$(date +%m%d_%H%M)
for d in $CASES; do
    [ -d "$d/results" ] || { mkdir -p "$d/results"; echo "  $d: created results/"; continue; }
    if [ -f "$d/results/circuit.csv" ]; then
        mv -f "$d/results/circuit.csv" "$d/results/circuit.csv.prev_$STAMP"
    fi
    if [ -f "$d/results/circuit.csv.names" ]; then
        mv -f "$d/results/circuit.csv.names" "$d/results/circuit.csv.prev_$STAMP.names"
    fi
    n=$(ls "$d/results/"case_t*.vtu 2>/dev/null | wc -l)
    rm -f "$d/results/"case_t*.vtu
    echo "  $d: removed $n stale VTU frames"
    rm -f "$d/windows.submitted"
done

echo
echo "=== 3. disk ==="
df -h ~/pysproject | tail -1
echo "  cases total: $(du -sh ~/pysproject/cases 2>/dev/null | cut -f1)"

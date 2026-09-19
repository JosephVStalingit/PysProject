#!/bin/bash
# _remote_resubmit.sh -- runs ON the HPC.
#
# run_all_curves.sh pre-creates an EMPTY cases/<curve>/mesh/ directory, and
# run_case.slurm only runs ElmerGrid when `[ ! -d mesh ]`.  So the converter
# was skipped and ElmerSolver died with
#     ERROR:: LoadMesh: Requested mesh > ./mesh < does not exist!
# Remove the empty directories so run_case.slurm regenerates them properly.
set -uo pipefail
cd "$HOME/pysproject/cases" || exit 1

echo "=== remove EMPTY mesh/ dirs (only the empty ones) ==="
find . -maxdepth 2 -type d -name mesh -empty -print -delete

echo "=== remove stale job output ==="
rm -f ./*/slurm-*.out ./*/slurm-*.err ./*/solve.log

CURVES="empty N25_L040_al_closed N25_L040_cu_closed N50_L040_al_closed N50_L040_cu_closed N100_L040_al_closed N100_L040_cu_closed"

echo "=== confirm model3d.msh present, mesh/ gone ==="
for c in $CURVES; do
    printf '  %-22s msh=%s mesh_dir=%s\n' "$c" \
        "$([ -f "$c/model3d.msh" ] && echo yes || echo NO)" \
        "$([ -d "$c/mesh" ] && echo PRESENT || echo absent)"
done

echo "=== resubmit ==="
for c in $CURVES; do
    cd "$HOME/pysproject/cases/$c" || continue
    out=$(sbatch "$HOME/pysproject/run_case.slurm" 2>&1)
    printf '  %-22s %s\n' "$c" "$out"
done

sleep 20
echo "=== queue ==="
squeue -u "$USER" -o "%.12i %.24j %.11P %.9T %.10M %.6D %R" 2>&1

#!/bin/bash
# _remote_submit.sh -- runs ON the HPC.  Unpack the case tarball and submit
# every new closed-circuit curve.  Plain bash, no nested quoting needed.
set -uo pipefail
cd "$HOME/pysproject" || exit 1

echo "=== unpack ==="
tar -xzf _upload.tar.gz -C cases && rm -f _upload.tar.gz && echo "  unpacked"

CURVES="empty N25_L040_al_closed N25_L040_cu_closed N50_L040_al_closed N50_L040_cu_closed N100_L040_al_closed N100_L040_cu_closed"

echo "=== sanity: every case has what run_case.slurm needs ==="
ok=1
for c in $CURVES; do
    d="$HOME/pysproject/cases/$c"
    have_mesh=no; have_sif=no; have_defs=n/a
    [ -f "$d/model3d.msh" ] && have_mesh=yes
    [ -f "$d/case.sif" ] && have_sif=yes
    if grep -q 'INCLUDE circuits.definitions' "$d/case.sif" 2>/dev/null; then
        [ -f "$d/circuits.definitions" ] && have_defs=yes || have_defs=MISSING
    fi
    printf '  %-22s mesh=%s sif=%s defs=%s\n' "$c" "$have_mesh" "$have_sif" "$have_defs"
    if [ "$have_mesh" != yes ] || [ "$have_sif" != yes ] || [ "$have_defs" = MISSING ]; then
        ok=0
    fi
done
[ "$ok" = 1 ] || { echo "[err] a case is incomplete -- NOT submitting"; exit 1; }

echo "=== submit ==="
for c in $CURVES; do
    cd "$HOME/pysproject/cases/$c" || continue
    out=$(sbatch "$HOME/pysproject/run_case.slurm" 2>&1)
    printf '  %-22s %s\n' "$c" "$out"
done

echo "=== queue ==="
squeue -u "$USER" -o "%.10i %.24j %.10P %.9T %.10M %.6D %R" 2>&1 | head -20

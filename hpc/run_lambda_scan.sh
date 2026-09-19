#!/bin/bash
#SBATCH --job-name=lamscan
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --array=0-9
#SBATCH --output=lamscan-%A_%a.out
#SBATCH --error=lamscan-%A_%a.err
#
# run_lambda_scan.sh -- HPC side of the STATIC Lambda_mot(z) scan.
#
# ONE array task = ONE (z, V) point.  Read the manifest row given by
# SLURM_ARRAY_TASK_ID, assemble the run dir, run ElmerSolver, echo the last
# circuit.csv row.  NO PYTHON HERE: the SIFs were already patched on the
# Windows box by hpc/stage_lambda_scan.py with the same
# scan_flux_force.patch() regexes a local run would have used.
#
# Each point is TRANSIENT with 4 timesteps and a CONSTANT Mesh Translate 3, so
# nothing moves; 4 steps are needed because make_sif.py gives the circuit
# solvers `Exec Solver = Before timestep` and a true Steady State run never
# executes CircuitsAndDynamics (i stays 0.000).
#
# OUTPUT:  $LAMSCAN_OUT/<tag>/results/circuit.csv    (default ~/hpc_lambda_scan)
#          one row per point; pull just the CSVs, they are ~1 kB each.
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

ROOT=$HOME/pysproject
SCAN=$ROOT/lambda_scan
R=${LAMSCAN_OUT:-$HOME/hpc_lambda_scan}
mkdir -p "$R"

i=${SLURM_ARRAY_TASK_ID:-0}
line=$(awk -v n=$((i + 1)) 'NR==n{print; exit}' "$SCAN/manifest.tsv")
if [ -z "$line" ]; then
    echo "FATAL: no manifest row for task $i (manifest has $(wc -l < "$SCAN/manifest.tsv") rows)"
    exit 0
fi
IFS=$'\t' read -r tag case z v <<<"$line"
echo "=== task $i  tag=$tag  case=$case  z=$z m  V=$v V ==="

D=$R/$tag
rm -rf "$D"
mkdir -p "$D"
cd "$D" || exit 1
cp "$SCAN/$tag/case.sif" ./
[ -f "$SCAN/$tag/circuits.definitions" ] && cp "$SCAN/$tag/circuits.definitions" ./
cp -r "$ROOT/cases/$case/mesh" ./mesh || { echo "FATAL: no mesh at $ROOT/cases/$case/mesh"; exit 1; }

echo "  sif: $(grep -E '^ *Timestep Intervals|^ *Mesh Translate 3|^ *testsource' case.sif | tr '\n' ' ')"
echo "  sif lines=$(wc -l < case.sif)"

$HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
rc=$?
echo "  ElmerSolver rc=$rc  'MAIN: Time' lines=$(grep -c 'MAIN: Time' solve.log)"

if [ -f results/circuit.csv ]; then
    echo "  header : $(head -1 results/circuit.csv)"
    echo "  last   : $(tail -1 results/circuit.csv)"
else
    echo "  NO circuit.csv -- errors:"
    grep -E 'ERROR|FATAL' solve.log | head -5
    tail -8 solve.log
fi
echo "done: $(date)"

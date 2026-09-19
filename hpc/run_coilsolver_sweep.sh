#!/bin/bash
#SBATCH --job-name=csweep
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=03:00:00
#SBATCH --output=csweep-%j.out
#SBATCH --error=csweep-%j.err
#
# run_coilsolver_sweep.sh -- 7-case HPC sweep, NO PYTHON ON THE CLUSTER.
#
# The case.sif files are generated LOCALLY with
#     python make_sif.py --curve <CASE> [--path coilsolver] --out <...>
# and pushed here beforehand.  This script only:
#     1. assembles a run directory (mesh + case.sif + circuits.definitions)
#     2. runs ElmerSolver
#     3. reports peak |i|, r_component(1), R_load
#
# WHY NO PYTHON: /usr/bin/python here is Python 2.7, and /usr/bin/python3.6
# is shadowed by a broken /usr/local/bin/python3 shim inside batch jobs.
# make_sif.py uses type annotations and f-strings and CANNOT run on this
# cluster.  (Job 122384493 died with `SyntaxError: invalid syntax` on
# `def patch_solver(sif: str, solver: str) -> str:`.)  Generating the SIF
# locally and shipping it is simpler and reproducible.
set -uo pipefail
export PATH=$HOME/elmer262/bin:$PATH
export LD_LIBRARY_PATH=$HOME/elmer262/lib:$HOME/elmer262/share/elmersolver/lib:${LD_LIBRARY_PATH:-}

CASES=(
  "empty"
  "N25_L040_cu_closed"
  "N50_L040_cu_closed"
  "N100_L040_cu_closed"
  "N25_L040_al_closed"
  "N50_L040_al_closed"
  "N100_L040_al_closed"
)

# Usage:  sbatch run_coilsolver_sweep.sh [--steps N] [CASE ...]
#
# A full 900-step case costs ~2-3.5 h on this cluster, so all 7 cases do not
# fit in one wall-clock window.  Pass a SUBSET of case names to split the
# sweep across several sbatch jobs that then run in PARALLEL, e.g.
#     sbatch run_coilsolver_sweep.sh --steps 300 \
#         N25_L040_cu_closed N50_L040_cu_closed N100_L040_cu_closed
STEPS=${SWEEP_STEPS:-900}
OUTINT=${SWEEP_OUTINT:-10}      # VTU output every N steps (circuit.csv is
                               # still written EVERY step by SaveScalars)
POS=()
while [ $# -gt 0 ]; do
    case "$1" in
      --steps)   STEPS="$2";  shift 2 ;;
      --out-int) OUTINT="$2"; shift 2 ;;
      *)         POS+=("$1"); shift ;;
    esac
done
if [ ${#POS[@]} -gt 0 ]; then
    CASES=("${POS[@]}")
fi

SRC_ROOT=$HOME/pysproject

# Output root.
#
# !! IMPORTANT !!  Every case directory is `rm -rf`'d at the start of its
# run, so a follow-up job that re-runs a partially-finished case DESTROYS
# the partial results.  That is exactly what happened when the first pass
# left N100_Cu at 133/300 and N50_Al at 170/300 and the follow-up jobs
# wiped both before they could be pulled.
#
# To keep two passes side by side, override the root:
#     SWEEP_OUT=$HOME/hpc_results_coilsolver_pass2 sbatch ...
R=${SWEEP_OUT:-$HOME/hpc_results_coilsolver}
mkdir -p "$R"
echo "output root: $R"


for CASE in "${CASES[@]}"; do
  echo
  echo "###############################################################"
  echo "#  CASE: $CASE   (target steps=$STEPS)"
  echo "###############################################################"
  SRC_CASE=$SRC_ROOT/cases/$CASE
  DEST=$R/$CASE
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cd "$DEST" || exit 1

  skip=0
  # case.sif is always required; circuits.definitions is only needed by
  # the CONDUCTOR curves (the `empty` baseline has no circuit at all, so
  # it legitimately has no definitions file).
  if [ ! -f "$SRC_CASE/case.sif" ]; then
    echo "  MISSING $SRC_CASE/case.sif -- skipping this case"
    skip=1
  fi
  if [ "$CASE" != "empty" ] && [ ! -f "$SRC_CASE/circuits.definitions" ]; then
    echo "  MISSING $SRC_CASE/circuits.definitions -- skipping this case"
    skip=1
  fi
  if [ ! -d "$SRC_CASE/mesh" ]; then
    echo "  MISSING $SRC_CASE/mesh -- skipping this case"
    skip=1
  fi
  if [ "$skip" = "1" ]; then
    cd "$R"; continue
  fi

  cp "$SRC_CASE/case.sif" ./
  [ -f "$SRC_CASE/circuits.definitions" ] && cp "$SRC_CASE/circuits.definitions" ./
  cp "$SRC_CASE/config.json" ./ 2>/dev/null || true
  cp -r "$SRC_CASE/mesh" ./mesh

  # Patch the timestep COUNT only.  Do NOT touch `Timestep Sizes`: the SIF
  # comes straight from make_sif.py, which writes it from
  # config.json -> experiment.dt_s (= 1.0e-3 s), and
  # experiment.t_end_default_s (= 0.9 s) / dt_s = 900 steps.  0.9 s is
  # THREE full spring periods (period = 0.2995 s), which is the project's
  # production length.
  #
  # An earlier version of this script force-set dt = 3.333e-4, which
  # silently turned "900 steps" into 0.3 s (one period) instead of 0.9 s.
  # Do not reintroduce that.
  if [ -n "$STEPS" ] && [ "$STEPS" != "0" ]; then
    sed -i -E "s/^([[:space:]]*Timestep Intervals[[:space:]]*=[[:space:]]*)[0-9]+/\1${STEPS}/" case.sif
  fi
  # VTU output frequency.
  #
  # NOTE (measured 2026-09-18): setting `Output Intervals(1) = 10` in the
  # Simulation section does NOT reduce the VTU count for our template --
  # Solver 4 (ResultOutputSolver) has no `Exec Solver` line and is invoked
  # every step regardless, so 900 files were written anyway
  # (hpc_results_z900 = 18 GB for 7 cases).  The sed below is therefore
  # KEPT for whoever fixes it properly, but do not rely on it: if disk is
  # tight, give Solver 4 an explicit `Exec Solver = After timestep` plus
  # `Output Intervals`, or drop the writer entirely -- circuit.csv (which
  # SaveScalars writes every step) is all that is needed for the EMF and
  # current series, and it is unaffected by any of this.
  if [ -n "$OUTINT" ] && [ "$OUTINT" != "0" ]; then
    sed -i -E "s/^([[:space:]]*Output Intervals\(1\)[[:space:]]*=[[:space:]]*)[0-9]+/\1${OUTINT}/" case.sif
  fi
  echo "  sif: $(grep -E '^ *Timestep (Intervals|Sizes)|^ *Output Intervals' case.sif | tr '\n' ' ')"
  echo "  equations=$(grep -c '^Equation ' case.sif)  solvers=$(grep -c '^Solver ' case.sif)"

  # Guard: the SIF must be complete (an earlier quoting bug produced a
  # 14-line SIF that still "ran" and reported NO RESULT).
  nl=$(wc -l < case.sif)
  if [ "$nl" -lt 200 ]; then
    echo "  ABORT: case.sif is only $nl lines -- truncated!"
    cd "$R"; continue
  fi

  $HOME/elmer262/bin/ElmerSolver case.sif > solve.log 2>&1
  rc=$?
  echo "  ElmerSolver rc=$rc  MAIN:Time lines=$(grep -c 'MAIN: Time' solve.log)"

  if [ -f results/circuit.csv ]; then
    awk -v c="$CASE" '
      NR>1 { q=($10<0?-$10:$10); if(q>m)m=q; v=$11; r=$14; rl=$16 }
      END { printf "  %-24s peak|i|=%.6e A  v=%.6e  r_comp1=%.6e  R_load=%.1f\n",
                    c, m, v, r, rl }' results/circuit.csv
  else
    echo "  $CASE : NO circuit.csv -- errors:"
    grep -E 'ERROR|FATAL' solve.log | head -3
    tail -6 solve.log
  fi
  cd "$R"
done

echo
echo "########## SWEEP SUMMARY ##########"
printf "  %-24s %14s  %12s  %10s\n" CASE peak_i r_comp1 R_load
for C in "${CASES[@]}"; do
  F=$R/$C/results/circuit.csv
  if [ -f "$F" ]; then
    awk -v c="$C" '
      NR>1 { q=($10<0?-$10:$10); if(q>m)m=q; r=$14; rl=$16 }
      END { printf "  %-24s %14.6e  %12.6e  %10.1f\n", c, m, r, rl }' "$F"
  else
    printf "  %-24s %14s\n" "$C" "NO RESULT"
  fi
done
echo
echo "Expected R_wire: Cu N25/50/100 = 0.1541 / 0.3082 / 0.6164 ohm"
echo "                 Al N25/50/100 = 0.2624 / 0.5248 / 1.0496 ohm"
echo "Wsolve baseline N50_Cu (900 steps): peak|i|=5.3880e-03 A"
echo "done: $(date)"

#!/bin/bash
# _submit_z3000.sh -- the FULL 3000-step CLOSED-CIRCUIT sweep.
#
# WHY 3000 STEPS
#   dt_s = 1.0e-3 s (config.json), t_end = 3.0 s  ->  3000 steps.
#   Spring period T = 0.2995 s  ->  3000 / 299.5 = 10.0 full periods.
#   This is the project's targeted production length so we can SEE the 10%
#   Lenz decay in the closed-circuit cases (the brief calls for tau10 ~ 1.99 s,
#   i.e. ~6.6 periods).  900 steps only covers 3 periods and the expected
#   decay (1.1%) is buried under the EMF-spike noise.
#
# CLOSED CIRCUIT, ALL 7 CASES (empty + 3 Cu + 3 Al)
#   [0 V source] -> [coil component 1, N turns, R_wire] -> [load component 2,
#   R_load = 0.5012 ohm (sensor + 0.5 ohm sense resistor)].
#   Body Force 3 (Circuit) keys are folded into Body Force 1 by make_sif.py
#   + the CircuitsAndDynamics solver carries Variable = X and No Matrix = True
#   so R_total = R_coil + R_load is solved -- the 9.045x anomaly is fixed
#   (notes.md 27 / README 11.9).
#
# PARALLELISM
#   7 jobs * 1 core each; HPC QOS allows 20 -> 7 fits comfortably.
#
# WALL CLOCK
#   Local 8.06 s/step, HPC ~1.8x slower => 3000 steps = 12 h case-wall.
#   All 7 in parallel -> 12 h total wall.  (The previous z900 sweep was
#   cancelled at ~19 min to switch to this longer sweep.)
set -uo pipefail
cd ~

if ! bash -n run_coilsolver_sweep.sh; then echo "FATAL bash -n"; exit 1; fi
echo "bash -n OK"

export SWEEP_OUT=$HOME/hpc_results_z3000
mkdir -p "$SWEEP_OUT"
echo "output root: $SWEEP_OUT"

submit() {
    local name=$1; shift
    printf '%-9s id: ' "$name"
    sbatch --parsable --job-name="$name" --time=16:00:00 \
        --export=ALL,SWEEP_OUT="$SWEEP_OUT",SWEEP_STEPS=3000,SWEEP_OUTINT=100 \
        run_coilsolver_sweep.sh --steps 3000 --out-int 100 "$@"
}

# Each case gets its own job so Slurm can dispatch them in parallel as cores
# free up.  Total QOS budget used: 7 / 20.
submit c3000E  empty
submit c3000C1 N25_L040_cu_closed
submit c3000C2 N50_L040_cu_closed
submit c3000C3 N100_L040_cu_closed
submit c3000A1 N25_L040_al_closed
submit c3000A2 N50_L040_al_closed
submit c3000A3 N100_L040_al_closed

sleep 8
echo
echo "--- queue ---"
squeue -u "$USER" 2>&1 | head -14
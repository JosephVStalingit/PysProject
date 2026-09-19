#!/bin/bash
# _submit_900.sh -- the FULL 900-step CLOSED-CIRCUIT sweep.
#
# WHY 900 STEPS
#   config.json: experiment.dt_s = 1.0e-3 s, t_end_default_s = 0.9 s,
#   so 900 steps x 1 ms = 0.90 s = THREE full spring periods
#   (period = 0.2995 s).  That is the project's production length and it is
#   what the SIF already carries -- this script pins the COUNT so a later
#   edit cannot shrink it, and deliberately does NOT touch `Timestep Sizes`
#   (an earlier version force-set dt = 3.333e-4, which silently turned
#   "900 steps" into 0.3 s = one period instead of 0.9 s = three).
#
# CLOSED CIRCUIT
#   Every one of the six conductor curves is a closed loop
#       [0 V source] -> [coil component 1] -> [load component 2, 10 ohm]
#   with the coil solved by CoilSolver (W vector) and its own resistance
#   taken from `Component 1 Resistance = R_wire(N)`.
#   `empty` is the no-coil / no-circuit reference (no Lenz braking).
#
# PARALLELISM
#   One case per job: a 900-step case costs 3-4 h here, so packing two into
#   one job would risk the wall limit.  Seven small jobs instead of three
#   big ones; Slurm queues whatever cannot start immediately.
#
# OUTPUT
#   hpc_results_z900/<case>/  (the 300-step results in
#   hpc_results_coilsolver are left untouched)
#   VTU every 10 steps to bound disk use; circuit.csv every step.
set -uo pipefail
cd ~

if ! bash -n run_coilsolver_sweep.sh; then echo "FATAL bash -n"; exit 1; fi
echo "bash -n OK"

export SWEEP_OUT=$HOME/hpc_results_z900
mkdir -p "$SWEEP_OUT"
echo "output root: $SWEEP_OUT"

submit() {
    local name=$1; shift
    printf '%-8s id: ' "$name"
    sbatch --parsable --job-name="$name" --time=06:00:00 \
        --export=ALL,SWEEP_OUT="$SWEEP_OUT" \
        run_coilsolver_sweep.sh --steps 900 --out-int 10 "$@"
}

submit c900E  empty
submit c900C1 N25_L040_cu_closed
submit c900C2 N50_L040_cu_closed
submit c900C3 N100_L040_cu_closed
submit c900A1 N25_L040_al_closed
submit c900A2 N50_L040_al_closed
submit c900A3 N100_L040_al_closed

sleep 8
echo
echo "--- queue ---"
squeue -u "$USER" 2>&1 | head -12

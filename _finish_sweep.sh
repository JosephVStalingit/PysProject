#!/bin/bash
# _finish_sweep.sh -- run the cases that did not finish in the first pass.
#
# First-pass outcome (jobs 122385167 / 122385862 / 122385860):
#   N25_Cu   300/300  OK   N50_Cu 300/300 OK   N100_Cu  133/300  (wall limit)
#   N25_Al   300/300  OK   N50_Al 170/300 (wall limit)   N100_Al  0/300
#   empty    300/300  OK (no circuit.csv -- expected)
#
# So three cases still need to run: N100_Cu, N50_Al, N100_Al.
# Each in its OWN job so a single slow case cannot starve the others.
set -uo pipefail
cd ~
if ! bash -n run_coilsolver_sweep.sh; then echo "FATAL bash -n"; exit 1; fi
echo "bash -n OK"

echo -n "N100_Cu id: "
sbatch --parsable --job-name=csweepC --time=03:00:00 \
    run_coilsolver_sweep.sh --steps 300 N100_L040_cu_closed

echo -n "N50_Al  id: "
sbatch --parsable --job-name=csweepD --time=03:00:00 \
    run_coilsolver_sweep.sh --steps 300 N50_L040_al_closed

echo -n "N100_Al id: "
sbatch --parsable --job-name=csweepF --time=03:00:00 \
    run_coilsolver_sweep.sh --steps 300 N100_L040_al_closed

sleep 5
echo
squeue -u "$USER" 2>&1 | head -8

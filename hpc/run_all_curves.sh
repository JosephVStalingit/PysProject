#!/bin/bash
# =====================================================================
#  hpc/run_all_curves.sh -- generate mesh + SIF + sbatch for every
#  curve in config.json -> [curves], in sequence.
#
#  This is the BATCH ENTRY POINT for the 12-curve (3 N x 2 mat x 2 state)
#  design added in [3.6.0].  Each curve becomes its own hpc/cases/<sif_suffix>/
#  directory holding a patched config.json, the mesh built by solenoid3d.py
#  under that config, and a case.sif produced by make_sif.py.
#
#  EVERY curve is dispatched the same way -- there is no circuit-mode flag
#  any more, because the open-circuit variant was removed.  make_sif.py
#  decides from the curve itself:
#
#    conductor (N_turns > 0) -> the closed circuit
#        Material 1 sigma = sigma_wire; `Component 1` = stranded coil with
#        this curve's N_turns; `Component 2` = load resistor with this
#        curve's R_load_ohm; WPotentialSolver + CircuitsAndDynamics +
#        CircuitsOutput solvers; `INCLUDE circuits.definitions` (written
#        into the case dir by make_sif.py, alongside case.sif).
#
#    no conductor (N_turns = 0, i.e. the `empty` curve) -> plain template
#        sigma = 0, no circuit.  This is the no-Lenz-braking baseline the
#        6 conductor curves are compared against.
#
#  So the sweep is 7 case directories: 1 baseline + 6 closed.
#
#  CAVEAT: the closed path now RUNS (hpc/notes.md 15.7), but it has only
#  been validated with a 3- and 20-step smoke test locally.  Smoke-test one
#  curve before dispatching the batch:
#      bash hpc/smoke_test_closed.sh N50_L040_cu_closed
#  Also note the coil's own resistance `r_component(1)` comes back ~10x
#  below a hand estimate -- check it before trusting the induced current.
#
#  Usage (on HPC):
#    bash hpc/run_all_curves.sh                 # generate + submit all 7
#    bash hpc/run_all_curves.sh --dry-run       # generate only, no sbatch
#    bash hpc/run_all_curves.sh --curve N50_L040_cu_closed  # single curve
#    bash hpc/run_all_curves.sh --curve empty --dry-run
#
#  The coil geometry (40 mm, 0.7 mm wire, bore r_in/r_out = 20/25 mm) is
#  identical across all curves.  Every curve gets its own mesh + SIF pair --
#  expect ~ 7 * <mesh_time> for gmsh + 7 * <Elmer time>.  On the HPC this is
#  trivial to parallelise; see hpc/run_case.slurm for the job template.
# =====================================================================
set -euo pipefail

PROJ=${PROJ:-$HOME/PysProject}
cd "$PROJ"

CURVE_FILTER=""
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)   DRY_RUN=1; shift ;;
        --curve)     CURVE_FILTER="$2"; shift 2 ;;
        -h|--help)   sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "[err] unknown arg: $1" >&2; exit 1 ;;
    esac
done

# Enumerate curves from config.json, skipping the non-dict `_comment_block`.
# Keep declaration order: `empty` first (the baseline), then the conductor
# curves, which is the order they are meant to be read in.
mapfile -t ALL_CURVES < <(python - <<'PY'
import json
d = json.load(open('config.json', encoding='utf-8'))
for k, v in d['curves'].items():
    if not isinstance(v, dict):
        continue
    print(k)
PY
)

if [ -n "$CURVE_FILTER" ]; then
    ALL_CURVES=("$CURVE_FILTER")
fi

echo "=== plan ==="
echo "  curves: ${ALL_CURVES[*]}"
echo "  dry run: $DRY_RUN"
echo

for curve in "${ALL_CURVES[@]}"; do
    # A conductor curve (N_turns > 0) gets the closed circuit; anything
    # else (`empty`) gets the plain template.  make_sif.py decides this
    # itself -- there is no mode flag to keep in sync any more.
    n_turns=$(python -c "
import json
d=json.load(open('config.json',encoding='utf-8'))
c=d['curves'].get('$curve',{})
print(int(c.get('N_turns',0) or 0))
")
    if [ "$n_turns" -gt 0 ]; then
        circuit="closed"
    else
        circuit="baseline (no conductor)"
    fi

    echo "[run ] $curve  N=$n_turns  circuit=$circuit"
    case_dir="$PROJ/hpc/cases/$curve"
    rm -rf "$case_dir"
    mkdir -p "$case_dir/mesh" "$case_dir/results"

    # 1. patch config.json: the SIF will be generated from THIS copy, so
    #    the coil block + body_name stay identical; only the curves block
    #    is reduced to just the active curve (so oscilloscope.py doesn't
    #    see the others).
    python - <<PY
import json, pathlib
src = json.load(open('config.json', encoding='utf-8'))
src['curves'] = {'${curve}': src['curves']['${curve}'],
                 '_comment_block': src['curves'].get('_comment_block', '')}
out = pathlib.Path('$case_dir/config.json')
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(src, indent=4, ensure_ascii=False), encoding='utf-8')
print(f'[case]  wrote {out}')
PY

    # 2. mesh build.  solenoid3d.py --config picks the sif_suffix from
    #    the curves block, which is now only the active curve.  For a
    #    conductor curve this also emits the CoilStart / CoilEnd physical
    #    groups the closed-circuit SIF needs.
    ( cd "$case_dir" && python "$PROJ/solenoid3d.py" )

    # 3. SIF.  --curve alone determines the circuit treatment; --solver
    #    stays at umfpack (the previously-validated default).
    #
    #    --out is passed EXPLICITLY and is essential.  make_sif.py resolves
    #    its default --out as `<directory of make_sif.py>/case_transient.sif`,
    #    i.e. relative to the SCRIPT, not the CWD.  Relying on the `cd`
    #    above therefore wrote the generated SIF into the project root and
    #    -- worse -- OVERWROTE the case_transient.sif template that every
    #    other curve reads from.  run_case.slurm then died with
    #    "no case.sif in $PWD".  A relative `case.sif` lands correctly
    #    because we are already inside $case_dir.
    ( cd "$case_dir" && python "$PROJ/make_sif.py" \
        --out case.sif --curve "$curve" --solver umfpack )

    # Guard: a conductor case MUST have the MNA definitions, or ElmerSolver
    # will die on the INCLUDE several minutes into the job instead of here.
    if [ "$n_turns" -gt 0 ] && [ ! -f "$case_dir/circuits.definitions" ]; then
        echo "[err] $curve has a conductor but make_sif.py wrote no" \
             "circuits.definitions" >&2
        exit 1
    fi

    # 4. sbatch.
    if [ $DRY_RUN -eq 0 ]; then
        ( cd "$case_dir" && sbatch "$PROJ/hpc/run_case.slurm" "$curve" )
    else
        echo "[dry-run] would sbatch $PROJ/hpc/run_case.slurm $curve"
    fi
    echo
done

echo "[done] $((${#ALL_CURVES[@]})) curves processed"

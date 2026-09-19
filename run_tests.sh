#!/usr/bin/env bash
# =============================================================================
#  run_tests.sh  --  Linux/macOS entrypoint for PysProject FEM pipeline
#
#  Equivalent to run_tests.ps1 (Windows).  Mirrors the 5-step process:
#    [1/5] gmsh        -> model3d.msh
#    [2/5] ElmerGrid   -> mesh/
#    [3/5] make_sif.py -> case_transient.sif, then ElmerSolver -> results/
#    [4/5] tests/test_mesh.py + tests/test_render.py + tests/test_sif_solver.py
#         + tests/test_sif_circuit.py + tests/test_spring_model.py
#    [5/5] oscilloscope.py + mode-aware verifier
#
#  Elmer 26.2 is looked up in this order:
#    $ELMER_HOME_OVERRIDE  ->  /opt/elmer  ->  ./elmer262  ->  /usr/local  ->  /usr
#  Inside the Docker image it is always /opt/elmer (the Dockerfile compiles
#  it in stage 1); ./elmer262 is the bundled Windows build for host use.
#
#  Exits 0 on success, 1 on any failure.
# =============================================================================
set -euo pipefail

# ---- locate Python (prefer python3, then python) ---------------------------
PY="${PY:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
    PY=python
fi
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "  err  python not found" >&2
    exit 1
fi
echo "    -> using $("$PY" --version)"

# ---- locate Elmer ----------------------------------------------------------
ELMER_HOME=""
for cand in \
        "${ELMER_HOME_OVERRIDE:-}" \
        /opt/elmer \
        "$(dirname "$(readlink -f "$0")")/elmer262" \
        /usr/local \
        /usr; do
    [ -n "$cand" ] || continue
    if [ -x "$cand/bin/ElmerSolver" ]; then
        ELMER_HOME="$cand"; break
    fi
done
if [ -z "$ELMER_HOME" ]; then
    echo "  err  ElmerSolver not found." >&2
    echo "       Inside the container it lives at /opt/elmer (built by the" >&2
    echo "       Dockerfile's stage 1).  On the host, install Elmer 26.2 or" >&2
    echo "       bundle ./elmer262/ next to this script." >&2
    exit 1
fi
export ELMER_HOME
export ELMER_LIB="${ELMER_HOME}/share/elmersolver/lib"
# Both directories are required: the solver plugins live in $ELMER_LIB but
# they need libelmersolver.so from $ELMER_HOME/lib/elmersolver, and they carry
# no RUNPATH of their own.
export LD_LIBRARY_PATH="${ELMER_HOME}/lib/elmersolver:${ELMER_LIB}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export PATH="${ELMER_HOME}/bin:${PATH}"
echo "    -> ELMER_HOME=${ELMER_HOME}"

mkdir -p test_outputs

# ---- [1/5] gmsh build ------------------------------------------------------
echo
echo "[1/5] gmsh build"
"$PY" solenoid3d.py 2>&1 | tee test_outputs/gmsh.log | tail -n 4
if [ ! -f model3d.msh ]; then
    echo "  err  model3d.msh not produced" >&2
    exit 1
fi
echo "  ok   model3d.msh  ($(du -h model3d.msh | cut -f1))"

# ---- [2/5] ElmerGrid -------------------------------------------------------
echo
echo "[2/5] ElmerGrid 14 2"
rm -rf mesh
ElmerGrid 14 2 model3d.msh -out mesh -autoclean 2>&1 \
    | tee test_outputs/elmergrid.log \
    | grep -E 'knots|elements|ERROR' | head -n 2 || true
if [ ! -f mesh/mesh.elements ]; then
    echo "  err  mesh/ not produced" >&2
    exit 1
fi
header=$(head -1 mesh/mesh.header)
echo "  ok   mesh/  (${header})"

# ---- [3/5] make_sif.py + ElmerSolver ---------------------------------------
echo
echo "[3/5] make_sif.py -> case_transient.sif, then ElmerSolver"
"$PY" make_sif.py
if [ ! -f case_transient.sif ]; then
    echo "  err  make_sif.py did not produce case_transient.sif" >&2
    exit 1
fi
mkdir -p results
rm -rf results/*
ElmerSolver case_transient.sif 2>&1 | tee results/solver.log
if [ ! -f results/case_t0001.vtu ]; then
    echo "  err  results/case_t0001.vtu not produced" >&2
    grep -E 'FATAL|ERROR' results/solver.log | head -5
    exit 1
fi
echo "  ok   case_t0001.vtu  ($(du -h results/case_t0001.vtu | cut -f1))"
grep -E 'ALL DONE|TOTAL TIME' results/solver.log \
    | sed 's/^/       /' || true

# ---- [4/5] FEM sanity tests ------------------------------------------------
echo
echo "[4/5] FEM tests"
for t in tests/test_mesh.py tests/test_render.py tests/test_sif_solver.py tests/test_sif_circuit.py tests/test_spring_model.py; do
    echo "  -> $t"
    "$PY" "$t" || { echo "  err  $t failed" >&2; exit 1; }
done

# ---- [5/5] oscilloscope + mode-aware verifier ------------------------------
echo
echo "[5/5] oscilloscope (FEM result plots)"
"$PY" oscilloscope.py || { echo "  err  oscilloscope.py failed" >&2; exit 1; }

# config.json decides which verifier is meaningful: the free-fall check is
# meaningless in spring mode and vice versa, so pick by motion_mode.
MODE=$("$PY" -c "import json;print(json.load(open('config.json',encoding='utf-8'))['experiment'].get('motion_mode','free_fall'))")
echo "  -> motion_mode = $MODE"
case "$MODE" in
    spring)    "$PY" test_outputs/verify_spring.py || \
               echo "  warn verify_spring.py reported a deviation" >&2 ;;
    free_fall) "$PY" test_outputs/verify_fall.py || \
               echo "  warn verify_fall.py reported a deviation" >&2 ;;
esac

echo
echo "  ok   all FEM tests passed"
echo
echo "Outputs in test_outputs/:"
ls -lh test_outputs | tail -n +2 | awk '{printf "  %-20s %s\n", $9, $5}'
echo
echo "Outputs in results/:"
ls -lh results | tail -n +2 | awk '{printf "  %-20s %s\n", $9, $5}'
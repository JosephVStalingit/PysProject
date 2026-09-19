#!/bin/bash
# =====================================================================
#  hpc/build_elmer.sh  --  build Elmer 26.2 on a new cluster
#
#  Four recipes.  Pick ONE based on what `detect_accelerator.sh` says.
#
#     cpu      MPI + OpenMP + MUMPS          (direct solver, needs MUMPS)
#     hypre    MPI + OpenMP + Hypre AMS      <- BEST CHOICE WITHOUT A GPU
#     rocm     MPI + OpenMP + rocALUTION     (AMD/Hygon DCU)
#     cuda     MPI + OpenMP + AmgX           (NVIDIA)
#
#  If the account has no accelerator allocation (or the only usable
#  partition has no cards, e.g. cancon's kshctest02 which reports
#  Gres=(null)), use `hypre`: it is iterative, so it escapes the O(n^2)
#  memory wall that kills UMFPACK ~100 k edges, and it provides AMS, the
#  curl-conforming preconditioner that H(curl) edge elements need.  No
#  GPU, and far easier to bootstrap than MUMPS (no BLACS/ScaLAPACK).
#
#  Lessons baked in (all learned the hard way on cancon.hpccube.com):
#    1. system cmake is often 2.8 -> download the static cmake tarball
#    2. /usr/lib64/libblas.so is often a DANGLING dev symlink; cmake
#       "finds" it and the link step then fails with
#            No rule to make target '/usr/lib64/liblapack.so'
#       so always pass explicit BLAS_LIBRARIES / LAPACK_LIBRARIES
#    3. WITH_OpenMP=TRUE makes Elmer add -DMATC_OPENMP, which breaks the
#       Fortran module order under `make -j`:
#            ElementDescription.F90: USE Messages
#            Fatal Error: Can't open module file "Messages.mod"
#       fix afterwards with:
#            find . -name flags.make -exec sed -i 's/-DMATC_OPENMP//g' {} \;
#    4. do NOT use mpif90 as the Fortran compiler if you also want
#       -fopenmp -- the OpenMPI wrapper does not forward it.
#    5. ** cmake IGNORES unknown -D variables. **  Elmer's options are
#       mixed case (WITH_Mumps, WITH_Hypre), so `-DWITH_MUMPS=TRUE` is
#       silently a no-op and you get a UMFPACK-only build that still says
#       "success".  verify_features() now reads CMakeCache.txt back and
#       fails loudly.
# =====================================================================
set -euo pipefail

ELMER_SRC=${ELMER_SRC:-$HOME/elmerbuild/elmerfem-release-26.2}
ELMER_PREFIX=${ELMER_PREFIX:-$HOME/elmer262}
CMAKE=${CMAKE:-$HOME/elmerbuild/cmake/bin/cmake}
JOBS=${JOBS:-16}
RECIPE=${1:?usage: build_elmer.sh <cpu|rocm|cuda>}

[ -x "$CMAKE" ] || { echo "[err] cmake not found at $CMAKE"; exit 1; }

# ---- BLAS/LAPACK shim -------------------------------------------------
# Never trust a bare /usr/lib64/libblas.so: it is frequently a dangling
# symlink installed by a -devel package that is not present.
SHIM=$HOME/elmerbuild/libshim
mkdir -p "$SHIM"
find_blas () {
    for c in /usr/lib64/libblas.so.3 /usr/lib/x86_64-linux-gnu/libblas.so.3 \
             /usr/lib64/libblas.so;  do [ -e "$c" ] && { echo "$c"; return; }; done
}
find_lapack () {
    for c in /usr/lib64/liblapack.so.3 /usr/lib/x86_64-linux-gnu/liblapack.so.3 \
             /usr/lib64/liblapack.so; do [ -e "$c" ] && { echo "$c"; return; }; done
}
BLAS=$(find_blas); LAPACK=$(find_lapack)
ln -sf "$BLAS"   "$SHIM/libblas.so"
ln -sf "$LAPACK" "$SHIM/liblapack.so"
echo "BLAS   = $BLAS"
echo "LAPACK = $LAPACK"

# ---- Hypre bootstrap --------------------------------------------------------
# Elmer's cmake/Modules/FindHypre.cmake looks for the header `HYPRE.h` and the
# library `libHYPRE.so`, honouring the hint variable HYPRE_ROOT (read from BOTH
# the cmake cache and the environment) with /include and /lib beneath it:
#
#     find_path(Hypre_INCLUDE_DIR NAMES HYPRE.h  HINTS "${HYPRE_ROOT}/include")
#     find_library(Hypre_LIBRARY  NAMES HYPRE    HINTS "${HYPRE_ROOT}/lib")
#
# Hypre needs only MPI -- no BLACS/ScaLAPACK/METIS chain like MUMPS -- so the
# classic autotools configure is enough.  We build the *sequential-stub* MPI
# variant (hypre bundles mpi stubs), which is what Elmer links against.
HYPRE_VERSION=${HYPRE_VERSION:-2.32.0}
HYPRE_ROOT=${HYPRE_ROOT:-$HOME/elmerbuild/hypre-install}
EXPECT_HYPRE=0

build_hypre () {
    if [ -f "$HYPRE_ROOT/include/HYPRE.h" ] && \
       ls "$HYPRE_ROOT"/lib/libHYPRE.* >/dev/null 2>&1; then
        echo "Hypre    = already present in $HYPRE_ROOT"
        return
    fi
    echo "Hypre    = building v$HYPRE_VERSION into $HYPRE_ROOT"
    local src=$HOME/elmerbuild/hypre-$HYPRE_VERSION
    if [ ! -d "$src" ]; then
        ( cd "$HOME/elmerbuild" && \
          curl -sSL -o hypre.tar.gz \
            "https://github.com/hypre-space/hypre/archive/refs/tags/v$HYPRE_VERSION.tar.gz" && \
          tar xzf hypre.tar.gz && mv "hypre-$HYPRE_VERSION" "$src" ) \
          || { echo "[err] could not fetch hypre v$HYPRE_VERSION"; exit 1; }
    fi
    ( cd "$src/src" && \
      ./configure --prefix="$HYPRE_ROOT" --disable-fortran && \
      make -j"$JOBS" && make install ) \
      || { echo "[err] hypre build failed"; exit 1; }
    [ -f "$HYPRE_ROOT/include/HYPRE.h" ] \
      || { echo "[err] hypre installed but HYPRE.h is missing"; exit 1; }
}

# ---- feature verification ---------------------------------------------------
# cmake silently ignores unknown -D variables (it only prints
#   "Manually-specified variables were not used by the project")
# which is how a mistyped WITH_MUMPS / WITH_Hypre produced a UMFPACK-only
# Elmer that still reported a successful build.  Never trust the exit code:
# read the resolved values back out of the cache.
verify_features () {
    local cache=$BUILD/CMakeCache.txt rc=0 v
    echo
    echo "=== resolved solver features (from CMakeCache.txt) ==="
    if [ ! -f "$cache" ]; then
        echo "[err] $cache not found -- configure did not run"
        exit 1
    fi
    for k in WITH_UMFPACK WITH_Mumps WITH_Hypre WITH_ROCALUTION WITH_AMGX; do
        v=$(sed -n "s/^$k:BOOL=//p" "$cache" | head -1)
        printf '  %-16s = %s\n' "$k" "${v:-<unset>}"
    done
    echo "  Hypre_FOUND      = $(sed -n 's/^Hypre_FOUND:.*=//p' "$cache" | head -1)"
    echo
    # Must have at least one usable solver.
    if ! grep -q '^WITH_UMFPACK:BOOL=TRUE' "$cache" && \
       ! grep -q '^WITH_Mumps:BOOL=TRUE'   "$cache"; then
        echo "[err] neither UMFPACK nor Mumps ended up enabled"
        rc=1
    fi
    if [ "$EXPECT_HYPRE" = "1" ] && ! grep -qi '^WITH_Hypre:BOOL=TRUE' "$cache"; then
        echo "[err] WITH_Hypre was requested but the cache says it is NOT enabled."
        echo "      Did you mistype the variable?  Elmer spells it 'WITH_Hypre'."
        rc=1
    fi
    [ "$rc" = "0" ] || exit 1
}

BUILD=$HOME/elmerbuild/build_$RECIPE
rm -rf "$BUILD"; mkdir -p "$BUILD"; cd "$BUILD"

COMMON=(
  -DCMAKE_INSTALL_PREFIX="$ELMER_PREFIX"
  -DCMAKE_BUILD_TYPE=Release
  -DBLAS_LIBRARIES="$SHIM/libblas.so"
  -DLAPACK_LIBRARIES="$SHIM/liblapack.so"
)

case "$RECIPE" in

# ---------------------------------------------------------------------
cpu)
    # MPI + OpenMP, MUMPS for the large direct solves.
    # 512 GB of RAM makes MUMPS comfortably able to hold our biggest case
    # (279 898 edges -> ~31 GB LU); no need for out-of-core, which would
    # be painful on a node with NO local scratch.
    #
    # !! THE SPELLING OF WITH_Mumps MATTERS !!
    #   Elmer's CMakeLists.txt says:
    #       SET(WITH_Mumps FALSE CACHE BOOL "Use Mumps sparse direct solver")
    #   i.e. an upper-case W but a LOWER-CASE 'umps'.  This script used to
    #   pass -DWITH_MUMPS=TRUE, which CMake does not recognise: it only
    #   warns
    #       Manually-specified variables were not used by the project:
    #         WITH_MUMPS
    #   and leaves WITH_Mumps at its default FALSE, so the build "succeeds"
    #   while silently producing a UMFPACK-only Elmer -- exactly the
    #   configuration that cannot solve our large cases.  Same trap for
    #   WITH_Hypre / WITH_UMFPACK / WITH_CHOLMOD (all mixed case).
    #   verify_features() below now makes this failure mode impossible.
    echo "=== recipe: CPU (MPI + OpenMP + MUMPS) ==="
    "$CMAKE" "${COMMON[@]}" \
        -DWITH_MPI=TRUE -DWITH_OpenMP=TRUE \
        -DWITH_Mumps=TRUE \
        -DWITH_UMFPACK=TRUE \
        -DCMAKE_C_COMPILER=mpicc \
        -DCMAKE_CXX_COMPILER=mpicxx \
        -DCMAKE_Fortran_COMPILER=gfortran \
        "$ELMER_SRC"
    ;;

# ---------------------------------------------------------------------
hypre)
    # RECOMMENDED RECIPE WHEN THE DCU IS NOT AVAILABLE.
    #
    # MUMPS is a direct solver, so it inherits the same O(n^2) memory
    # growth that makes UMFPACK fall over ~100 k edges.  Hypre gives an
    # ITERATIVE AMG instead, and -- this is the important part -- it ships
    # **AMS**, the auxiliary-space Maxwell solver, which is the
    # curl-conforming preconditioner that H(curl) edge elements require.
    #
    # Why the previous "iterative route diverges" note was misleading:
    # plain BiCGStab + ILU genuinely diverges on Whitney edge elements,
    # but that is a property of ILU, not of Elmer.  Elmer has had a full
    # AMS implementation in fem/src/SolveHypre.c for years
    # (HYPRE_AMSCreate / HYPRE_AMSSetDiscreteGradient /
    #  HYPRE_AMSSetInterpolations); it was simply compiled out because
    # WITH_Hypre defaults to FALSE.  Upstream tests this exact
    # combination in fem/tests/mgdyn_hypre_ams ("BiCGStab as solver, AMS
    # as preconditioner").
    #
    # Hypre is also much easier to bootstrap than MUMPS: it needs only
    # MPI, no BLACS/ScaLAPACK/METIS chain.
    echo "=== recipe: Hypre (MPI + OpenMP + Hypre AMS) ==="
    build_hypre
    echo "HYPRE_ROOT = $HYPRE_ROOT"
    "$CMAKE" "${COMMON[@]}" \
        -DWITH_MPI=TRUE -DWITH_OpenMP=TRUE \
        -DWITH_Hypre=TRUE \
        -DWITH_UMFPACK=TRUE \
        -DHYPRE_ROOT="$HYPRE_ROOT" \
        -DCMAKE_C_COMPILER=mpicc \
        -DCMAKE_CXX_COMPILER=mpicxx \
        -DCMAKE_Fortran_COMPILER=gfortran \
        "$ELMER_SRC"
    EXPECT_HYPRE=1
    ;;

# ---------------------------------------------------------------------
rocm)
    # AMD / Hygon DCU.  Elmer's interface is rocALUTION (HAVE_ROCALUTION).
    #
    # On cancon.hpccube.com the stack is already installed:
    #     /opt/dtk-25.04.2/                      (Hygon DTK = ROCm fork)
    #     /opt/dtk-25.04.2/rocalution/lib/librocalution.so   <- what Elmer links
    #     /opt/dtk-25.04.2/rocalution/include/rocalution.hpp
    #     /opt/dtk-25.04.2/bin/hipcc
    #     source /opt/dtk-25.04.2/env.sh
    # NOTE: the DCU partitions (GRES `dcu:Hygon:4`) are HIDDEN from the
    # default `sinfo`; use `sinfo -a`.  You need an account authorised for
    # one of them, otherwise sbatch says
    #     Invalid account or account/partition combination specified
    echo "=== recipe: ROCm / rocALUTION (AMD, Hygon DCU) ==="
    DTK=${DTK:-/opt/dtk-25.04.2}
    # shellcheck disable=SC1090
    [ -r "$DTK/env.sh" ] && source "$DTK/env.sh" || true
    "$CMAKE" "${COMMON[@]}" \
        -DWITH_MPI=TRUE -DWITH_OpenMP=TRUE \
        -DWITH_ROCALUTION=TRUE \
        -DWITH_Mumps=TRUE \
        -DCMAKE_C_COMPILER=mpicc \
        -DCMAKE_CXX_COMPILER="$DTK/bin/hipcc" \
        -DCMAKE_Fortran_COMPILER=gfortran \
        -DROCALUTION_INCLUDE_DIR="$DTK/rocalution/include" \
        -DROCALUTION_LIBRARY="$DTK/rocalution/lib/librocalution.so" \
        "$ELMER_SRC"
    ;;

# ---------------------------------------------------------------------
cuda)
    # NVIDIA.  AmgX must be built FIRST with the same MPI + CUDA.
    echo "=== recipe: CUDA / AMGX (NVIDIA) ==="
    : "${AMGX_DIR:?set AMGX_DIR to the AmgX install prefix}"
    "$CMAKE" "${COMMON[@]}" \
        -DWITH_MPI=TRUE -DWITH_OpenMP=TRUE \
        -DWITH_AMGX=TRUE \
        -DWITH_Mumps=TRUE \
        -DCMAKE_C_COMPILER=mpicc \
        -DCMAKE_CXX_COMPILER=mpicxx \
        -DCMAKE_Fortran_COMPILER=gfortran \
        -DAMGX_INCLUDE_DIR="$AMGX_DIR/include" \
        -DAMGX_LIBRARY="$AMGX_DIR/lib/libamgxsh.so" \
        "$ELMER_SRC"
    ;;

*) echo "[err] unknown recipe '$RECIPE' (use cpu|hypre|rocm|cuda)"; exit 1;;
esac

# ---- prove the requested features really got enabled -------------------
# (a mistyped -D variable is ignored by cmake, not rejected)
verify_features

# ---- work around Elmer's MATC_OPENMP define ---------------------------
find . -name flags.make -exec sed -i 's/-DMATC_OPENMP//g' {} \; || true

make -j"$JOBS" install

# Elmer records the feature switches as HAVE_* macros in config.h; that is
# the ground truth for whether the Hypre branch in fem/src/SolveHypre.c was
# actually compiled in.
if [ "$EXPECT_HYPRE" = "1" ]; then
    echo
    if grep -q '^#define HAVE_HYPRE' config.h 2>/dev/null; then
        echo "  [ok] config.h has HAVE_HYPRE -- SolveHypre.c compiled in"
        echo "       (SIF: 'linear system use hypre = logical true' +"
        echo "             'Linear System preconditioning = ams')"
    else
        echo "  [err] WITH_Hypre was TRUE but config.h has no HAVE_HYPRE."
        echo "        SolveHypre.c was compiled out -- AMS will NOT be available."
        exit 1
    fi
fi

echo
echo "=== installed ==="
ls -la "$ELMER_PREFIX/bin/ElmerSolver" || true
echo
echo "NOW RUN THE SMOKE TEST -- it must not print 'umf4num: -1.0':"
echo "  cd \$HOME/elmerbuild && cp -r $ELMER_SRC/fem/tests/mgdyn_transient ."
echo "  ELMER_HOME=$ELMER_PREFIX $ELMER_PREFIX/bin/ElmerSolver case.sif | tail -20"
if [ "$EXPECT_HYPRE" = "1" ]; then
    echo
    echo "and prove AMS itself works on the upstream test case:"
    echo "  cp -r $ELMER_SRC/fem/tests/mgdyn_hypre_ams ."
    echo "  cd mgdyn_hypre_ams && ELMER_HOME=$ELMER_PREFIX \\"
    echo "      $ELMER_PREFIX/bin/ElmerSolver case.sif | tail -30"
fi

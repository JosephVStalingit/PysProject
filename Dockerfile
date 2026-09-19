# syntax=docker/dockerfile:1
# =============================================================================
#  PysProject -- Elmer 26.2.1 + gmsh + pyvista, fully self-contained
#
#  WHY ELMER IS COMPILED HERE (and not apt-installed)
#    Debian 12 ships no elmerfem package.  Inside python:3.11-slim,
#    `apt-cache search elmer` returns one unrelated perl module and nothing
#    else, so the previous recipe's `apt-get install elmerfem` could never
#    have succeeded.
#
#  WHY EXACTLY THESE CMAKE FLAGS
#    They are read out of the shipped Windows build tree
#    (elmer262/CMakeCache.txt) that produced every validated result in this
#    repo:
#         WITH_UMFPACK          TRUE    <- the only solver flag that is ON
#         every other WITH_*    FALSE   (no MPI, no MUMPS, no OpenMP,
#                                        no ROCALUTION, no Hypre, no MKL)
#    The SIF's `Linear System Solver = Direct` lands on UMFPACK, so matching
#    this flag is what makes the container reproduce the Windows numbers.
#    Do not casually "improve" it.
#
#  BUILD / EXPORT
#      docker build -t pysproject:3.5.0 .
#      docker save pysproject:3.5.0 -o pysproject-3.5.0.tar
# =============================================================================

ARG PY_BASE=python:3.11-slim
ARG PIP_INDEX=https://pypi.org/simple

# -----------------------------------------------------------------------------
#  Stage 1 -- compile Elmer 26.2.1
# -----------------------------------------------------------------------------
FROM debian:12-slim AS elmer

ARG ELMER_TAG=release-26.2.1
ARG NJOBS=
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake gfortran curl ca-certificates \
        libopenblas-dev liblapack-dev \
        m4 file \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN curl -fsSL -o elmer.tar.gz \
        "https://github.com/ElmerCSC/elmerfem/archive/refs/tags/${ELMER_TAG}.tar.gz" \
 && tar -xzf elmer.tar.gz \
 && mv elmerfem-* elmerfem \
 && rm -f elmer.tar.gz

# NOTE: this runs about 20-35 min.  The flag list is the parity contract.
RUN set -eu; \
    cmake -S elmerfem -B build -G "Unix Makefiles" \
          -DCMAKE_INSTALL_PREFIX=/opt/elmer \
          -DCMAKE_BUILD_TYPE=Release \
          -DWITH_UMFPACK=TRUE \
          -DWITH_Mumps=FALSE \
          -DWITH_MPI=FALSE \
          -DWITH_OpenMP=FALSE \
          -DWITH_ElmerGUI=FALSE \
          -DWITH_ELMERPOST=FALSE \
          -DWITH_LUA=FALSE \
          -DWITH_Hypre=FALSE \
          -DWITH_ROCALUTION=FALSE \
          -DWITH_MKL=FALSE \
          -DWITH_NETCDF=FALSE \
          -DWITH_CHOLMOD=FALSE \
          -DWITH_Trilinos=FALSE \
          -DWITH_Zoltan=FALSE \
          -DWITH_MMG=FALSE \
          -DWITH_XIOS=FALSE ; \
    cmake --build build -j "${NJOBS:-$(nproc)}" ; \
    cmake --install build

# Fail the build now if the binaries cannot resolve their shared libs,
# rather than shipping an image that only breaks at solve time.
RUN set -eu; \
    ls -l /opt/elmer/bin/ ; \
    for b in ElmerSolver ElmerGrid ; do \
        if ldd "/opt/elmer/bin/$b" 2>&1 | grep -q "not found"; then \
            echo "FATAL: $b has missing shared libraries:" ; \
            ldd "/opt/elmer/bin/$b" | grep "not found" ; exit 1 ; \
        fi ; \
    done ; \
    echo "ElmerSolver / ElmerGrid link cleanly"

# -----------------------------------------------------------------------------
#  Stage 2 -- precompile every Python wheel (some deps have C extensions)
# -----------------------------------------------------------------------------
FROM ${PY_BASE} AS wheels

ARG PIP_INDEX
ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential gfortran \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /w
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip wheel --wheel-dir=/wheels --index-url="${PIP_INDEX}" -r requirements.txt

# -----------------------------------------------------------------------------
#  Stage 3 -- runtime
# -----------------------------------------------------------------------------
FROM ${PY_BASE} AS runtime

ARG PIP_INDEX

LABEL org.opencontainers.image.title="pysproject" \
      org.opencontainers.image.description="Magnet free-fall / spring FEM pipeline (Elmer 26.2.1 + gmsh + pyvista)" \
      org.opencontainers.image.version="3.5.0" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Runtime shared libs:
#   libgfortran5 / libquadmath0 /
#   libopenblas0-pthread / libgomp1       -> Elmer + numpy
#     libquadmath0 is easy to miss: the builder stage gets it for free from
#     gfortran, but the runtime stage does not, and without it ElmerSolver
#     dies with "error while loading shared libraries: libquadmath.so.0".
#   The X11 client set + libgl1/libglu1-mesa -> gmsh's OCC kernel and VTK.
#     gmsh links the full OpenCASCADE X stack even in batch mode, and VTK
#     links its X/GL back-ends, so the whole set must be present.  They fail
#     one library at a time at import time (seen so far: libXcursor.so.1,
#     then libXft.so.2), so the complete set is listed up front rather than
#     rediscovered by repeated rebuilds.
#     libgl1-mesa-dri + libosmesa6 give the software GL that pyvista uses for
#     off-screen rendering when there is no GPU.
#   libfontconfig1 / libfreetype6         -> matplotlib + pyvista headless
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libgfortran5 libquadmath0 libgcc-s1 \
        libopenblas0-pthread libgomp1 \
        libgl1 libglu1-mesa libglx0 libegl1 \
        libgl1-mesa-dri libosmesa6 \
        libx11-6 libxext6 libxrender1 libxfixes3 libxcursor1 \
        libxi6 libxrandr2 libxinerama1 libxkbcommon0 libxkbcommon-x11-0 \
        libxft2 libxpm4 libxmu6 libxaw7 libxt6 \
        libxcb1 libxau6 libxdmcp6 libsm6 libice6 \
        libxcb-render0 libxcb-shm0 libxcb-util1 libxcb-image0 \
        libxcb-keysyms1 libxcb-randr0 libxcb-xinerama0 libxcb-icccm4 \
        libxcb-sync1 libxcb-xfixes0 libxcb-shape0 libxcb-xkb1 \
        libfontconfig1 libfreetype6 \
        procps \
 && rm -rf /var/lib/apt/lists/*

# Elmer, straight from stage 1
COPY --from=elmer /opt/elmer /opt/elmer

# Python deps, straight from stage 2 (no network needed at runtime)
COPY --from=wheels /wheels /wheels
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-index --find-links=/wheels -r /tmp/requirements.txt \
 && rm -rf /wheels /tmp/requirements.txt

# Elmer runtime environment.
#
# LD_LIBRARY_PATH must list BOTH directories:
#   lib/elmersolver          <- libelmersolver.so, libmatc.so, libfhuti.so,
#                               libarpack.so, libmpi_stubs.so
#   share/elmersolver/lib    <- the solver plugins (WaveSolver.so, ...)
# The plugins have NO RUNPATH of their own and hard-require libelmersolver.so,
# while only the top-level binaries get `$ORIGIN/../lib/elmersolver`.  Omit the
# first path and every plugin fails its ldd check.
ENV ELMER_HOME=/opt/elmer \
    ELMER_SOLVER_HOME=/opt/elmer/share/elmersolver \
    ELMER_LIB=/opt/elmer/share/elmersolver/lib \
    LD_LIBRARY_PATH=/opt/elmer/lib/elmersolver:/opt/elmer/share/elmersolver/lib \
    PATH=/opt/elmer/bin:/usr/local/bin:/usr/bin:/bin

WORKDIR /app

# Application source.  Keep this list explicit: it is also the contract for
# what the image can run.  .dockerignore is what keeps the build context
# small -- elmer262/ alone is ~259 MB of Windows binaries we do not ship.
COPY solenoid3d.py spring_model.py make_sif.py oscilloscope.py \
     config.json case_transient.sif __version__.py __init__.py \
     clean.sh run_tests.sh ./
COPY tests/ ./tests/
COPY test_outputs/verify_bfield.py test_outputs/verify_fall.py \
     test_outputs/verify_spring.py ./test_outputs/

RUN chmod +x run_tests.sh clean.sh \
 && mkdir -p mesh results test_outputs

# Prove the toolchain is coherent at build time, and fail loudly if not.
#
# NOTE: `ElmerSolver -version` prints the banner and THEN exits 1, because
# Elmer treats "-version" as the name of a SIF file it cannot open.  The
# exit status therefore has to be swallowed with `|| true`; under `set -e`
# it would abort the build even though the version line printed fine.
RUN set -eu; \
    ElmerSolver -version > /tmp/elmerver.txt 2>&1 || true ; \
    echo "--- ElmerSolver -version ---" ; head -3 /tmp/elmerver.txt ; \
    grep -q "26\.2" /tmp/elmerver.txt || { \
        echo "FATAL: ElmerSolver did not report v26.2" ; \
        cat /tmp/elmerver.txt ; exit 1 ; } ; \
    rm -f /tmp/elmerver.txt ; \
    echo "--- ldd sweep over every Elmer binary and solver .so ---" ; \
    missing=0 ; \
    for f in /opt/elmer/bin/* /opt/elmer/lib/elmersolver/*.so \
             /opt/elmer/share/elmersolver/lib/*.so ; do \
        [ -f "$f" ] || continue ; \
        if ldd "$f" 2>&1 | grep -q "not found" ; then \
            echo "MISSING LIB for $f:" ; \
            ldd "$f" | grep "not found" ; missing=1 ; \
        fi ; \
    done ; \
    if [ "$missing" -ne 0 ] ; then \
        echo "FATAL: unresolved shared libraries in the Elmer install" ; \
        exit 1 ; \
    fi ; \
    echo "all Elmer binaries resolve their shared libraries" ; \
    python -c "import gmsh, meshio, pyvista, numpy, matplotlib; \
               print('py deps ok: numpy', numpy.__version__, \
                     '| pyvista', pyvista.__version__)" ; \
    echo "image self-check passed"

HEALTHCHECK --interval=60s --timeout=30s --start-period=10s --retries=3 \
    CMD python -c "import gmsh; gmsh.initialize(); gmsh.finalize()" || exit 1

ENTRYPOINT ["./run_tests.sh"]
CMD []

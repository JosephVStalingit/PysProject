#!/bin/bash
# =====================================================================
#  hpc/test_dcu.sh  --  validate the Hygon DCU resource AND an
#                       Elmer build that uses it.
#
#  Submit this to a DCU partition.  It answers, in order:
#     1. is a DCU actually visible to the job?
#     2. does the DTK / rocALUTION stack work?
#     3. does a HIP program compile and run?
#     4. does ElmerSolver link against rocALUTION?
#     5. does the 3-step smoke test on OUR case converge?
#
#  Usage (on cancon.hpccube.com, once the account is authorised):
#
#      sbatch -p kshdexclu01 --gres=dcu:1 --account=<ACCOUNT> hpc/test_dcu.sh
#
#  NOTE: the DCU partitions are hidden from a plain `sinfo`; use `sinfo -a`.
#  Without the account/partition association sbatch refuses with
#      Invalid account or account/partition combination specified
# =====================================================================
#SBATCH --job-name=dcutest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=dcu:1
#SBATCH --time=00:30:00
#SBATCH --output=dcutest-%j.out
#SBATCH --error=dcutest-%j.err

DTK=${DTK:-/opt/dtk-25.04.2}
ELMER_HOME=${ELMER_HOME:-$HOME/elmer262_dcu}
ELMER_LIB="$ELMER_HOME/share/elmersolver/lib"

echo "=============================================="
echo " job $(hostname)   started $(date)"
echo " partition=$SLURM_JOB_PARTITION  gres=$SLURM_JOB_GRES"
echo "=============================================="

echo
echo "--- 1. DCU visible to this job? ---"
if [ -r "$DTK/env.sh" ]; then source "$DTK/env.sh"; else
    export PATH="$DTK/bin:$PATH"; export LD_LIBRARY_PATH="$DTK/lib:$LD_LIBRARY_PATH"; fi
rocminfo 2>&1 | grep -iE "Agent |Name:|Marketing|gfx|Compute Unit" | head -20 \
    || echo "  rocminfo FAILED"
echo "  hipcc: $(command -v hipcc || echo MISSING)"

echo
echo "--- 2. DTK / rocALUTION stack ---"
for f in "$DTK/rocalution/lib/librocalution.so" \
         "$DTK/lib/libamdhip64.so" "$DTK/lib/libhipblas.so"; do
    [ -e "$f" ] && echo "  OK   $f" || echo "  MISS $f"
done

echo
echo "--- 3. tiny HIP program ---"
T=$(mktemp -d); cd "$T"
cat > t.cpp <<'EOF'
#include <hip/hip_runtime.h>
#include <cstdio>
int main(){
  int n=0; hipGetDeviceCount(&n);
  printf("  hipGetDeviceCount = %d\n", n);
  for(int i=0;i<n;i++){ hipDeviceProp_t p; hipGetDeviceProperties(&p,i);
    printf("  dev %d: %s  gcnArch=%s  mem=%.1f GB\n", i, p.name,
           p.gcnArchName, p.totalGlobalMem/1073741824.0); }
  return n>0?0:1;
}
EOF
hipcc -o t t.cpp 2>&1 | head -5 && ./t 2>&1 | head -6 || echo "  HIP compile/run FAILED"
cd - >/dev/null; rm -rf "$T"

echo
echo "--- 4. ElmerSolver built with rocALUTION? ---"
if [ -x "$ELMER_HOME/bin/ElmerSolver" ]; then
    strings "$ELMER_HOME/bin/ElmerSolver" 2>/dev/null | grep -ci rocalution \
        | xargs -I{} echo "  rocalution strings in binary: {}"
    ldd "$ELMER_HOME/bin/ElmerSolver" 2>/dev/null | grep -i rocalution \
        || echo "  (not dynamically linked to rocALUTION -- check -DWITH_ROCALUTION)"
else
    echo "  ElmerSolver not found at $ELMER_HOME/bin -- build it first:"
    echo "      bash hpc/build_elmer.sh rocm"
fi

echo
echo "--- 5. Elmer 3-step smoke test on OUR case ---"
CASE=${CASE:-$HOME/pysproject/cases/L020_ri020_coarse}
if [ -d "$CASE" ] && [ -x "$ELMER_HOME/bin/ElmerSolver" ]; then
    cd "$CASE"
    sed 's/^Timestep Intervals.*/Timestep Intervals     = 3/' case.sif > _smoke.sif
    export PATH="$ELMER_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$ELMER_LIB:$DTK/lib:$LD_LIBRARY_PATH"
    ( cd "$CASE" && ElmerSolver _smoke.sif ) > _smoke.log 2>&1
    if grep -q "umf4num:   -1" _smoke.log; then
        echo "  [FAIL] umf4num ABI bug is BACK -- solver still broken"
    elif grep -q "ALL DONE" _smoke.log; then
        echo "  [PASS] 3 steps completed"
    else
        echo "  [??]   check $CASE/_smoke.log"
    fi
    tail -6 _smoke.log | sed 's/^/      /'
else
    echo "  skipped (case dir or ElmerSolver missing)"
fi

echo
echo " done $(date)"

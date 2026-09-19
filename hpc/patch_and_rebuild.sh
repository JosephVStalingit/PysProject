#!/bin/bash
#SBATCH --job-name=fixL
#SBATCH --partition=kshctest02
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=01:00:00
#SBATCH --output=fixL-%j.out
#SBATCH --error=fixL-%j.err
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!  DO NOT RUN THIS SCRIPT.  IT IS A RETRACTED FALSE LEAD.               !!
# !!                                                                       !!
# !!  2026-09-16: the premise below was WRONG and the patch it applies was  !!
# !!  physically incorrect, so it was reverted the same day.  Kept only as  !!
# !!  a record.  Use hpc/test_wvec_path.sh instead.                         !!
# !!                                                                       !!
# !!  WHY IT WAS WRONG -- the stranded and solid conductor terms are NOT    !!
# !!  supposed to be symmetric:                                            !!
# !!      stranded : J = N_j * I * w            (NO sigma)                 !!
# !!      massive  : J = -sigma * dA/dt         (sigma INSIDE)              !!
# !!  so `Psi = N_j * Integral(A.w) dV` [units: 1/m^2 * Wb/m * m^3 = Wb]    !!
# !!  must NOT carry `localC`.  Adding `/localC` would have made the coil    !!
# !!  self-inductance ~2.87e6 times TOO SMALL.  See the comment block now    !!
# !!  standing in CircuitsAndDynamics.F90 at the flux-linkage term.          !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# --- original (WRONG) rationale, retained for the record --------------------
#
# patch_and_rebuild.sh -- apply the flux-linkage sigma fix to
# CircuitsAndDynamics.F90, rebuild the module, install it into the Elmer
# prefix, then run a 30-step VALIDATION of the N25 case.
#
# WHY (RETRACTED): see README 7.4.4 / 7.5.  The transient flux-linkage term
# carried an uncancelled sigma while the resistance term cancels it via
# /localC, which inflated the coil self-inductance by ~3.7e6 (L_model = 460 H
# vs the true 1.249e-4 H).  The fix appends `/localC` to that term.
#
set -uo pipefail
export PATH=$HOME/elmerbuild/cmake/bin:$PATH

SRC=$HOME/elmerbuild/elmerfem-release-26.2/fem/src/modules/CircuitsAndDynamics.F90
BUILD=$HOME/elmerbuild/build
PREFIX=$HOME/elmer262

echo "host      : $(hostname)"
echo "started   : $(date)"
echo "src       : $SRC"
[ -f "$SRC" ] || { echo "[err] source not found"; exit 1; }

cp -f "$SRC" "$SRC.orig_$(date +%m%d_%H%M)"
echo "backed up source"

# ---------------------------------------------------------------- 1. patch
# tolerant match: no end-of-line anchor (trailing blanks are harmless),
# and skip any line that already carries /localC (the resistance line does).
awk '
  /val = Comp % N_j \* IP % s\(t\)\*detJ\*Basis\(j\)\*circ_eq_coeff\/dt\*w\(3\)/ {
      if ($0 !~ /\/localC/) { sub(/[ \t]*$/, ""); $0 = $0 "/localC"; n1++ }
      print; next }
  /val = Comp % N_j \* IP % s\(t\)\*detJ\*SUM\(WBasis\(j,:\)\*w\)\/dt/ {
      if ($0 !~ /\/localC/) { sub(/[ \t]*$/, ""); $0 = $0 "/localC"; n2++ }
      print; next }
  { print }
  END { printf "  patched dim2=%d dim3=%d\n", n1, n2 > "/dev/stderr" }
' "$SRC" > "$SRC.patched"

echo "lines containing 'SUM(WBasis(j,:)*w)/dt/localC' after patch:"
grep -cn 'SUM(WBasis(j,:)\*w)/dt/localC' "$SRC.patched" || true
echo "all N_j-flux lines after patch:"
grep -n 'val = Comp % N_j \* IP % s(t)\*detJ' "$SRC.patched" || true

if [ "$(grep -c 'SUM(WBasis(j,:)\*w)/dt/localC' "$SRC.patched")" != "1" ]; then
    echo "[abort] the 3D flux term was NOT patched -- source layout differs."
    echo "        Fix the awk pattern; nothing was written."
    exit 1
fi
mv -f "$SRC.patched" "$SRC"
echo "source patched OK"

# ------------------------------------------------------------- 2. rebuild
echo
echo "=== rebuilding CircuitsAndDynamics ==="
cd "$BUILD/fem/src/modules" || exit 1
rm -f CMakeFiles/CircuitsAndDynamics.dir/CircuitsAndDynamics.F90-pp.f90 \
      CMakeFiles/CircuitsAndDynamics.dir/CircuitsAndDynamics.F90.obj
make CircuitsAndDynamics 2>&1 | tail -25 || {
    echo "[err] make failed"; exit 1; }
ls -la CircuitsAndDynamics.so

# ------------------------------------------------------- 3. install to prefix
echo
echo "=== installing ==="
INST="$PREFIX/share/elmersolver/lib/CircuitsAndDynamics.so"
ls -la "$INST"
echo "md5 of installed .so : $(md5sum "$INST" | cut -d' ' -f1)"
echo "--- candidate build trees ---"
for b in "$HOME/elmerbuild/build" "$HOME/elmerbuild/build_omp" \
         "$HOME/elmerbuild/build_omp2" "$HOME/elmerbuild/build_omp3"; do
    so="$b/fem/src/modules/CircuitsAndDynamics.so"
    if [ -f "$so" ]; then
        printf "  %-40s %s\n" "$b" "$(md5sum "$so" | cut -d' ' -f1)"
    fi
done
# the tree we rebuilt in must be the one matching the install; verify by
# size before overwriting (the .so changed, so md5 will differ -- compare
# the OTHER build trees to make sure none of them matches instead)
echo "--- sanity: which build tree matches the install? ---"
MATCH=""
for b in "$HOME/elmerbuild/build_omp" "$HOME/elmerbuild/build_omp2" \
         "$HOME/elmerbuild/build_omp3"; do
    so="$b/fem/src/modules/CircuitsAndDynamics.so"
    [ -f "$so" ] || continue
    if [ "$(md5sum "$so" | cut -d' ' -f1)" = "$(md5sum "$INST" | cut -d' ' -f1)" ]; then
        MATCH="$b"
    fi
done
if [ -n "$MATCH" ]; then
    echo "[abort] the installed .so matches $MATCH, not ~/elmerbuild/build."
    echo "        Rebuild in THAT tree instead (or stop here and report)."
    exit 1
fi
echo "  no other tree matches -> ~/elmerbuild/build is the right one"
# keep a restore point BEFORE overwriting
BK="$PREFIX/share/elmersolver/lib/CircuitsAndDynamics.so.pre_fixL_$(date +%m%d_%H%M)"
cp -f "$INST" "$BK"
echo "backed up installed .so -> $BK"
cp -f CircuitsAndDynamics.so "$INST"
echo "installed (new):"
ls -la "$INST"
echo "restore with:  cp -f $BK $INST" > "$HOME/RESTORE_CircuitsAndDynamics.txt"
echo "restore cmd written to ~/RESTORE_CircuitsAndDynamics.txt"

# ------------------------------------------------------------ 4. validation
# a 30-step N25 run in a scratch dir, so the study results are untouched
echo
echo "=== validation: 30 steps of N25 ==="
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib:$PREFIX/share/elmersolver/lib:${LD_LIBRARY_PATH:-}
V=$HOME/validate_fixL/N25
rm -rf "$V"; mkdir -p "$V"
for f in case.sif circuits.definitions config.json model3d.msh; do
    cp "$HOME/pysproject/cases/N25_L040_cu_closed/$f" "$V/"
done
cp -r "$HOME/pysproject/cases/N25_L040_cu_closed/mesh" "$V/mesh"
# shorten to 30 steps
awk '/^  Timestep Intervals/ {print "  Timestep Intervals     = 30"; next} {print}' \
    "$V/case.sif" > "$V/case.tmp" && mv -f "$V/case.tmp" "$V/case.sif"
grep -E '^  Timestep' "$V/case.sif"
cd "$V" || exit 1
$PREFIX/bin/ElmerSolver case.sif > solve.log 2>&1
echo "ElmerSolver rc=$?"
grep -c 'MAIN: Time' solve.log
if [ -f results/circuit.csv ]; then
    echo "step 17 row:"
    awk 'NR==17 {printf "  i1=%.6e  v1=%.6e  r_comp1=%.6e\n", $10, $11, $14}' \
        results/circuit.csv
else
    echo "[err] no circuit.csv"; tail -20 solve.log; exit 1
fi
echo "finished  : $(date)"

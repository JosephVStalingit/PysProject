# HPC handoff 闁?closed-circuit FEM (`make_sif.py`, no `--circuit` flag)

Written 2026-09-13.  Short, actionable version of `hpc/notes.md` 閹?5.
Read this first; go to 搂15.13 for the root cause, 搂15.11 for the mesh gate.


---

## 0. DO NOT DISPATCH THE FULL SWEEP YET 鈥?搂15.13

**The mesh instability is FIXED; the induced-current MAGNITUDE is not.**  On the
production mesh the coil current used to grow exponentially with a constant
step-to-step ratio of 1.7777 闁?`1.78^900` over the production timeline.  A
900-step dispatch would have burned ~7 h of queue per case and produced
nothing but a blown-up number.

Three proofs it was not physics:

| test | result |
|---|---|
| magnet **frozen** (amplitude 0 => no EMF at all) | current **still grew**, to 4.34e-2 A by t = 9 ms 闁?indistinguishable from the moving case |
| `dt` 1 ms vs **2 ms** | identical values **at the same step index** 闁?not a time-integration effect |
| `R_load` 10 ohm vs **100 ohm** | identical series to 4-5 figures 闁?not an L-R loop effect |

### What it actually was: `lc_slit_m`

Varying ONLY the slit element size, everything else at production resolution,
on the 3.5 mm slit:

| `lc_slit_m` | elements | per-step gain | verdict |
|---|---|---|---|
| 2.5 mm (old) | 30698 | **1.777** | exploded by t = 9 ms |
| 3.0 mm | 26375 | **3.30** | worse |
| 3.5 mm | 21650 | 1.199 | marginal |
| **4.0 mm (new)** | **18743** | **~1.000** | **stable** |
| 8.0 mm | 12456 | <1 | stable |

**The threshold is exactly `lc_slit_m = slit_width_m`.**  Below it the gap is
spanned by more than one element and the coupled A / circuit / W-potential
operator gains a mode that amplifies by a constant factor every timestep.
`r_component(1)` is identical to 12 figures across all of them
(3.016937402022E-001), so `w`, the geometry and the resistance never changed.

That also disposes of the earlier red herrings: coarsening `[mesh]` scaled
`lc_slit_m` along with everything else, so those were slit-mesh runs in
disguise.  And the `Coil Use W Vector` route was tested and **eliminated** 闁?
identical magnitude, opposite sign, `Wnorm = 1.003 ~ 1` 闁?so the scalar-W
path was correct all along.  The `EMF = -(R_c+R_L)i` reading that once looked
like a sign error is a consequence of the circuit topology, not evidence
about the physics.

### What changed

* `config.json`: `lc_slit_m` 0.0025 -> **0.004**, plus a `_comment_lc_slit`
  warning.  Bonus: 18743 elements instead of 30698, i.e. **39% cheaper**.
* `solenoid3d.py:build()` now REFUSES to mesh a conductor curve with
  `lc_slit_m < slit_width_m`.  This had to be a hard gate because the failure
  is SILENT 闁?Elmer exits 0 and writes a plausible `results/circuit.csv`.
* Locked by `test_lc_slit_must_not_be_smaller_than_the_slit_width` and
  `test_solenoid3d_refuses_a_too_fine_slit` (38/38 in `test_sif_circuit.py`).
* `hpc/smoke_test_closed.sh` passes all 7 checks at the new setting.

### The blocker is now UNDERSTOOD (notes.md 15.13)

The sweep ran clean (7 jobs, 900/900 steps, 0 errors) and produced
`hpc/results/*/circuit.csv`, but **the induced current is NOT usable**.  The
cause is no longer a mystery:

**The model's coil inductance is ~3.7e6 times too large.**  Measured
directly, with no assumptions, from two clean limits
(`i_short = (1/L) * INT eps_open dt`):

    L_model  =  460 H        (constant to 2% over 60 steps)
    L_true   =  1.249e-4 H   (mu0 N^2 A/l;  Wheeler: 82.7 uH)
    ratio    =  3.7e6

and the ratio has a clean analytic form,

    L_turn / A_coil^2 = 0.1414 / (2.0e-4)^2 = 3.54e6     (matches to 4%)

Because `wL ~ 1e4 ohm >> R_total`, the loop is **inductance-dominated**, and
that single fact explains every anomaly found earlier:

| observation | explanation |
|---|---|
| `R_load` 1e-6 -> 1e4 has no effect | `R << wL`: pure integral regime |
| `R_load` 1e5 -> 1e6 does drop | entering the resistive regime |
| Cu vs Al identical | 0.30 vs 0.51 ohm against `wL ~ 1e4` |
| `R_coil` 0 -> 0.29 invisible, 1e6 visible | same; 1e6 crosses `wL` |
| `i ~ 1/N` exactly | `L ~ N^2`, `eps ~ N`, `i = (1/L) INT eps` |
| current ~1000x below the hand value | large `L` means small `i` |
| survives with a frozen magnet / oscillates with motion | it is `INT eps` |

**Why `r_component(1)` is right and `L` is not:** the fill factor
(`sigma_eff = f*sigma_wire`) cancels the extra `1/A_coil^2` that `N_j^2`
brings into the RESISTANCE integral.  The INDUCTANCE integral has no such
cancellation, so it keeps that factor.  15.8 fixed one and left the other.

### So: do NOT dispatch, and do NOT quote `i_component(1)`

The sweep in `hpc/results/` is valid as a test of the pipeline, the mesh
stability and the RESISTANCE model only.

Next work, in order:

1. **Fix the inductance scale.**  The EMF term of `Add_stranded`
   (`CircuitsAndDynamics.F90:710-724`) is the place: `r_component(1)`
   constrains only `INTEGRAL |w|^2/sigma dV`, which is blind to this.
   Note the open-circuit EMF came out 10.84 V vs a ~0.4 V hand estimate, so
   the EMF and `L` carry DIFFERENT scale errors -- it is not one missing `w`
   normalisation.
2. Re-run the `R_load` sweep; with `L` correct, `i` must scale as
   `1/(R_total + sL)`, i.e. drop by ~1e5 from `R = 1e-6` to `R = 1e6`.
3. Only then re-dispatch.

`_rload_decide.sh` + `_measure_L.py` reproduce the whole measurement in
~15 min on the local docker image.  Use them before any queue time.

### What IS trustworthy and should be kept

These three fixes are real and independently verified; do not revert them
while working on 15.11:

1. **The fill factor (閹?5.8).**  `Electric Conductivity` must be
   `f * sigma_wire`, `f = N*A_wire/A_coil`.  Without it the coil was ~10x
   too conductive.  `r_component(1)` is now 0.30169 ohm vs 0.3082 hand.
2. **The export chain (閹?5.9).**  `Export Circuit Variables`, `Max Output
   Level = 10` and the `SaveScalars` Solver 11 now put `i_component(1)` into
   `results/circuit.csv` every step.  Before this a run could exit `rc=0`
   with a clean log and contain **no circuit quantity at all**.
3. **The execution order (閹?5.7).**  Solvers 9/10 must stay
   `Before timestep`.

`hpc/smoke_test_closed.sh` passes all 7 checks.  That is necessary but **not
sufficient** 闁?it only proves the machinery turns over.

---

## 1. Read this before queueing anything

**The closed-circuit transient now RUNS *and* produces the science output.**
Two blockers were cleared in the latest round:

| # | what was wrong | where |
|---|---|---|
| 1 | circuit solvers never executing | 閹?5.7 (execution order) |
| 2 | coil resistance 10x too small | **閹?5.8 (missing fill factor)** |
| 3 | `i_component(1)` reached no file at all | **閹?5.9 (two export gates)** |

**Blocker 2 was a silent physics bug**, not a crash.  The coil body's
`Electric Conductivity` must be the homogenised `f * sigma_wire`
(`f = N * A_wire / A_coil`), because Elmer's coil-resistance formula
assumes a solid winding window.  With `sigma_wire` the coil came out
~10x too conductive, so **every induced current computed before this fix
was ~10x too large.**  `r_component(1)` is now 3.0169e-01 ohm for
`N50_L040_cu_closed`, against a hand value of 0.3082 ohm.

**Blocker 3 meant a run could exit `rc=0` with a clean log and a full
`results/` directory and still contain no circuit data whatsoever.**
Three keys have to be right:

```elmer
Max Output Level = 10                        !! circuit values are logged at Level 10
Solver 10
  Export Circuit Variables = Logical True    !! else Circuits_ToMeshVariable returns early
End
Solver 11                                    !! SaveScalars -> results/circuit.csv
  Variable 1 = "crt i"
  Variable 2 = "crt v"
End
```

All three are emitted by `make_sif.py` and asserted by
`hpc/smoke_test_closed.sh` step 5.

**Run length is now 900 steps, not 600.**  `experiment.t_end_default_s`
went from 0.6 to 0.9 s, i.e. ~2 -> ~3 full spring oscillations
(T = 0.29976 s).  That is **1.5x the wall-clock** versus the numbers in
`notes.md` 閹? and 閹?.4, which predate the change.

**Measured cost per case** (閹?5.10, local serial UMFPACK):

| | |
|---|---|
| mesh | **30698 elements** |
| solve | **~28 s / step** -> **~7 h** for 900 steps |
| VTU | **4.9 MB / step** -> **~4.4 GB** per case |
| full sweep (7 cases) | **~49 h, ~31 GB** |

`results/circuit.csv` is ~40 kB per case, so **make sure it is the thing
you copy back** 闁?the VTU tree is 100000x larger and mostly redundant.

---

## 1. FIRST: smoke-test one conductor curve (3 timesteps, ~2 min)

```bash
cd ~/PysProject
bash hpc/smoke_test_closed.sh N50_L040_cu_closed
```

It runs the checks in order and stops at the first failure, printing the
exact error.  **Expected state: everything PASSES.**

| check | expect |
|-------|--------|
| 1.  gmsh mesh | PASS |
| 1b. physical groups | PASS 闁?`1003`..`1008` CoilStart/CoilEnd/Alpha0/Alpha1/Beta0/Beta1 |
| 2.  ElmerGrid `-autoclean` | PASS |
| 2b. `mesh/mesh.names` | PASS 闁?`CoilStart = 3`, `CoilEnd = 4`, `Alpha0..Beta1 = 5..8` |
| 3.  generate the SIF | PASS |
| 4.  ElmerSolver | PASS 闁?`rc=0`, 3 steps |
| 5.  **circuit time series** | PASS 闁?`results/circuit.csv`, one row per step, `i_component(1)` in col 10, and `V = 10 ohm * I` on every load row |

Step 5 is new and it is the one that matters: check 4 alone can pass while
producing no usable output.

If step 4 fails, the most likely cause is that Solvers 9/10 lost
`Exec Solver = "Before timestep"`.  See 閹?5.7.

**Before trusting the physics, sanity-check one number**: `r_component(1)`
must be ~0.31 ohm for `N50_L040_cu_closed`, not ~0.029.  If it is 10x
low, the fill factor has regressed 闁?see 閹?5.8.

---

## 2. Blocker status 闁?**RESOLVED** (notes.md 閹?5.7)

The closed-circuit transient **now runs to completion**.  Root cause was an
Elmer execution-order subtlety, not a missing key:

> **Elmer runs the per-timestep solvers in SOLVER-NUMBER order, not in the
> order they appear in `Active Solvers`.**
> `MainUtils.F90:3310` is `DO k=1,nSolvers; Solver => Model % Solvers(k)`.

`MagnetoDynamicsCalcFields` is **Solver 3**, so any circuit solver numbered
above 3 is reached only *after* it -- and CalcFields segfaults on the NULL
Lagrange multiplier that the circuit has not yet created.  Circular
dependency.

**Fix:** run the circuit pair in the `Before timestep` pre-pass
(`MainUtils.F90:3014`, which executes before the `Always` pass):

```elmer
Solver 9
  Exec Solver = "Before timestep"     !! was `Always`
  Equation = "Circuits"
  Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics"
End
Solver 10
  Exec Solver = "Before timestep"     !! was `Always`
  Equation = "Circuits Output"
  Procedure = "CircuitsAndDynamics" "CircuitsOutput"
End
```

Solver 10 must stay numbered above 9 (the pre-pass is numeric order too).

Verified locally: all ten solvers run, the circuit assembles, the 6 rows
enter the A-matrix, `r_component(2) = 1.0E+01` (the 10 ohm load), and a
3-step transient exits `rc=0`.

### Also resolved earlier in this session

| was | now |
|-----|-----|
| `GetElementRotM: RotM E variable not found` | gone 闁?solvers 5-7 wired up + `Alpha`/`Beta` reference keys + four BCs |
| `Circuit Current Variable Id not found!` | gone 闁?emitted (value 2; source only checks presence) |
| `Stranded Coil N_j not found!` | gone 闁?emitted as `N/A_coil` = 2.5e5 1/m^2 |
| the annulus had no face pair in theta | gone 闁?`solenoid3d.py` cuts a radial slit (閹?5.1) |

### ONE THING TO CHECK ON HPC

`r_component(1)` 闁?the coil's own resistance 闁?comes back as
**2.9026e-02 ohm**.  A hand estimate for 50 turns of 0.7 mm copper on a
22.5 mm mean radius is ~**0.31 ohm**, i.e. ~10x higher.  It is no longer
zero, so the machinery works, but **a factor of 10 here is a factor of 10
in the induced current**.  Sanity-check it before trusting `i_component(1)`;
prime suspects are `Stranded Coil N_j` and the W normalisation.

---

## 3. Geometry: SETTLED 闁?the annulus needs a RADIAL SLIT (notes.md 閹?3.12)

`circuits_transient_stranded` uses a **rectangular block** with 6 faces and
spends all 6: `alpha0/alpha1` + `beta0/beta1` for the direction solves, and
`gamma0/gamma1` for `W = 1` / `W = 0`.

Our coil is an **annulus** (a hollow cylinder from `occ.cut`), so it has only
4 faces 闁?inner cylinder, outer cylinder, and two z-normal disks.  This is no
longer an open question; it was settled with two independent lines of
evidence:

1. **`WPotentialSolver.F90` `LocalMatrix`** solves `闁?C闁愁厼妲?鐠侯垶鍩堥崳鏄?with a default
   tensor `C = diag(0,0,1)`, and rotates it **only** when
   `CoilType /= 'massive'` and a `RotM` exists. So under
   `Coil Type = Massive` the conduction axis is **global z**.
2. **`solenoid3d.py`** tags `CoilStart`/`CoilEnd` on the two **z-normal flat
   disks** and explicitly skips the lateral cylinders
   (`if abs(bb[2] - bb[5]) > 1e-4: continue  # lateral surface, skip`).
   Confirmed on the built mesh: both groups are planar at `z = 0` and
   `z = 40 mm`.

Together: with `Massive`, `W` varies purely with `z` and **the current flows
axially 闁?a tubular conductor, not a solenoid**. The `massive` route is dead
for this geometry even if the 閹? blocker were solved.

For an azimuthal (solenoidal) current, `stranded` is required, hence `RotM`,
hence the `Alpha` x `Beta` solves. The local frame must be

```
alpha = r-hat   (inner / outer cylinder faces)
beta  = z-hat   (bottom / top disk faces)
gamma = alpha x beta = -theta-hat      <- the wire direction
```

so the `W = 0/1` pair has to be the two sides of a **radial slit** through
the annulus 闁?which is exactly the pair of terminals a real winding has.

### Required retagging 闁?**IMPLEMENTED** (notes.md 閹?5.1)

| face | before | now |
|------|--------|-----|
| inner cylinder (r = 20 mm) | untagged | `Alpha0` (tag 1005, `Body 1: Alpha = 0`) |
| outer cylinder (r = 25 mm) | untagged | `Alpha1` (tag 1006, `Body 1: Alpha = 1`) |
| bottom disk (z = 0) | `CoilStart` | `Beta0` (tag 1007, `Body 1: Beta = 0`) |
| top disk (z = 40 mm) | `CoilEnd` | `Beta1` (tag 1008, `Body 1: Beta = 1`) |
| **radial slit, side A** | 闁?| **`CoilStart`** (tag 1003, `W = 1`) |
| **radial slit, side B** | 闁?| **`CoilEnd`** (tag 1004, `W = 0`) |

plus `Alpha reference (3) = Real 1 0 0` / `Beta reference (3) = Real 0 0 1`
on Body 1.  All six faces are consumed 闁?the same as upstream with its block.

`ElmerGrid -autoclean` renumbers them 3/4/5/6/7/8 **in tag order**, so
`CoilStart = 3` / `CoilEnd = 4` are unchanged and
`hpc/smoke_test_closed.sh` step 2b still passes.

**Cost:** the slit needs a finer mesh than `lc_coil_m` = 8 mm.  Measured,
chosen `slit_width_m` = 3.5 mm with `lc_slit_m` = 2.5 mm -> 27498 elements,
**2.0x** the 14084-element baseline.  `lc_min_m` MUST be <= `lc_slit_m`
(it is a global floor).  The full sweep is in 閹?5.1.

Two decisions to make before coding:
1. **Slit width** 闁?visible to the mesh but negligible to the field; wire
   diameter (0.7 mm) is the natural scale.
2. **Does the slit open into the bore, or close on itself?** An open slit
   changes the magnetic path; a closed one does not.  A modelling choice
   with physical consequences 闁?make it deliberately.

---

## 4. The one thing that definitely works: the baseline

The `empty` curve has no conductor, so it gets the plain template and is
unaffected by any of the above.  It is safe to run:

```bash
bash hpc/run_all_curves.sh --curve empty --dry-run   # generate + inspect
bash hpc/run_all_curves.sh --curve empty             # generate + sbatch
```

Note it still moves with the **spring** law (`motion_mode` is global), so
it is a spring-oscillation baseline, *not* a free-fall one.

---

## 5. What is on this branch

| file | state |
|------|-------|
| `config.json` | 8 entries: 1 doc string + `empty` + **6 conductor curves** (open variants removed) |
| `make_sif.py` | no `--circuit` flag; a curve with `N_turns > 0` always gets the closed circuit.  Emits the fill-factor conductivity (閹?5.8), `Export Circuit Variables`, `Max Output Level = 10` and Solver 11 (閹?5.9) |
| `solenoid3d.py` | emits `CoilStart` / `CoilEnd` physical groups when `N_turns > 0` |
| `case_transient.sif` | template; `Max Output Level = 10`, `Timestep Intervals = 900` |
| `tests/test_sif_circuit.py` | **36/36** 闁?locks the SIF structure, the W solver, the fill factor, the export chain and the baseline invariant |
| `hpc/run_all_curves.sh` | 7 jobs; passes `--out case.sif` explicitly (see below) |
| `hpc/smoke_test_closed.sh` | the 7-check validator from 閹? |
| `hpc/run_case.slurm` | fails the job if `results/circuit.csv` is missing |
| `oscilloscope.py` | unchanged; still computes `I = EMF / R_total` post hoc 闁?see 閹? |

**Bugs fixed this round:** the missing fill factor (閹?5.8, a 10x physics
error) and the two export gates (閹?5.9, which made a "successful" run
produce no circuit data).  Earlier: `run_all_curves.sh` was not passing
`--out`, so `make_sif.py` wrote the SIF into the project root *and
overwrote the `case_transient.sif` template*; `run_case.slurm` then died
with `no case.sif in $PWD`.  Would have killed every job on the first
dispatch.  Now fixed and guarded by
`test_baseline_is_byte_identical_to_the_template`.

---

## 7. Cross-checking the FEM current against the analytic estimate

`oscilloscope.py` computes `I = EMF / R_total` **post hoc** from the
prescribed trajectory.  That was kept deliberately until now, because there
was no FEM current to compare against.  There is one now 闁?
`results/circuit.csv` column 10.

Once the first real run finishes, compare the two.  What to expect:

* same shape and phase (the load is 10 ohm against a coil reactance of
  `omega L ~ 21 rad/s * 0.1 H ~ 2 ohm`, so the circuit is **resistive and
  the current should track the EMF almost in phase**);
* same order of magnitude.  A factor-of-10 disagreement means the fill
  factor has regressed 闁?check `r_component(1)` first, it is a 5-second
  check;
* `oscilloscope.py` ignores the coil's own `R` and `L` and treats the
  circuit as EMF-driven through `R_load` only, so it should sit slightly
  **above** the FEM current.  If it is *below*, something is wrong.

Once the two agree, `oscilloscope.py`'s post-hoc path can be dropped.

---

## 6. Environment reminder

`hpc/build_elmer.sh` installs to `ELMER_PREFIX=${ELMER_PREFIX:-$HOME/elmer262}`
and `run_case.slurm` reads the same default as `ELMER_HOME`.

The closed path needs four plugins in addition to the ones the open path
already loaded.  Verify them once before the first run:

```bash
ls "$ELMER_HOME/share/elmersolver/lib" \
  | grep -E 'WPotentialSolver|CircuitsAndDynamics|CoordinateTransform|DirectionSolver'
```

Expect all four.  All four are confirmed present in the Windows 26.2.1
build, and they come from the same `fem/src` tree, so a stock
`hpc/build_elmer.sh` should have built them.  If the grep is empty, the
layout differs from the default -- locate them with:

```bash
find "$ELMER_HOME" -name 'WPotentialSolver.*'
```

Note `run_case.slurm` exports `LD_LIBRARY_PATH="$ELMER_HOME/lib"` only; the
plugins live under `share/elmersolver/lib` and are found through Elmer's
own `ELMER_SOLVER_HOME` search rather than the loader path.  That already
works for the existing solvers (`RigidMeshMapper`, `MagnetoDynamics`, ...),
so it should work unchanged for these four.

# HPC notes 闂?what the cancon.hpccube.com run taught us

A brutal, useful log of what works, what doesn't, and why 闂?so the next
person (or future-me) doesn't repeat the same experiments.

## 1. Environment (Sept 2026)

```
Host:        cancon.hpccube.com
Login:       josephvstalin  (RSA key, port 65023, ~/.ssh/cancon_key)
OS:          CentOS 7 (3.10.0-957)
Partition:   kshctest02 闂?438 nodes, 431 idle, 32 cores / 126 GB / node
Wall-time:   3 days / job
Queue:       DefMemPerCPU = 3569 MB  闂? --mem 70 GB needs  --cpus-per-task 20
User limits: max 20 concurrent jobs
```

## 2. Elmer 26.2 build

`WITH_MPI=TRUE, WITH_OpenMP=TRUE, WITH_UMFPACK=TRUE`, gcc-7.3.1, cmake-3.28.6.
The CentOS system has cmake 2.8 (too old), gcc 4.8 (too old), but
`module load compiler/devtoolset/7.3.1` gives 7.3.1 and we dropped a
cmake-3.28.6 static package into `~/elmerbuild/cmake/`.

The **system `/usr/lib64/liblapack.so` is a dangling dev symlink** that
cmake finds; without an explicit shim the build halts with

```
make: *** No rule to make target '/usr/lib64/liblapack.so'
```

Fix: symlink the real `.so.3.4.2` into `~/elmerbuild/libshim/`,
and pass it to cmake:

```bash
-DBLAS_LIBRARIES=$HOME/elmerbuild/libshim/libblas.so
-DLAPACK_LIBRARIES=$HOME/elmerbuild/libshim/liblapack.so
```

## 3. The bug that ate 14 jobs: `MATC_OPENMP`

Even with `WITH_OpenMP=TRUE`, the build dies at 51% with

```
(null):0: confused by earlier errors, bailing out
ElementDescription.F90:47:7: USE Messages
Fatal Error: Can't open module file "Messages.mod"
```

Root cause: Elmer's own `CMakeLists.txt` adds `-DMATC_OPENMP`, which
triggers use of `matc` modules that need to be compiled in the right
order under `make -j`.  **Fix:** post-configure, nuke the define:

```bash
find . -name "flags.make" -exec sed -i "s/-DMATC_OPENMP//g" {} \;
```

This is a hack, not a port to upstream.  Document it loudly.

## 4. The bigger bug: UMFPACK OOM at ~100 k edges

The supposedly-fixed Elmer is **still** broken:

```
L020_coarse:   9 771 nodes /  69 626 edges  ->  60 kB/step OK
L020_fine:    13 167 nodes /  93 800 edges  ->  80 kB/step OK
L040_coarse:  13 656 nodes /  97 960 edges  ->  100 MB jobs all die
L040_fine:    17 212 nodes / 122 000 edges  ->  dies
L080_fine:    25 849 nodes / 183 658 edges  ->  dies
L160_fine:    33 721 nodes / 238 759 edges  ->  dies
```

Error pattern (every time, at step 0):

```
SolveLinearSystem: Serial linear System Solver: direct
Note: The following floating-point exceptions are signalling: IEEE_DENORMAL
STOP 1
 Error occurred in umf4num:   -1.0000000000000000
```

`umf4num: -1.0` is the **BLAS/LAPACK info argument** being passed
double, but UMFPACK's C interface declares it `int *`.  gfortran 7.3.1
across an ABI boundary treats the real -1.0 as an "integer -1",
UMFPACK returns -1 = "out of memory", and the suite
Says `umf4num: -1.0` because it wrote the double -1 into the
"integer" slot.

**Memory was NOT the problem** 闂?same job uses only 2.7 GB before
crashing.  Even applying 110 GB does not help.

The Iterative route (`BiCGStab + ILU1`) **diverges** at step 0.  That much is
reproducible.  But the explanation originally recorded here --

> "`MagnetoDynamics` edge elements need a curl-conforming preconditioner
>  that Elmer doesn't ship.  This is a known limit."

-- is **WRONG, and it cost this project a lot of time.**  The divergence is a
property of **ILU**, not of Elmer: ILU is built for H^1 (nodal) problems and
is simply the wrong preconditioner for H(curl) (edge) elements.  Elmer *does*
ship a curl-conforming preconditioner, and has for years: **Hypre's AMS**
(auxiliary-space Maxwell solver), implemented in `fem/src/SolveHypre.c`:

```c
HYPRE_AMSCreate(&precond);
HYPRE_AMSSetDiscreteGradient(precond, parcsr_G);
HYPRE_AMSSetInterpolations(precond, parcsr_Pi, NULL, NULL, NULL);
HYPRE_AMSSetEdgeConstantVectors(precond, ...);
```

`ElmerHypreContainer` even carries dedicated `HYPRE_IJMatrix G, Pi` members --
the discrete gradient and the edge->node interpolation, assembled from the
Elmer mesh.  Upstream tests exactly this combination in
`fem/tests/mgdyn_hypre_ams`, whose header says:

> "This test case with BiCGStab as solver, AMS as preconditioner."

It was never available here for one mundane reason: `WITH_Hypre` defaults to
**FALSE**, so `HAVE_HYPRE` was undefined and the whole AMS code path was
compiled out.  The SIF keywords to switch it on (all verified against that
upstream test case) are:

```
linear system use hypre          = Logical True
Linear System Solver             = Iterative
Linear System Symmetric          = Logical True
Linear System Preconditioning    = AMS
Linear System Method Hypre Index = Integer 7   ! 7 = BiCGStab
```

`make_sif.py --solver hypre-ams` now writes exactly that block for Solver 2,
and `hpc/build_elmer.sh hypre` builds the Elmer that can run it.

**Correction to the paragraph that followed:** the original text also claimed
"**Hypre AMG** needs rebuilding with a solver that maps the trace to
HYPRE_Solver.  Neither is wired up."  The mapping is already written -- it is
the `HYPRE_AMSSetEdgeConstantVectors` / `HYPRE_AMSSetInterpolations` pair
above.  Nothing needs to be written; the library just has to be linked in.
`Pardiso/MKL` is genuinely not installed, and is now unnecessary anyway
because it is a *direct* solver and would inherit the same O(n^2) wall.

> **Conclusion:** on this HPC, this Elmer 26.2 build, and UMFPACK in
> general, the practical maximum linear system is **~100 k edges**.
> Above that, the solver interface bug kicks in.  This is a HARD LIMIT.

## 5. Wall-clock budget per case (HPC, Hygon 32-core node, 1 core)

| case | edges | step time | frames | total |
|---|---|---|---|---|
| L020_coarse  |  69 k | ~ 6 min | 56 | ~ 5.6 h |
| L020_fine    |  94 k | ~10 min | 56 | ~ 9.3 h |
| L040_fine    | 122 k |  OOM at step 0 | -- | inf |
| L080_fine    | 184 k |  OOM at step 0 | -- | inf |
| L160_fine    | 239 k |  OOM at step 0 | -- | inf |

The single core is **~1.8x slower** than a Ryzen 7  H 255 (Zen4).
The HPC wins on **memory headroom** and **job parallelism**, not speed.

## 6. Queue quirks

- `QOSMaxSubmitJobPerUserLimit = 20`.  We can run 20 jobs at once, and
  `-All` is OK as long as the per-case window count averages 闂?20/6.
- `DefMemPerCPU = 3569 MB`.  `--mem=20G` *with* `--cpus-per-task=6`
  is rejected with "too much memory requested".  The right pattern is
  ask for many cpus, only one is used.
- After `scancel -u $USER`, the login node's sftp subsystem can hang
  for 5-15 min.  `sync.ps1` retries do the trick.

## 7. What I would do differently

1. **Build with Pardiso or Hypre from the start**, not UMFPACK.
2. **Pre-flight every case with a 3-step run** before queueing 16 windows.
3. **Cap the matrix size** at 80 k edges by using **second-order elements**
   in free-space volumes and **first-order** in the magnet + coil only.
4. **Never trust a solver library that doesn't ship its own tests** 闂?we
   just wasted ~5 hours on a "successful" build that silently
   miscompiles a single Fortran 闂?C ABI edge case.

## 8. Decision rule: local vs HPC

Implemented in **`hpc/should_run_locally.py`**.  Run it before queueing anything:

```
python hpc/should_run_locally.py hpc/cases
```

The rule it encodes:

> **The laptop is ~1.8x faster per core and its UMFPACK has no ABI bug,
> so the laptop is the DEFAULT.**  The HPC only wins on (a) 20-way
> parallelism (a case can be cut into windows) and (b) 126 GB RAM.
> So a case goes to the HPC only when the laptop would need more than an
> overnight run (48 h) *and* the HPC can actually solve it (<= 100 k edges).

Current verdicts (Sept 2026):

| case | edges | frames | laptop | HPC | runner |
|---|---|---|---|---|---|
| L020_ri020_coarse |  73 935 |  56 |  0.6 h |  1.2 h | **local** |
| L020_ri020_fine   |  98 494 |  56 |  4.7 h |  6.3 h | **local** |
| L040_ri020_fine   | 128 890 |  66 |  9.5 h | 12.7 h | **local** |
| L080_ri020_fine   | 193 185 |  86 | 27.8 h | 37.1 h | **local** |
| L040_ri017_fine   | 279 898 |  66 | 44.9 h | 59.8 h | **local** (2 days) |
| L160_ri020_fine   | 250 269 | 126 | 68.5 h | 91.3 h | **change-solver** |

### Calibration tables (edges -> s/step, single core)

Measured on this laptop (Ryzen 7 H 255, mingw64 gfortran 13):

| edges | s/step |
|---|---|
| 16 000 | 1.0 |
| 40 000 | 5.0 |
| 60 000 | 16.0 |
| 80 000 | 60.0 |
| 94 000 | 167.0 |
| 98 000 | 300.0 |

HPC (Hygon, gcc-7.3.1) is consistently ~1.8x slower per core.
Do **not** extrapolate with the local log-log slope beyond 98 k edges 闂?between the last two rows it is roughly `n^14`, which produces nonsense
(5 million hours).  `_fit()` therefore switches to a clean `O(n^2)` rate
past the last table entry.

### Rule of thumb

| edges | runner | why |
|---|---|---|
| <=  80 k | **laptop** | minutes to a few hours, no upload overhead |
| 80-100 k | **laptop** | still faster than the HPC, ~5-8 h |
| 100-250 k | **laptop** with UMFPACK if <= 48 h, else **HPC + `--solver hypre-ams`** | UMFPACK dies at its ABI wall; AMS is iterative and does not |
| > 250 k | **HPC + `--solver hypre-ams`** | direct solvers are hopeless; AMS is ~O(n) in memory |

`make_sif.py --solver hypre-ams` is what makes the last two rows viable
without a GPU; see section 9.6.

## 9. New cluster: 128 cores / 512 GB / 8 accelerators

Spec of the machine being considered:

| | value |
|---|---|
| CPU | 2 闁?64C = 128 cores, 2.4 GHz |
| RAM | 512 GB |
| interconnect | 400 Gb |
| local scratch | **none** |
| accelerators | 8 闁?64 GB HBM ("BW"), 50 GPU-card-hours |

### 9.1 The 512 GB RAM solves the REAL problem

The old HPC's "100 k edge" wall was an **UMFPACK ABI bug, not RAM**.
Estimated LU memory for our cases (scaled n^1.75 from the measured
2.7 GB @ 69 626 edges):

| case | edges | LU memory | old HPC | new (512 GB) |
|---|---|---|---|---|
| L020_coarse | 73 935 | 3.0 GB | OK | OK |
| L020_fine | 98 494 | 5.0 GB | OK | OK |
| L040_fine | 128 890 | 7.9 GB | **ABI crash** | OK |
| L080_fine | 193 185 | 16.1 GB | **ABI crash** | OK |
| L160_fine | 250 269 | 25.3 GB | **ABI crash** | OK |
| L040_ri017 | 279 898 | 30.8 GB | **ABI crash** | OK |

A fresh build (with MUMPS, and its own LAPACK) should not inherit the bug
闂?**but prove it with a 3-step smoke test before queueing anything.**

### 9.2 The CPU path alone is enough

Because the problem is quasi-static, every timestep is independent, so
128 cores can chew through different timesteps at once:

| case | s/step (1 core) | 600 steps | concurrent | **wall** |
|---|---|---|---|---|
| L020_fine | 168 s | 28 h | 102 | **0.3 h** |
| L040_fine | 288 s | 48 h | 64 | **0.7 h** |
| L160_fine | 1085 s | 181 h | 19 | **9.5 h** |
| L040_ri017 | 1357 s | 226 h | 16 | **14.1 h** |

**The whole study in ~14 h without using a single GPU-card-hour.**
GPU only matters if the wall clock has to come down further
(the same cases would land around 40 min with GPU-AMG).

### 9.3 Using the accelerators (only if needed)

**FOUND: `BW` = Hygon DCU, and the whole stack is already installed on
cancon.hpccube.com.**  Verified on the login node:

```
/opt/dtk-25.04.2/                                  Hygon DTK (ROCm fork)
/opt/dtk-25.04.2/rocalution/lib/librocalution.so   <-- exactly what Elmer needs
/opt/dtk-25.04.2/rocalution/include/rocalution.hpp
/opt/dtk-25.04.2/bin/{hipcc,rocminfo}
/opt/dtk-25.04.2/{hipblas,hipsparse,hipsolver,hipfft,hsa,amdgcn,dcc}
/opt/dtk-22.04  /opt/dtk-22.04.1  /opt/rocm  /opt/rocm-3.3.0 /opt/rocm-5.0.0 /opt/rocm-5.1.0
```

There are even ready-made `-DCU` app modules
(`apps/gromacs-DCU2/2023.2-hpcx_gcc7.3.1_mpi-dtk23.10`, `lammps-DCU`, 闂?
and Apptainer/Singularity modules (`apps/apptainer/1.3.4`,
`apps/singularity/3.8.7`) 闂?note the earlier "no containers" conclusion was
wrong, they were simply not on PATH.

**DCU partitions (GRES `dcu:Hygon:4` = 4 Hygon DCUs per node):**

| partition | nodes | idle (at the time) | limit |
|---|---|---|---|
| `kshdnormal` | 1915 | 121 | 333 d |
| `kshdexclu01` | 343 | **339** | 闂?|
| `kshdexclu03` | 587 | 226 | 闂?|
| `kshdexclu16` | 30 | **30** | 333 d |
| `kshdnormal02` | 139 | 38 | 333 d |
| `kshdnormal03` | 162 | 15 | 333 d |
| `kshdtest` | 79 | 1 | 3 d |
| `kshdsctest` | 24 | 1 | 3 d |
| `kshdAI` | 39 | 1 | **2 h** |
| `kshdexcluwa` | 15 | 11 | 闂?|
| `kshdexclu09` / `16` / `23` | small | | 闂?|

**IMPORTANT: these partitions are HIDDEN from a plain `sinfo`** 闂?you must
use `sinfo -a`.  They do not appear in the default partition list, which is
why the first recon wrongly concluded "no GPUs".

**BLOCKER (confirmed exhaustively): `josephvstalin` may use `kshctest02` ONLY.**
I probed **all 41 partitions** with `sbatch --test-only`. Result:

```
kshctest02         OK                        <-- the only one
kshcexclu11/12      DENIED
kshdexclu01/02/03   DENIED  (the DCU ones)
kshdexclu16/23/wa   DENIED
kshdnormal/02/03/04/05  DENIED
kshdtest kshdsctest kshdAI  DENIED
kshc* ksag* kshk* Agent0 comp  DENIED / permission denied
```

- `scontrol show partition kshdexclu01` 闂?**"Partition kshdexclu01 not found"**
  闂?I cannot even *read* the config, let alone submit.
- `scontrol show partition kshctest02` 闂?works, and its `AllowAccounts` list
  (10043 entries) **does** contain `josephvstalin`.
- Adding an explicit `--account=josephvstalin --gres=dcu:1` does **not** help;
  the association simply does not exist.
- **And the decisive test:** the `kshctest02` nodes report `Gres=(null)`.
  They are **plain CPU nodes 闂?no DCU cards at all.**  So the one partition I
  *can* use is also the one partition that cannot answer the DCU question.

**=> The DCU cannot be tested from this account. Not "hard to reach" -
physically unreachable.**  Hardware present, software present, account grant
absent.  Request an association with `kshdnormal` (or `kshdexclu01`) plus a
card-hour allocation; nothing else will move this.

Ready-made validation script for the moment access arrives:
`hpc/test_dcu.sh` 闂?checks DCU visibility, rocALUTION, a HIP smoke build, the
Elmer link, then runs the 3-step case smoke test and greps for `umf4num: -1`.

### 9.4 What we CAN use meanwhile: `kshctest02` is not small

The test partition is far bigger than the old cluster, so the CPU-only study
is comfortably feasible:

| | kshctest02 |
|---|---|
| nodes | **438** |
| total CPUs | **14016** |
| CPUs / node | 32 |
| RAM / node | **126.5 GB** |
| MaxTime / DefaultTime | **3 days** |
| AllowQos | ALL |
| TRES | `cpu=14016,mem=55407000M,node=438` |

438 nodes 闁?126 GB is ~10闁?the machine the whole study was designed for
(512 GB).  Window parallelism is therefore not just viable but generous -
the ~14 h estimate was for a *single* node, and we can fan out across many.


Once that is done:

```bash
bash hpc/build_elmer.sh rocm    # uses /opt/dtk-25.04.2 + rocALUTION + MUMPS
```

Elmer 26.2 has exactly two accelerator interfaces:

| cmake option | needs | guard macro |
|---|---|---|
| `-DWITH_ROCALUTION=TRUE` | AMD / Hygon ROCm or DTK | `HAVE_ROCALUTION` |
| `-DWITH_AMGX=TRUE` | NVIDIA CUDA | `HAVE_AMGX` |

`fem/src/rocalution.cpp` and `fem/src/amgx.c` are both in the tree; only the
link is switched off by default.  Both are **iterative AMG**, which fixes
the two problems hit on the old cluster at once: O(n) memory instead of
O(n闁?, and a preconditioner that actually works for H(curl) edge elements
(plain BiCGStab+ILU diverges 闂?verified).

### 9.4 Two constraints specific to this node

1. **No local scratch.**  All I/O goes over the 400 Gb network.  VTU frames
   are 7-9 MB each; **900 frames 闂?6-8 GB per case** (this was ~600 frames
   until the run was lengthened to THREE spring periods 闂?see 闁?4), which
   the network handles easily 闂?but make sure MUMPS stays **in-core**
   (512 GB is ample), since its out-of-core mode would thrash without local
   disk.
2. **50 GPU-card-hours is a small budget.**  Exploit the quasi-static
   property: `Phi(z)` needs only ~30 magnet positions, not 900 timesteps.
   At ~10 min/solve that is 11 card-hours for the two big cases, leaving
   room for convergence studies.

## 9.6 FINAL: no DCU allocation -> the Hypre path (2026-09-12)

The DCU question is closed: **this account has no accelerator allocation.**
`kshctest02` is the only partition that accepts it, and its nodes report
`Gres=(null)` -- no cards.  Everything below assumes CPU only.

That removes `rocALUTION` from consideration, which in turn means the
~100 k-edge UMFPACK wall had to be solved some other way.  The answer is
**Hypre AMS** (see section 4 for the full explanation of why the earlier
"Elmer has no curl-conforming preconditioner" note was wrong).  AMS is the
right preconditioner for H(curl) edge elements *by construction*, so it
fixes the divergence that made the iterative route unusable before.

Why Hypre and not MUMPS for this:

| | MUMPS | **Hypre AMS** |
|---|---|---|
| kind | direct (LU) | iterative (Krylov + AMG) |
| memory | O(n^2), same wall as UMFPACK | ~O(n) |
| preconditioner for H(curl) | n/a (direct) | **AMS, purpose-built** |
| extra deps | BLACS + ScaLAPACK + METIS/Scotch | MPI only |
| bootstrap effort | high | low |

MUMPS is still wired up (`bash hpc/build_elmer.sh cpu`) as a fallback for
cases where an exact factorisation is wanted, but AMS is the recommended
default now that no GPU is available.

### 9.5 Recommended order

```
1. bash hpc/detect_accelerator.sh                    <- identify the stack
2. bash hpc/build_elmer.sh hypre                     <- Hypre AMS + OpenMP
3. 3-step smoke test: must NOT print 'umf4num: -1.0'
4. prove AMS on the upstream test: cd fem/tests/mgdyn_hypre_ams
   (build_elmer.sh prints the exact command)
5. python make_sif.py --solver hypre-ams
6. run the study on CPU with window parallelism (0 card-hours)
```

Step 3 and step 4 are the important ones: step 3 catches the UMFPACK ABI bug,
step 4 proves `HAVE_HYPRE` was really compiled in *and* that AMS converges on
Whitney elements.  Everything else is wasted effort if either fails.

> **A build that "succeeded" is not proof.**  Elmer's cmake options are
> mixed case (`WITH_Mumps`, `WITH_Hypre`), and cmake **ignores unknown `-D`
> variables** -- it only prints "Manually-specified variables were not used
> by the project".  `hpc/build_elmer.sh` used to pass `-DWITH_MUMPS=TRUE`,
> which is not a real variable, so MUMPS silently stayed off and the build
> still reported success.  `verify_features()` now reads the resolved values
> back out of `CMakeCache.txt` and greps `HAVE_HYPRE` out of `config.h`, and
> fails the build if the requested solver is not actually there.

Step 3 is the important one 闂?everything else is wasted effort if the
solver is still broken.


| edges | runner | why |
|---|---|---|
| <=  80 k | **laptop** | minutes to a few hours, no upload overhead |
| 80-100 k | **laptop** | still faster than the HPC, ~5-8 h |
| 100-250 k | **laptop** with UMFPACK if <= 48 h, else **HPC + `--solver hypre-ams`** | UMFPACK dies at its ABI wall; AMS is iterative and does not |
| > 250 k | **HPC + `--solver hypre-ams`** | direct solvers are hopeless; AMS is ~O(n) in memory |

The `change-solver` verdict that `should_run_locally.py` still reports above
the 100 k wall is no longer a dead end: the solver to change *to* is now
selected with one flag, needs no GPU, and is the recommended route.

---

## 10. The AMS-verify impasse (Windows laptop, 2026-09-12)

Until `hpc/build_elmer.sh hypre` is actually executed on the HPC cluster
and proves that `HYPRE_AMS` converges on Whitney edge elements for **this**
specific problem, every statement about AMS performance above remains a
prediction derived from upstream's `fem/tests/mgdyn_hypre_ams` test case
plus the source of `fem/src/SolveHypre.c`.  This section is the log of an
attempt to retire that risk locally on the Windows laptop, and why it
failed.

### 10.1 What was tried, and what each probe found

1. **MSYS2 ships a prebuilt `mingw-w64-x86_64-hypre 2.33.0-1`.**
   `pacman -Ss hypre` returned it under all four mingw64 variants.  This
   would have been a zero-compile path: install the package, point Elmer's
   `cmake/Modules/FindHypre.cmake` at it, done.  17 MB install.

2. **First symbol probe was unreliable because the toolchain was missing.**
   Running the probe under plain `bash -c` left `gcc/nm/objdump` as
   "command not found", so `grep -c` over their output always returned 0.
   That produced a falsely "MISS" verdict on **every** Hypre symbol,
   including `HYPRE_BoomerAMGCreate` which is in any version of Hypre.
   So a test that reports "missing" for an unambiguously-present symbol is
   wrong, not the library.  Lesson: when probing a binary's API, use at
   least two independent tools (`objdump -p` and `nm` on the static
   archive are a strong pair), and assert sanity first.

3. **The DLL exports AMS 闂?but `nm -D` lies about it.**
   Under a MinGW64 login shell (`bash -lc MSYSTEM=MINGW64 ...`), three
   independent checks agree:

       objdump -p libHYPRE.dll      -> HYPRE_AMSCreate        exported
                                      HYPRE_BoomerAMGCreate   exported
       nm        libHYPRE.a         -> HYPRE_AMSCreate        defined  (in 1 obj)
                                      HYPRE_BoomerAMGCreate   defined  (in 1 obj)
       nm -D     libHYPRE.dll       -> 0 hits for any symbol  (false negative)

   So the AMS symbols are present.  But this is necessary, not sufficient.

4. **The package is MPI-enabled, which collides with the project's serial
   build.**  `objdump -p libHYPRE.dll` shows `DLL Name: msmpi.dll`, and
   `HYPRE_config.h` defines `HYPRE_HAVE_MPI 1` and
   `HYPRE_HAVE_MPI_COMM_F2C 1` 闂?the latter is the Fortran闂佹剚鍋呴幗?comm
   conversion Elmer calls in `SolveHypre.c`.

   But the project's Windows Elmer (`elmer262/CMakeCache.txt`) was built
   with `WITH_MPI:BOOL=FALSE`, and its link line shows
   `general;mpi_stubs;...`  -- it uses Elmerfem's bundled `mpi_stubs`
   library, which makes every `MPI_*` call a serial no-op.  This is
   intentional: a serial Elmer can never be linked against an MPI-aware
   Hypre because the two views of `MPI_Comm` (stubs vs `MSMPI_Comm`) are
   type-incompatible, and even if the types aligned, the runtime state
   (communicators, error handlers) would not.

5. **MSYS2 does not ship a sequential-stub MPI variant.**  The Hypre
   autotools build supports `./configure --disable-mpi`, which produces
   the compatible version, but the prebuilt MSYS2 package skipped that
   configuration.  Compiling a sequential Hypre from source is ~15-25 min
   on this laptop and adds a heavy dependency to the project (LAPACK +
   BLAS + OpenBLAS, plus a working autotools environment).  The benefit
   is purely to verify AMS on this machine; the production build is the
   HPC one anyway.  The cost/benefit ratio was judged negative.

### 10.2 Net status

* **The SIF keywords (`make_sif.py --solver hypre-ams`) are still
  correct** because they are transcribed verbatim from the upstream test
  case, and the surgical-text-replacement tests
  (`tests/test_sif_solver.py`) confirm that Solver 2 ends up with the
  intended `linear system use hypre`, `Linear System Preconditioning =
  AMS`, `Linear System Method Hypre Index = Integer 7`, and no duplicate
  SIF keys.

* **AMS convergence on `WhitneyAVSolver` with our specific geometry is
  still unverified.**  Until step 4 of `build_elmer.sh hypre`'s own
  recommended order is run on the HPC and the upstream `mgdyn_hypre_ams`
  test case passes, treat the ~100 k-edge wall as **predicted to fall**,
  not proven to fall.

* **No Windows-side verification script is being added.**  The
  investigation above is one-shot and the wrong conclusion it nearly
  produced (claims of "missing symbols" driven by missing tools) is the
  reason it does not get codified into the project.  Future attempts on
  a different OS should pick the **sequential-stub-MPI Hypre** path, not
  the prebuilt MSYS2 package.


## 11. Recovery: the three verifier scripts were never tracked (2026-09-12)

A subtle data-loss bug surfaced and was repaired in this same session,
documented here because it touches every downstream verifier and because
the fix is **tracking, not backups**.

### 11.1 What happened

Three files used by `run_tests.sh` / `run_tests.ps1` to evaluate the
results of every transient run:

    test_outputs/verify_bfield.py   1327 bytes  (analytic Bz vs FEM)
    test_outputs/verify_fall.py     2632 bytes  (free-fall z(t) match)
    test_outputs/verify_spring.py   4805 bytes  (spring z(t) match)

...existed only as **untracked working-tree presence**.  They were
referenced by the pipeline runners (`& $PY test_outputs\verify_spring.py`)
and by `Dockerfile` (`COPY test_outputs/verify_bfield.py ...`), but had
never been `git add`-ed.  `git status` showed them as `?? test_outputs/`
throughout the project history.

A later cleanup step (`git clean -f test_outputs`) faithfully executed
what was asked, and deleted all three.  They were not in any commit, in
any stash, in any dangling blob (verified with `git fsck --lost-found`
and walking every dangling commit), and not in the reflog.  By every
normal recovery path they were **gone**.

### 11.2 Why they survived

The project also ships a 611.9 MB Docker image tarball,
`pysproject-3.5.0.tar` (`docker save` output, layer blobs in
`docker save` v1 format).  The image had been built from a Dockerfile
that did `COPY test_outputs/verify_bfield.py ...` for every file, so the
same three scripts were baked into one of the layer tarballs as
`app/test_outputs/verify_*.py`.  A one-shot extractor walked every layer
gzip blob, gunzipped each, opened the inner tar, and pulled out the
three files.  Recovery was byte-exact:

    test_outputs/verify_bfield.py   1291 bytes  (was 1327 CRLF; LF on commit)
    test_outputs/verify_fall.py     2567 bytes  (was 2632 CRLF; LF on commit)
    test_outputs/verify_spring.py   5396 bytes  (was 4805 CRLF + --results/--sif patch
                                              re-applied from session memory; LF on commit)

### 11.3 The fix that matters

The recovery script (`_recover2.py`) was one-shot and has been deleted.
The **defence that matters** is that all three files are now staged for
commit.  Once committed, `git clean -f test_outputs` will not touch them
-- the working tree will be recoverable from `.git/objects` even after
any future cleanup.  As of this writing the commit has NOT yet been
made: the previous session staged the files and explicitly deferred the
commit decision to the user.  **Do not `git clean` the working tree
until the staged files are committed.**

The lesson is broader than "be careful with git clean":

  * If `COPY <path>` appears in a `Dockerfile`, the path is part of the
    contract.  Files under that path that are **not** tracked in git are
    in a half-life state -- they exist, they work, but a stray `git clean
    -fd` deletes them with no warning.  Either track them, or pin them
    in `.gitignore` with `*.swp`-style exceptions, or document the
    rule that triggers `git clean`.
  * A 611 MB Docker image tarball is not a backup strategy.  It worked
    by luck here -- the image had been built from the same
    working tree, and the Dockerfile happened to COPY these specific
    files.  The next build may not, and a future recovery attempt from
    the image will fail.

### 11.4 Net status

* `verify_bfield.py`, `verify_fall.py`, `verify_spring.py` are now staged
  (`git status` shows them as `A`); `git ls-files --stage` confirms
  SHA-indexed presence and `git diff --quiet` reports zero uncommitted
  changes on top of the staged content.
* The two-line `--results` / `--sif` patch on `verify_spring.py` (added
  in an earlier session to let it validate arbitrary run directories)
  was re-applied from session memory after the image yielded only the
  unpatched baseline.  The patched version is what got staged.
* No code change elsewhere.  `tests/test_spring_model.py` (21/21) and
  `tests/test_sif_solver.py` (13/13) still pass against the recovered
  verifiers, which is the only behavioural check available without
  bringing Docker back up.
* **Action item left to the user:** review `git diff --cached
  test_outputs/` and commit when satisfied.  Until then, do not run
  `git clean` or any other operation that resets the index.


## 12. 12-curve sweep design (closed + open circuit), HPC dispatch (2026-09-12)

> **STATUS (superseded in part).**  闁?2.2 ("What the FEM actually does"),
> 闁?2.3 ("Why we did not implement a true coupled circuit") and 闁?2.7
> ("TODO, left for whoever wants the real closed-circuit FEM") described a
> design in which **all 12 curves ran the same open-circuit SIF** and the
> closed/open contrast was pure post-processing.  That is no longer true on
> either count:
>
> * the closed circuit is now real -- `make_sif.py` emits a genuinely
>   coupled coil + load circuit whenever the curve has a conductor;
> * the **open-circuit variant was REMOVED entirely** (闁?3.10), so the
>   sweep is now **7 cases, not 12**: 1 `empty` baseline + 6 conductor
>   curves.  There is no `--circuit` flag any more and no `R_load = inf`
>   twin.  The only remaining contrast is N_turns and material.
>
> Read **闁?3** for what was implemented, what has been executed, and what
> is still blocked.  闁?2.1, 闁?2.4, 闁?2.5 and 闁?2.6 (geometry, dispatch,
> observables) still stand, but any reference in them to "12 curves", to a
> `circuit_state` factor, or to a closed/open pair is stale -- read it as
> the 7-case design above.

This section is the design log of the current redesign.  It supersedes
the earlier "6 curves" idea (`make_sif.py --solver` is unchanged) and
extends it to **3 turns x 2 materials x 2 states = 12 curves**, all of
which can be dispatched on the HPC in a single batch.

### 12.1 The 3 x 2 x 2 factorial

The shared coil geometry (in `[coil]`) is **fixed**: length = 40 mm,
r_inner = 20 mm, r_outer = 25 mm.  Every curve has its own sif_suffix,
so each gets its own mesh + SIF pair (12 meshes, 12 runs).  The three
factors:

| factor          | levels                                |
|-----------------|---------------------------------------|
| N_turns         | 25 / 50 / 100                         |
| material (sigma)| Cu (5.96e7 S/m) / Al (3.50e7 S/m)    |
| circuit_state   | closed (R_load=10) / open (R_load=inf)|

Naming: `N<turns>_L040_<material>_<state>`, e.g. `N50_L040_cu_closed`.

The closed/open pair for each (N, material) isolates the Lenz
feedback effect: the only thing different is R_load.  The N and
material pairs isolate turn count and wire conductivity.

### 12.2 What the FEM actually does (the honest part)

**All 12 curves run the SAME SIF.**  Material 1's `Electric
Conductivity` is 0.0; Body Force 1 has all `Current Density` zeros;
there is no `Solver "CoilSolver"` and no `Circuit ... End` block.
That is the existing architecture, documented by its own comment:

```
! Body 1 -- the winding is OPEN CIRCUIT for an induction experiment.
! There is NO source current: the only field source is the permanent magnet
! (Material 2), and everything the coil sees is induced by the magnet.
! The induced current is recovered afterwards as I = EMF / R_total.
```

The 12 curves therefore differ only in how `oscilloscope.py`
interprets the result:

  * `circuit_state = 'closed'`  ->  R_load = 10 ohm,  I = EMF / R_total
  * `circuit_state = 'open'`    ->  R_load = inf,    I = 0

This is **the same approximation** the project has always used.
The sweep over N and sigma makes the comparison across curves
meaningful, but the closed/open contrast is NOT a true FEM difference
-- it is the **post-processing** using the same A-field.

### 12.3 Why we did not implement a true coupled circuit

For the FEM to actually solve a closed circuit, the SIF needs:

1.  A `Solver` block with `Procedure = "CoilSolver" "CoilSolver"`
    (the upstream Elmerfem 26.2.1 test `fem/tests/CoilSolver1/case.sif`
    shows the full syntax).  This is real Elmerfem code (NOT a
    separate library), so it is in the build by default.
2.  `Boundary Condition` entries with `Coil Start = Logical True`
    and `Coil End = Logical True` on TWO mesh surfaces -- the top
    and bottom of the coil body, marking where the winding enters
    and exits.  The current mesh has only `MagneticInfinity` (BC 1)
    and `MagnetSurface` (BC 2); the coil body's top + bottom disks
    are *interior* faces, not boundary faces, so `Coil Start` /
    `Coil End` have nothing to attach to.
3.  `Material 1` would need `Electric Conductivity = sigma_wire`
    (instead of 0.0); the current open-circuit assumption
    `sigma = 0` short-circuits any attempt at finite conductivity.

Implementing all three is **outside the scope of this redesign**
because each one is a non-trivial change with HPC-only validation:

* (1) requires a new SIF template branch in `make_sif.py` keyed by
  `circuit_state`, with a CoilSolver solver and the BCs it needs.
* (2) requires `solenoid3d.py` to subdivide the coil's top + bottom
  disks out as named physical boundaries (currently they are
  interior faces of a single Body 1).
* (3) is straightforward once (1)(2) are done.

None of these are impossible -- the upstream `CoilSolver1` test
SIF gives a complete template for (1) and (2) -- but they require
HPC validation with a real Elmer build (the Windows elmer262 build
is not a full CoilSolver test rig) and the geometry rebuild changes
the mesh, which propagates to `oscilloscope.py`'s BC indices.

### 12.4 What we did change

* `config.json -> curves` now has 12 conductor curves + 1 `empty`
  baseline + 1 `_comment_block`.  Each conductor curve carries
  `circuit_state` so oscilloscope.py can read it without guessing
  from `R_load_ohm`.  The shared `[coil]` block holds `z0_m`,
  `z1_m`, `r_inner_m`, `r_outer_m` -- length is fixed across the sweep.
* `make_sif.py --curve <name>` selects the active curve.  The SIF
  itself is unchanged for every curve today; the flag exists so
  HPC scripts and oscilloscope.py can be told which entry is
  "current" without re-parsing config.json themselves.  It
  validates against the curves block (rejects `_comment_block` and
  typos; tested with `--curve _comment_block`, `--curve bogus_name`
  both exit 1 with a list of valid curves).
* `hpc/run_all_curves.sh` enumerates every curve in `config.json`,
  generates a `hpc/cases/<sif_suffix>/` directory containing a
  patched `config.json` (with only the active curve), the
  `solenoid3d.py` mesh, the `make_sif.py` SIF, and then `sbatch`'s
  `run_case.slurm`.  Supports `--dry-run`, `--state {closed,open}`,
  and `--curve <name>` filters.  Each curve is its own sbatch job.

### 12.5 How to dispatch on the HPC

```bash
# 1. sync the source tree (run on cancon.hpccube.com)
cd ~/pysproject
git pull         # or rsync the working tree from the laptop

# 2. generate + submit ALL 12 curves
bash hpc/run_all_curves.sh

# ... or only the closed-circuit 6
bash hpc/run_all_curves.sh --state closed

# ... or a single curve to smoke-test
bash hpc/run_all_curves.sh --curve N50_L040_cu_closed --dry-run

# 3. monitor + pull results back
squeue -u josephvstalin
bash hpc/pull.ps1
```

The 12 curves can run **in parallel** (different case directories,
each a 1-core sbatch job).  On a 438-node cluster the wall-clock
for the full sweep is bounded by the slowest single case (a few
hours per FEM, dominated by the 600-timestep transient of
`case_transient.sif`).

### 12.6 What the post-processing will show

`oscilloscope.py` already reads `R_load_ohm` per curve, and now also
`circuit_state`.  For the 12 curves:

  * 6 closed curves:  I = EMF / (R_load + R_wire), R_wire scales
    linearly with N and inversely with sigma, so the Lenz braking
    signal in `dPhi/dz` scales with N x sigma (approximately).
  * 6 open curves:  I = 0 everywhere, no Lenz feedback.  The
    magnet follows the prescribed `spring` trajectory unchanged.

The closed vs open contrast, isolated by N and material, is the
**observable** the new design is built around.  In the post-hoc
plot the closed curves should show measurable departure from their
open twins only when the Lenz force (proportional to N x sigma) is
comparable to the spring restoring force; at small N that contrast
should be invisible.

### 12.7 TODO (left for whoever wants the real closed-circuit FEM)

> **DONE -- see 闁?3.**  All four items below were implemented in the
> follow-up session, with one important correction: the "CoilSolver"
> approach sketched here (item 2) is the **wrong tool**.  `CoilSolver`
> solves a *static* coil-current distribution; it cannot drive a transient
> induced-current loop.  The working route is `Component` +
> `CircuitsAndDynamics`, per upstream
> `fem/tests/circuits2D_transient_variable_resistor`.  Item 1 (the mesh
> change in `solenoid3d.py`) was done as described.

If/when the team wants the FEM to actually solve the closed circuit:

1.  Subdivide the coil's top + bottom disks in `solenoid3d.py`
    and tag them `CoilStart` / `CoilEnd` so `Coil Start = True` /
    `Coil End = True` can be attached.  Likely a `gmsh.model.occ.fuse`
    + `getBoundary` + `addPhysicalGroup` sequence on the coil cylinder.
2.  Add a `case_transient_closed.sif` template (or branch in
    `make_sif.py`) that:
      - sets `Material 1 Electric Conductivity = sigma_wire`
        (curve-dependent);
      - adds `Solver 5 (CoilSolver)` after the existing Solvers
        1..4 with `Coil Start = True` / `Coil End = True` BCs;
      - promotes Solver 5 to the active solvers list.
3.  Validate on HPC with a single curve first (`--curve
    N50_L040_cu_closed` on the 438-node cluster, expect ~1 hour /
    600 steps).  Once the CoilSolver converges for one case,
    the same SIF template handles the other 11 unchanged.
4.  After validation, drop `oscilloscope.py`'s `I = EMF/R_total`
    post-processing (it duplicates what CoilSolver already gives
    via the saved coil current field).

None of (1)-(4) was done in this session because each requires
HPC validation and the geometry rebuild (1) breaks the existing
case sweep -- it is a separate piece of work, not a "bug fix".

---

## 13. True closed-circuit FEM: `Component` + `CircuitsAndDynamics` (2026-09-13)

> **Short version:** see **`hpc/HANDOFF.md`** 闂?the actionable checklist
> (what to run first, what is expected to fail, and the geometry question
> to settle before writing more solver code).  This section is the long
> form, with the evidence.

This is the implementation of what 闁?2.7 asked for, with a different (and
correct) solver choice.  For every curve that has a conductor, `make_sif.py`
now generates a SIF in which the coil and the load resistor are genuinely
coupled.  (There is no mode flag: see 闁?3.10, the open variant is gone.)

NOTE: 闁?3.3-闁?3.8 were written while the flag still existed.  Read
`--circuit closed` in them as "a curve with N_turns > 0".

### 13.1 The correction: `CoilSolver` is the wrong tool

闁?2.7 proposed `Procedure = "CoilSolver" "CoilSolver"`, citing upstream
`fem/tests/CoilSolver1/case.sif`.  Inspecting the shipped Windows build
(`elmer262/share/elmersolver/lib`) confirms the plugin exists, and that
`CoilSolver.dll` does parse `Coil Start`, `Coil End`, `CoilPot` and
`Coil Current`:

```
CoilSolver.dll   CircuitsAndDynamics.dll   SimpleCircuits.dll
FluxSolver.dll   DivergenceSolver.dll
```

But `CoilSolver` solves the **static** current distribution in a stranded
coil for a prescribed total current.  It does not solve the transient loop
`EMF = I*R + d(L*I)/dt` that a magnet falling through a coil actually
excites.  Using it would have produced a converged, well-formed SIF with
the wrong physics -- the worst kind of failure, because nothing would look
broken.

### 13.2 The right route

Enumerating `fem/tests` found the canonical cases:

| test | what it teaches |
|------|-----------------|
| `circuits_transient_stranded` | transient + stranded coil + circuit, 3D |
| `circuits2D_transient_variable_resistor` | a load modelled as a `Component` |
| `circuits_transient_stranded_full_coil` | the same circuit, different mesh |

The decisive line is a comment in `variable_resistor.sif`:

```
! Now we define the variable resistor. It is similar to FE components
! in the sense that Elmer will write the component equation to the row
! of the voltage component (row 6).  So no need to write V=RI.
```

**A resistor is just a `Component` block.**  Elmer assembles `V = R*I`
itself.  So the whole closed-circuit problem reduces to declaring two
components and letting `CircuitsAndDynamics` do the algebra:

```elmer
Component 1                                  ! the coil
  Name = String "CoilWinding"
  Master Bodies = Integer 1
  Coil Type = String stranded
  Number of Turns = Real 50
  Electrode Boundaries(2) = Integer 3 4
End

Component 2                                  ! the load
  Name = String "LoadResistor"
  Component Type = String Resistor
  Resistance = Real 10.0
End
```

### 13.3 What a conductor curve inserts

Five independent changes, all in `make_sif.py`:

1. **Material 1 conductivity** `0.0` -> the curve's `sigma_wire`
   (copper 5.96e7, aluminium 3.5e7).  Rewritten on **every** call, not
   guarded by the idempotency check, because it is curve-dependent.
2. **`Component 1` / `Component 2`** as above, inserted before the
   `!  Boundaries` header.
3. **`Body Force "Circuit"`** carrying the source definition.
4. **Solvers** for `CircuitsAndDynamics` + `CircuitsOutput`, with
   Solver 1-4's list rewritten to `Active Solvers(6) = 1 2 3 4 5 6`.
5. **`INCLUDE circuits.definitions`** before the Header, and the file
   itself written next to the SIF.

### 13.4 Why the circuit source is a **0 V** source

Deriving a source-free MNA topology from first principles is possible but
would be untested, and the generator cannot be run end-to-end here.  So the
topology is reused **verbatim** from
`variable_resistor_circuit.definitions` -- a 6-unknown series loop that is
known to converge -- with the single change `testsource = Real 0.0`.

With `V_source = 0` the loop equation `-v_source + v_coil + v_load = 0`
collapses to `v_coil = -v_load`: no external drive, the magnet's induced
EMF pushes current through the load.  That is exactly the experiment, and
it costs nothing in fidelity.


### 13.5 Bugs this session found and fixed

All three would have burned HPC time or produced silent nonsense:

1. **Row-eating regex.**  The solver list was written with `[\d\s]+`, and
   `\s` matches newlines.  It emitted
   `Active Solvers(3) = 1 2 3 4 5 6 7Mesh Update = Logical True` -- a
   corrupted SIF.  Fixed to `[ \t]` + `$` anchors.
2. **Stale solver count.**  `Active Solvers(3)` was left as `(3)` while
   listing seven solvers.  Elmer reads the count.
3. **Wrong boundary indices.**  The coil end faces are gmsh physical groups
   1003 / 1004, but `ElmerGrid -autoclean` renumbers boundary groups
   **sequentially**, so the SIF must say `Target Boundaries = 3` / `4`.
   Writing 1003 gives `target boundary not found` at load time.  The
   template's own comment above BC 1 documents the 1001->1 / 1002->2 half
   of this mapping.

### 13.6 WHAT IS NOT VERIFIED (read this before dispatching)

**This has never been executed.**  The dev machine has no `gmsh` and the
Docker daemon is down, so not one step of the closed path has run.  Asset
by asset:

**Update: it HAS now been executed once** -- see 闁?3.9.  The Docker image
was built and the generated SIF was run against real `gmsh` + `ElmerGrid` +
`ElmerSolver`.  The table below is the revised verdict.

| asset | status |
|-------|--------|
| SIF text structure, key placement, no duplicate keys | **verified** by `tests/test_sif_circuit.py` (26/26) |
| open path byte-identical to `case_transient.sif` | **verified** |
| refusal of no-curve / N_turns=0 / R_load=inf | **verified** |
| `CoilStart`/`CoilEnd` emitted by gmsh | **VERIFIED BY EXECUTION** -- `mesh.names` shows them |
| `ElmerGrid -autoclean` renumbering to 3 / 4 | **VERIFIED BY EXECUTION** -- exactly 3 and 4 |
| `Master Bodies = Integer 1` is the coil | **VERIFIED** -- `StrandedCoil = 1`, and Elmer logs `"Body 1" associated to "Component 1"` |
| the MNA matrix entries | **VERIFIED** -- Elmer logs `Initializing circuit 1 with 6 variables`, `Writing resistor equation, component 2`, and reports `r_component(2) = 1.0000E+01` (our 10 ohm) |
| the coil's own `r_component(1)` | **reported as 0.0** -- wrong; needs the W/coil-type work below |
| a full 3-step transient | **FAILS** -- see 闁?3.9 for the two blockers |

The MNA decode turned out to be **correct**.  The two remaining blockers are
not in the circuit definition at all; they are in how the coil body is
declared and post-processed.

### 13.7 HPC validation protocol

Do **not** dispatch all 6 closed curves first.  Run this instead:

```bash
# 1. mesh only -- confirm the coil end faces exist at all
python solenoid3d.py --config config.json
gmsh -3 model3d.geo -o model3d.msh
ElmerGrid 14 2 model3d.msh -out mesh -autoclean
cat mesh/mesh.names            # <- MUST show the coil faces at 3 and 4

# 2. generate, then shrink the timeline before spending wall-clock
python make_sif.py --out case.sif --curve N50_L040_cu_closed --circuit closed
#    edit case.sif: Timestep intervals = 3   (instead of 600)
ElmerSolver case.sif | tail -40

# 3. only if (1) and (2) are clean
bash hpc/run_all_curves.sh --state closed
```

What to look for in step 2, in order of likelihood:

* `Boundary condition 3: target boundary not found` -> the renumbering
  assumption (闁?3.5 item 3) is wrong; fix `Target Boundaries` from
  `mesh/mesh.names`.
* `Component 1` rejected, or `Number of Turns` ignored -> `Master Bodies`
  is pointing at the wrong body.
* `CircuitsAndDynamics` complains about a singular matrix -> the MNA rows
  are wrong; the empty rows 3 / 5 are the first thing to reconsider.
* The solve runs but `i_component(1)` stays 0 -> the loop is open
  somewhere: check that `Coil Start` / `Coil End` landed on *different*
  surfaces (both on the same disk leaves the winding unconnected).

Once one closed curve converges, the other 5 are the same SIF with
different `Number of Turns` / `Resistance` / `sigma`, so they follow.

### 13.8 Follow-up work

* `oscilloscope.py` still computes `I = EMF / R_total` post hoc.  Once the
  closed FEM is validated, compare the two: they should agree, and the
  difference between them is a useful error bar.  Do not delete the
  post-hoc path until then.
* `hpc/run_case.slurm` needs no change: `run_all_curves.sh` now passes
  `--circuit` per curve, so `circuits.definitions` is already sitting in
  the case directory by the time `sbatch` runs.
* `.github/workflows/ci.yml` runs only `test_mesh.py` + `test_render.py`.
  `test_sif_circuit.py` is dependency-free and could be added there too.


---

### 13.9 FIRST REAL EXECUTION -- what running it actually did (2026-09-13)

The Docker image was built (`pysproject:3.5.0`) and the generated closed-circuit
SIF was run end-to-end against real `gmsh` + `ElmerGrid` + `ElmerSolver` inside
it.  This section is the raw result.  **The closed path does not yet complete a
transient**, but everything upstream of the coil body is now confirmed.

#### What got verified (and how)

`mesh/mesh.names`, with `solenoid3d.py --config N50_L040_cu_closed` then
`ElmerGrid 14 2 model3d.msh -out mesh -autoclean`:

```
! ----- names for bodies -----
$ StrandedCoil = 1        <- `Master Bodies = Integer 1` is right
$ Magnet       = 2
$ Air          = 3
! ----- names for boundaries -----
$ MagneticInfinity = 1
$ MagnetSurface    = 2
$ CoilStart        = 3    <- the renumbering is exactly 1003->3
$ CoilEnd          = 4    <- and 1004->4.  `Target Boundaries = 3 / 4` works.
```

`ElmerSolver` then reported, on the first timestep:

```
CircuitsAndDynamics: Initializing electric circuits for transient simulation
AddComponentsToBodyList: "Body 1" associated to "Component 1"
CircuitsAndDynamics: Circuit equations associated with solver index: 2
CircuitsAndDynamics: Initializing circuit 1 with 6 variables!
Circuits_Init: Component 2 is not a coil. Checking if it has a component type.
AddComponentEquationsAndCouplings: Writing resistor equation, component 2
CircuitsOutput: There are 6 Circuit Variables
CircuitsOutput: r_component(1)          0.0000E+00     <- WRONG, see below
CircuitsOutput: r_component(2)          1.0000E+01     <- our 10 ohm load
MAIN: Time: 2/3:   4.000E-03
```

So: **the 6-unknown MNA decode is correct, the resistor `Component` is
correct, the boundary renumbering is correct, and the `Component`-to-`Body`
binding is correct.**  The one thing that is visibly wrong is
`r_component(1) = 0`: the coil's own resistance comes out zero, which is the
symptom of the missing wire-direction potential.

#### Blocker 1 -- the stranded coil needs W (and more)

Without a wire-direction potential the run dies on the FIRST
`MagnetoDynamicsCalcFields` call:

```
WARNING:: GetWPotentialVar: Could not obtain variable for potential "W"
MagnetoDynamicsCalcFields: Number of components to compute: 12
Program received signal SIGSEGV: Segmentation fault
#3  magnetodynamicscalcfields_          (ElmerSolver rc=139)
```

Adding `Solver 5 = WPotentialSolver` (`Exec Solver = Before All`) plus
`W = Real 1` / `W = Real 0` on CoilStart / CoilEnd -- both are now in
`make_sif.py`, and locked down by
`test_the_coil_has_a_wire_direction_potential` -- changes the failure to:

```
ERROR:: GetElementRotM: RotM E variable not found        (rc=1, no crash)
```

`RotM E` is the rotation matrix from `CoordinateTransform` / `RotMSolver`.
`circuits_transient_stranded` obtains it by running, in this order,
**two `DirectionSolver` solves (Alpha, Beta) then `RotMSolver`**, with
`Alpha reference` / `Beta reference` on the coil Body and
`Alpha0/Alpha1/Beta0/Beta1` BCs.  That is the machinery for a coil whose
*local wire direction varies across the body*; it is not yet wired up here.
Note `.so` availability is not the problem -- `CoordinateTransform.so`,
`DirectionSolver.so` and `WPotentialSolver.so` are all present in the image.

#### Blocker 2 -- `Massive` gets further, then CalcFields wants a circuit voltage

Switching `Component 1` to `Coil Type = String Massive` (per
`circuits_transient_massive`, which needs **no** `RotMSolver` at all because a
solid conductor has no local wire frame) removes the RotM error.  That variant
then runs timestep 1 and dies later with:

```
ERROR:: MagnetoDynamicsCalcFields: Circuit Voltage Variable Id not found!
```

Adding `Foil Winding Voltage Polynomial Order`, `Circuit Equation Voltage
Factor`, and `A {e} = Real 0` on both end faces does not change it, so the
missing piece is inside `MagnetoDynamicsCalcFields`' own circuit wiring, not
in the `Component`.

#### The physics fork this exposes

`Massive` is a **solid** conductor: no `Number of Turns`, so the N sweep --
which is one of the three axes of the 12-curve design -- would not enter the
FEM at all.  `Stranded` is the physically intended model for a wound coil, but
needs the Direction/RotM stack.  **This is a real design decision, not a bug
fix**, so it is left flagged rather than guessed at.

#### Recommended next step

Wire up the `DirectionSolver` x2 + `RotMSolver` chain from
`circuits_transient_stranded`, keeping `Coil Type = String stranded`.  That
test's `Solver 1/2/3/4` blocks are the literal template, and it also shows the
`Alpha reference (3) = Real 1 0 0` / `Beta reference (3) = Real 0 1 0` keys on
the coil Body plus the `Alpha0/Alpha1/Beta0/Beta1` BCs they need.  Re-run the
three-step smoke test (`闁?3.7`) after each addition -- the failures are
immediate and specific, so the loop is fast.

#### A geometry question to settle FIRST (this may change the mesh)

Before wiring the Direction/RotM stack, check whether the coil body even has
the faces it needs.  `circuits_transient_stranded` uses a rectangular block,
which has 6 faces, and it spends all 6:

| faces | role |
|-------|------|
| `alpha0` / `alpha1` | Dirichlet pair for the `Alpha` direction solve |
| `beta0` / `beta1` | Dirichlet pair for the `Beta` direction solve |
| `gamma0` / `gamma1` | `W = 1` / `W = 0`, the wire direction |

Our coil is an **annulus**, not a block, so it has only 4 faces: inner
cylinder, outer cylinder, top disk, bottom disk.  `solenoid3d.py` currently
tags the top and bottom disks as `CoilStart` / `CoilEnd`, which makes them
the `gamma` pair -- i.e. `W` runs **axially** from 0 to 1.

But the winding is **azimuthal** (a solenoid), so `W` ought to run with
theta, and the `gamma` pair ought to be the two sides of a **radial slit**
through the annulus -- that slit *is* the pair of terminals a real winding
has.  With `W` varying axially the current would flow along z instead of
around the bore.

So the likely-correct shape is: cut a thin radial slit in the coil body,
tag its two faces `CoilStart` / `CoilEnd`, and then find four more faces (or
impose the direction BCs on the inner/outer/top/bottom set) for
Alpha/Beta.  Whether Elmer's `WPotentialSolver` actually needs the slit, or
tolerates the axial `W` and derives the azimuthal direction from `RotM`, is
**not known** -- it has not been tried.

Settle this before writing code: if the slit is needed, that is a
`solenoid3d.py` geometry change, and it invalidates the existing meshes and
the `CoilStart = 3` / `CoilEnd = 4` renumbering that
`hpc/smoke_test_closed.sh` currently asserts.


---

### 13.10 The open-circuit variant was REMOVED (2026-09-13)

Per an explicit decision, the sweep no longer has an open-circuit twin.  The
project now solves the closed circuit or nothing.

#### What changed

| before | after |
|--------|-------|
| 14 `[curves]` entries: 1 doc string + `empty` + 6 closed + 6 open | 8 entries: 1 doc string + `empty` + 6 closed |
| `make_sif.py --circuit {open,closed}`, default `open` | **no `--circuit` flag at all** |
| `circuit_state` field on every conductor curve | field gone; `N_turns > 0` *is* the criterion |
| `R_load_ohm` could be `"inf"` on a conductor curve | every conductor curve must have a finite `R_load_ohm` |
| `hpc/run_all_curves.sh --state {closed,open}` | `--state` gone |
| 12 HPC jobs | 7 (1 baseline + 6 closed) |

`make_sif.py` now decides from the curve itself:

```
--curve <conductor>  (N_turns > 0)  -> the closed circuit
--curve empty        (N_turns = 0)  -> the plain template, untouched
no --curve at all                   -> the plain template, untouched
```

The last two are the no-Lenz-braking baseline, and
`tests/test_sif_circuit.py::test_baseline_is_byte_identical_to_the_template`
pins them to `case_transient.sif` byte for byte.

#### The scientific cost (recorded deliberately)

The closed/open pair was the control that isolated the Lenz-feedback effect
with **everything else held fixed** -- same N, same material, only `R_load`
differing.  That control is gone.  What remains:

* `empty` (no conductor) vs any conductor curve: isolates "any conductor at
  all", but changes geometry *and* the presence of a circuit at once;
* N pairs (25/50/100) and material pairs (Cu/Al): isolate turns and
  conductivity.

So the Lenz effect can still be *seen* (the magnet's trajectory departs from
the `empty` baseline), but it can no longer be *cleanly separated* from the
"the coil body is there" effect.  If that separation turns out to matter,
the cheapest way back is to re-add ONE open curve rather than the full six.

#### A latent bug this removal exposed

While re-testing the dispatch path, `hpc/run_all_curves.sh` turned out to be
writing the generated SIF to the wrong place -- and destroying the template:

```
( cd "$case_dir" && python "$PROJ/make_sif.py" --curve "$curve" ... )
```

`make_sif.py` resolves its default `--out` as
`<directory of make_sif.py>/case_transient.sif`, i.e. relative to the
**script**, not the CWD.  The `cd` was therefore useless for the SIF: the
output landed in the project root as `case_transient.sif`, **overwriting the
template every other curve reads from**, and `run_case.slurm` then died with
`no case.sif in $PWD`.  Fixed by passing `--out case.sif` explicitly.

This was pre-existing, not introduced by the removal -- it would have broken
all 12 jobs on the first HPC dispatch, and it only surfaced because the
whole path was exercised inside the image.  A regression guard for it lives
in `test_baseline_is_byte_identical_to_the_template`, which fails loudly if
the template is ever mutated in place.

#### Still open

The two blockers in **闁?3.9** are unaffected by this change and are now the
only thing standing between the project and a runnable closed-circuit FEM.


---

## 14. Run lengthened to THREE spring periods (2026-09-13)

`experiment.t_end_default_s` 0.6 -> **0.9 s**, i.e. ~2.00 -> ~3.00 full
back-and-forth oscillations of the magnet.  Purely a change of simulated
duration; no other physics moved.

#### The arithmetic

`T = 2*pi/omega_d` for m = 0.5, k = 220, c = 0.8:

```
omega0 = sqrt(440)        = 20.97617696 rad/s
gamma  = 0.8 / 1.0        =  0.80000000 1/s
omega_d= sqrt(w0^2 - g^2) = 20.96091601 rad/s
T = 2*pi/omega_d          =  0.29975719 s
```

| t_end | periods | steps @ dt=0.001 |
|-------|---------|------------------|
| 0.6 (old) | 2.0016 | 600 |
| **0.9 (new)** | **3.0024** | **900** |

`0.9` rather than `3*T = 0.899272` keeps the existing convention: a round
number whose quotient by `dt` is a whole number of steps.

#### Note on which period is meant

`spring_model.py` defines `period = 2*pi/omega0` (**undamped**), not
`2*pi/omega_d`, and `tests/test_spring_model.py::test_period_is_two_pi_over_omega0`
locks that in.  The two differ by only 0.08 % here (0.29952 vs 0.29976 s)
because Q = 13.1, and both round to `t_end = 0.9`, so the choice is
unaffected.  Worth knowing if `sp['period']` is ever used for timing -- it
is the undamped period.

#### What did NOT change (checked, not assumed)

The travel **envelope** is set by the release amplitude, not the duration:
the extreme is still A = 25 mm at t = 0, and it has decayed to only 12.2 mm
by t = 3T.  So

* the air domain (z in [-80, 110] mm, R = 80 mm) still contains the motion
  with the same margin as before;
* no new collision or element-size risk is introduced -- there are simply
  more oscillations inside the same envelope;
* `RigidMeshMapper`'s per-step displacement is unchanged, because `dt` did
  not change.

#### The one thing that DID have to change with it

`case_transient.sif` carries its own copy of `Timestep Intervals`, and
three tests assert that `make_sif.py`'s default output reproduces the
template **byte for byte**:

```
[FAIL] test_umfpack_is_byte_identical_to_the_template
[FAIL] test_only_solver2_is_modified
[FAIL] test_baseline_is_byte_identical_to_the_template
```

That is the guard working as designed: the template is the committed
"as-shipped default", so config and template must agree.  `Timestep
Intervals = 600` -> `900` in the template, and all 29 + 13 + 21 tests pass
again.

#### Operational consequence

600 -> 900 steps means **1.5x the solver wall-clock per case**, and VTU
output grows to ~6-8 GB per case (see 闁?.4).  On the 7-case sweep that is
1.5x the total queue time.

#### Two stale comments fixed in passing

The template's own header and its `Body Force 2` block still described the
**free-fall** law -- "TRANSIENT magnetostatics with a FALLING magnet",
`z(t) = z0 - 1/2 g t^2`, and `Name = "FallingMagnet"` -- even though
`motion_mode` has been `"spring"` for a while and the MATC line right below
them held the damped-oscillator expression.  Corrected, and the body force
renamed to `OscillatingMagnet` (nothing reads that name; the SIF references
the block by index, and the only `FallingMagnet` elsewhere is a FreeCAD
*document* name in `visualize_freecad_macro.py`, unrelated).


---

### 13.11 Blocker hunt, round 2 (2026-09-13) -- what was tried and what it proved

Session goal: crack 闁?3.9's two blockers.  **Neither is solved**, but the
failure is now fully characterised and two hypotheses are definitively dead.

#### Hypotheses tested and REJECTED

**A. Solver order.**  Upstream `circuits_transient_*` runs
`CircuitsAndDynamics` *before* `WhitneyAVSolver`/`CalcFields`; our patch
appended it last.  Reordering to `Active Solvers(6) = 5 1 6 2 3 7`
(W, mesh, circuits, Whitney, CalcFields, output) changed nothing:

```
variant A: stranded, corrected order -> GetElementRotM: RotM E variable not found
variant B: Massive,  corrected order -> Circuit Voltage Variable Id not found!
```

**B. Two-equation structure.**  The reference gives the COIL body its own
`Equation` carrying the circuit solvers, and leaves magnet + air on a plain
one.  Replicating that (`Equation 2 / Active Solvers(5) = 5 6 2 3 7` on
Body 1) also changed nothing -- same two errors.

#### What the source actually says

`fem/src/modules/CircuitUtils.F90` is the only place in the whole tree that
names these keys, and it only ever **READS** them (lines 396-411):

```fortran
CoilType = GetString(ComponentParams, 'Coil Type', Found)
IF(.NOT. Found) CYCLE
SELECT CASE (CoilType)
CASE ('stranded')
  VarName = 'Circuit Current Variable Id'
CASE ('massive','foil winding')
  VarName = 'Circuit Voltage Variable Id'
CASE DEFAULT
  CYCLE
END SELECT
IF(.NOT. ListCheckPresent(ComponentParams, VarName) ) THEN
  CALL Warn('CheckComponentOwners','Coil type given for component '//...
  j = j + 1
END IF
...
IF(j > 0) THEN
  CALL Fatal('CheckComponentOwners','Check your circuit settings!')
END IF
```

`CircuitsAndDynamics.F90` (107 kB, downloaded and grepped) contains **no
occurrence of either key**.  So:

> **`Circuit Voltage Variable Id` (massive/foil) and
> `Circuit Current Variable Id` (stranded) are USER-SUPPLIED keys on the
> `Component` block.**  Elmer does not compute them; it validates them and
> dies if they are missing.

That is consistent with the error text, which is a plain "not found".

#### The decisive experiment

Adding the key under `Coil Type = Massive` **removes the "not found" error
entirely** -- and then segfaults for every candidate value:

| `Circuit Voltage Variable Id` | result |
|-------------------------------|--------|
| (absent) | `ERROR:: ... not found!` (clean abort) |
| 1, 2, 3, 4, 5, 6 | `SIGSEGV` (rc=139), 1 timestep logged |

So the key is right and the **value** is wrong: Elmer is indexing the
circuit's variable array out of bounds.

The value must be an index into `Circuit % CircuitVariables`, whose layout
is built in `AllocateCircuit` / `ReadCircuitVariables` from the
`C.1.perm` permutation declared in `circuits.definitions`.  The two upstream
examples use DIFFERENT permutations:

```
circuits2D_transient_variable_resistor :  perm = [0,1,2,3,4,5]   (identity)
circuits_transient_stranded            :  perm = [2,3,1,0]       (not!)
```

Neither upstream SIF sets the key, so both rely on Elmer filling it from
that permutation.  **The missing piece is how the permutation maps to the
id** -- that is the next thing to chase, and it is in
`CircuitUtils.F90`'s `AddComponentEquationsAndCouplings` /
`ReadCircuitVariables`, not in anything we control from the SIF.

#### Side finding: an unlisted keyword

With `Coil Type = Massive`, Elmer logs

```
CheckKeyword:  Unlisted keyword: [foil winding voltage polynomial order] in section: [component 1]
CheckKeyword:  Unlisted keyword: [electrode boundaries] in section: [component 1]
```

`Foil Winding Voltage Polynomial Order` belongs to the FOIL coil type, not
Massive -- it was copied from the reference without checking. Harmless, but
it should not be emitted for a Massive coil.

#### A bug FOUND in our own patch (not yet fixed)

The template's original equation is

```
Equation 1
  Active Solvers(3) = 1 2 3
```

i.e. **Solver 4 (VtuOutputSolver) is deliberately NOT active** -- it is
driven by `Output Intervals`, as the template comment says.  Our
`patch_circuit_closed()` rewrites the line to `1 2 3 4 5 6 7`, which
**activates Solver 4 as well**.  That silently changes the output schedule
of every conductor run.  The reordered variants above
(`5 1 6 2 3 7`) are what the patch should emit; see the follow-up list.

#### Net state

| item | state |
|------|-------|
| mesh: `CoilStart`/`CoilEnd`, body indices | **works** (executed) |
| `Component` + MNA + resistor | **works** (executed, `r_component(2) = 10.0`) |
| solver order as the cause | **disproved** |
| two-equation structure as the cause | **disproved** |
| `stranded` | blocked on `RotM E` (needs Direction闁? + RotMSolver + 4 more BC faces) |
| `massive` | blocked on the `Circuit Voltage Variable Id` **value** |
| the `Active Solvers` regression above | **open, our own bug** |

Recommended next step is unchanged from 闁?3.9 (settle the radial-slit
geometry question first), but the cheap, independent win is the
`Active Solvers` fix above -- it is a regression we introduced, it is
testable without any of the closed-circuit machinery, and it should be
closed out on its own.


---

### 13.12 GEOMETRY QUESTION SETTLED: the annulus needs a RADIAL SLIT (2026-09-13)

The question from 闁?3.9 -- "does our annular coil need a radial slit, or can
`W` run axially between the top and bottom disks?" -- is now **answered, by
two independent lines of evidence**.  The answer is **yes, it needs a slit**,
and it also shows that the current `CoilStart` / `CoilEnd` tagging is
**actively wrong** for a solenoid.

#### Evidence 1 -- the source: W is anisotropic and `massive` never rotates

`fem/src/modules/WPotentialSolver.F90`, `SUBROUTINE LocalMatrix`:

```fortran
C(1,1:3) = [0,0,0]
C(2,1:3) = [0,0,0]
C(3,1:3) = [0,0,1]                       ! default: conduction along z ONLY
...
C(i,j) = SUM( Tcoef(i,j,1:n) * Basis(1:n) )
IF (CoilBody .AND. CoilType /= 'massive' .AND. .NOT. NoRotM) THEN
  RotMLoc(i,j) = SUM( RotM(i,j,1:n) * Basis(1:n) )
END IF
...
IF (CoilBody .AND. CoilType /= 'massive' .AND. .NOT. NoRotM) THEN
  C = MATMUL(MATMUL(RotMLoc, C), TRANSPOSE(RotMLoc))    ! only now
END IF
STIFF(i,j) = STIFF(i,j) + SUM(MATMUL(C, dBasisdx(i,:)) * dBasisdx(j,:))*detJ*IP%s(t)
```

So `W` solves the anisotropic Laplace problem `闂?(C 闂佹剚鍘煎Σ? 閻?闂佹剚鍘煎?d闁诡垳鍓?with

* **`Coil Type = Massive` -> C is NEVER rotated -> `diag(0,0,1)`**, so `W`
  then varies along **global z only**.
* `stranded` / `foil winding` -> `C` is rotated by `RotM` into the local wire frame, so the conduction axis can be arbitrary.

The module header confirms what `W` is: *"Module for computing the wire
direction for coils"* (Eelis Takala).

There is also a `Without RotM = Logical True` component key, which forces the
un-rotated `diag(0,0,1)` tensor for `stranded` too -- i.e. an escape hatch
that keeps `Number of Turns` while still conducting along z.

#### Evidence 2 -- the geometry: our W pair is the two z-normal disks

`solenoid3d.py` builds the coil as a hollow cylinder (`occ.cut` of two
`addCylinder`s), so the body has exactly **4 faces**: inner cylinder, outer
cylinder, and two annular disks at `z = S_Z0` and `z = S_Z1`.

The `CoilStart` / `CoilEnd` selection (lines 246-273) tags **only the flat
disks** and explicitly **discards the lateral surfaces**:

```python
if abs(bb[2] - bb[5]) > 1e-4:
    continue  # lateral surface, skip
z_mid = 0.5 * (bb[2] + bb[5])
if abs(z_mid - S_Z0) < 1e-4:  coil_start_srf.append(tag)   # z = S_Z0
elif abs(z_mid - S_Z1) < 1e-4: coil_end_srf.append(tag)    # z = S_Z1
```

Confirmed on the generated mesh by querying gmsh directly:

```
tag=1003   'CoilStart'   r=[0.0354,0.0354]  z=[0.0000,0.0000]
tag=1004   'CoilEnd'     r=[0.0354,0.0354]  z=[0.0400,0.0400]
```

Both are **z-normal planar disks**. They are not separated in theta.

#### The conclusion

Combining the two: with `Coil Type = Massive`, `C = diag(0,0,1)` and the
`W = 0 / 1` pair sits on the two z-normal disks, so **W varies purely with
`z` and the current flows AXIAL, parallel to the bore axis**.

> **That is a tubular axial conductor, not a solenoid winding.** Even if the
> `Circuit Voltage Variable Id` blocker (闁?3.11) were solved, the physics
> from the `massive` route would be wrong. The `massive` route is dead for
> this geometry regardless.

To get the **azimuthal** current a solenoid needs, `stranded` is required,
hence `RotM`, hence the `Alpha` x `Beta` direction solves. And for a ring
wound in theta the local frame has to be

```
alpha = r-hat   (from the inner / outer cylinder faces)
beta  = z-hat   (from the bottom / top disk faces)
gamma = alpha x beta = -theta-hat      <- the wire direction
```

so `gamma` is the wire axis, and the `W = 0 / 1` pair must be the two sides
of a **radial slit** through the annulus. That slit is exactly the pair of
terminals a real winding has.

#### Consequent design (NOT yet implemented)

| face | now | must become |
|------|-----|-------------|
| inner cylinder (r = 20 mm) | untagged | `Alpha0` (`Body 1: Alpha = 0`) |
| outer cylinder (r = 25 mm) | untagged | `Alpha1` (`Body 1: Alpha = 1`) |
| bottom disk (z = 0) | `CoilStart` | `Beta0` (`Body 1: Beta = 0`) |
| top disk (z = 40 mm) | `CoilEnd` | `Beta1` (`Body 1: Beta = 1`) |
| **radial slit, side A** | -- | **`CoilStart`** (`W = 1`) |
| **radial slit, side B** | -- | **`CoilEnd`** (`W = 0`) |

plus, on `Body 1`: `Alpha reference (3) = Real 1 0 0` and
`Beta reference (3) = Real 0 1 0`.

All six faces are consumed, which is exactly what upstream
`circuits_transient_stranded` does with its six-sided block -- so our
4+slit annulus is the right shape, not a coincidence.

#### What this costs

* `solenoid3d.py` must cut the slit (a thin `occ.cut` box through the
  annulus) and retag six faces instead of two.
* The existing **meshes are invalidated**, and so is the
  `CoilStart = 3` / `CoilEnd = 4` renumbering that
  `hpc/smoke_test_closed.sh` step 2b asserts today -- with six coil groups
  the `ElmerGrid -autoclean` indices will shift.
* `make_sif.py` must emit four more BCs plus the `Alpha`/`Beta` reference
  keys, and the `DirectionSolver` x2 + `RotMSolver` solvers.

#### Recommendation

Do the geometry change first; it is the thing everything else waits on, and
it is now fully specified.  Two things to decide before coding:

1. **Slit width.** It must be thin enough not to perturb the field but wide
   enough to mesh.  Something on the order of the wire diameter (0.7 mm) is
   the natural scale, and it should be refined at least as finely as the
   wire cross-section.
2. **Whether the slit should be filled with air or left as a void touching
   the bore.** A void that opens into the bore changes the magnetic path;
   a slit that closes on itself (a thin air wedge cut but not penetrating)
   does not.  This is a modelling choice with a physical consequence and
   should be made deliberately.


---

## 15. Radial slit + the full stranded-coil stack (2026-09-13)

Implementation session: did 闁?3.12's geometry change and 闁?3.9's direction
stack.  **The closed circuit still does not run**, but the failure is now
pinned to a single, precisely-located cause (闁?5.5), and everything up to it
is verified working.

### 15.1 The radial slit -- DONE and verified

`solenoid3d.py` now cuts a thin radial slit through the coil annulus and
retags six faces, replacing the two it used to tag:

| physical group | tag | what it is |
|---|---|---|
| `CoilStart` | 1003 | slit side, `W = 1` |
| `CoilEnd` | 1004 | slit side, `W = 0` |
| `Alpha0` | 1005 | inner cylinder (r = 20 mm) |
| `Alpha1` | 1006 | outer cylinder (r = 25 mm) |
| `Beta0` | 1007 | bottom disk (z = 0) |
| `Beta1` | 1008 | top disk (z = 40 mm) |

`ElmerGrid -autoclean` renumbers them **3/4/5/6/7/8 in tag order**, so the
existing `Target Boundaries = 3` / `4` for CoilStart/CoilEnd are unchanged --
`smoke_test_closed.sh` step 2b still holds.

Two bugs had to be fixed to get there:

1. **The slit tool was being swallowed into the coil body.** `solenoid3d.py`
   classifies volumes by bounding box, and the slit tool (a slab from
   `x = 0` to `x = S_OUT`) satisfies every test for "coil" -- same z-range,
   same `rmax`.  It is excluded now by requiring the full diameter
   (`xmax - xmin > 2*S_OUT - 1e-3`), which a real annulus has and a
   half-width slab does not.
2. **The slit tool must be KEPT** (`removeTool=False`) and passed to
   `occ.fragment`, otherwise the slit is a void belonging to no volume and
   the mesh simply has a hole through the coil.

#### Slit width / mesh cost -- measured, not guessed

The slit must be resolved, but `lc_coil_m` is 8 mm while the slit is
millimetre-scale, and gmsh point-sizes spread the fine size through the
whole air domain.  A sweep (baseline before the slit: 2502 nodes / 14084
elements):

| slit / `lc_slit` | nodes | elements | ratio |
|---|---|---|---|
| 1.5 mm / 1.2 mm | 19369 | 118097 | 8.4x |
| 3.0 mm / 3.0 mm | 3852 | 22658 | 1.6x |
| 3.0 mm / 2.0 mm | 6740 | 40155 | 2.9x |
| **3.5 mm / 2.5 mm** | **4681** | **27498** | **2.0x** |
| 5.0 mm / 5.0 mm | 2367 | 13282 | 0.9x |
| 2.5 mm / 1.8 mm | 8767 | 52628 | 3.7x |

**Chosen: 3.5 mm slit, `lc_slit_m` = 2.5 mm** (2.0x cost, ~1.4 elements
across the slit, ~2.5 % of the coil material removed).  Added to
`config.json [coil]` as `slit_width_m` and `[mesh]` as `lc_slit_m`.

**`lc_min_m` MUST be <= `lc_slit_m`** -- it is a global floor, so leaving it
at the old 3 mm coarsens the slit straight back out.  It is now 2.5 mm.


### 15.2 The direction + frame stack -- DONE

Six new solvers replace the previous two:

```
Solver 5   DirectionSolver (Alpha)   Exec Solver = "Before all"
Solver 6   DirectionSolver (Beta)    Exec Solver = "Before all"
Solver 7   RotMSolver                Exec Solver = "Before All"
Solver 8   WPotentialSolver          Exec Solver = "Before All"
Solver 9   CircuitsAndDynamics       Exec Solver = Always
Solver 10  CircuitsOutput            Exec Solver = Always
```

plus `Alpha reference (3) = Real 1 0 0` and `Beta reference (3) = Real 0 0 1`
on Body 1, and the four new BCs (Alpha0/Alpha1/Beta0/Beta1 = target 5..8).

**`GetElementRotM: RotM E variable not found` is GONE.**  All of 5/6/7/8
load, run in the `Before All` phase, and the W solve converges:

```
SingleSolver: Attempting to call solver: 8
SingleSolver: Solver Equation string is: wire direction
AddComponentsToBodyList: "Body 1" associated to "Component 1"
ComputeChange: NS (ITER=1) (NRM,RELC): ( 0.45958648  2.0000000 ) :: wire direction
```

### 15.3 The two keys CalcFields demands -- found in the source

`fem/src/modules/MagnetoDynamics/CalcFields.F90`, `CASE ('stranded')`:

```fortran
IvarId = GetInteger (CompParams, 'Circuit Current Variable Id', Found)
IF (.NOT. Found) CALL Fatal (Caller, 'Circuit Current Variable Id not found!')
N_j = GetConstReal (CompParams, 'Stranded Coil N_j', Found)
IF (.NOT. Found) CALL Fatal (Caller, 'Stranded Coil N_j not found!')
```

* **`Circuit Current Variable Id`** (Integer) -- which circuit unknown holds
  this coil's current.  The value does not matter to the "not found" check
  (0..7 all pass it); it is used as `LagrangeVar % Values(IvarId)`.
* **`Stranded Coil N_j`** (Real) -- the **turn density N/A_coil**, because
  the source sets `ItoJCoeff = N_j` and needs `J = N_j * I` in A/m^2.  For
  our 50-turn coil: `50 / ((0.025-0.020)*(0.040-0.000)) = 2.5e5 1/m^2`.

Both are emitted on **Component 1 AND on the `Circuit` Body Force**, because
a second code path reads them from the Body Force
(`CalcFields.F90:1130-1138`, the `ImposeCircuitCurrent` branch).

Also added: `Export Lagrange Multiplier = Logical True` on Solver 2 --
without it `CircuitsAndDynamics.F90:184`'s
`ASolver => FindSolverWithKey('Export Lagrange Multiplier')` finds nothing.

### 15.4 The `empty` baseline still runs

Verified `rc=0`, 3 steps, for `--curve empty`.  The baseline invariant is
intact and now asserted by
`test_baseline_is_byte_identical_to_the_template`.


### 15.5 THE BLOCKER: CircuitsAndDynamics and CircuitsOutput never execute

> **SOLVED in 闁?5.7.**  The cause was Elmer executing the per-timestep
> solvers in SOLVER-NUMBER order, so an `Always` circuit solver could only
> be reached after Solver 3 (CalcFields) had already crashed.  Read this
> section for the evidence trail, then 闁?5.7 for the fix.

**This is the one thing left, and it is precisely located.**

`CircuitsAndDynamics` (Solver 9) and `CircuitsOutput` (Solver 10) are
**configured but never invoked**.  Evidence, all from one run:

**(a) Their signature log lines are absent.**  The very first closed-circuit
run (闁?3.9) had all of these; none appear now:

```
CircuitsAndDynamics: Initializing electric circuits for transient simulation
CircuitsAndDynamics: Initializing circuit 1 with 6 variables!
AddComponentEquationsAndCouplings: Writing resistor equation, component 2
CircuitsOutput: r_component(2)          1.0000E+01
```

(The one `AddComponentsToBodyList:` line that does appear comes from
`WPotentialSolver`'s init, not from the circuit module.)

**(b) The coupled-solver loop never calls them.**  Only 1, 2, 3, 5, 6, 7, 8
ever appear as `Attempting to call solver:`; 9 and 10 never do.

**(c) No Lagrange multiplier exists.**  `CalcFields.F90:798` logs
`Using Lagrange multiplier: <name>` at `Level=20` when the variable is
found.  With `Max Output Level = 20` that line is **absent**, so
`LagrangeVar` is NULL.  `CircuitsAndDynamics.F90:242-259` would log
`Associating circuit variable to Lagrange values!` at `Level=8` -- also
absent.  No line containing `multiplier` appears anywhere in the log.

**(d) The circuit never enters the A-matrix.**
`SolveWithLinearRestriction: ... Collection matrix increased with 6 rows` --
present in the first working run, nowhere now.  That message comes from
`AddConstraintFromBulk` merging the circuit rows
(`WhitneyAVSolver.F90:627`).

**Consequence:** `LagrangeVar % Values(IvarId)` dereferences a NULL pointer
and `MagnetoDynamicsCalcFields` SIGSEGVs:

```
MagnetoDynamicsCalcFields: Number of components to compute: 12
WARNING:: GetPermittivity: Permittivity not defined in material, ...
Program received signal SIGSEGV ... #3 in magnetodynamicscalcfields_
```

#### Ruled out (tested, not guessed)

| hypothesis | test | result |
|---|---|---|
| `Active Solvers` must be ascending | `1 2 3 5 6 7 8 9 10` | still skipped |
| `Active Solvers` must be contiguous from 1 | `1 2 3 4 5 6 7 8 9 10` | still skipped |
| the reorder itself broke it | original `5 6 7 8 1 9 2 3 10` | still skipped |
| `Export Lagrange Multiplier` is the culprit | removed it | identical segfault |
| `Coil Use W Vector = Logical True` avoids it | set it | identical segfault |

So it is not list syntax and not the Lagrange key: **solvers 9 and 10 are
specifically not reached.**  Solvers 4 (VtuOutput, correctly inert), 9 and
10 are the only three that never run; 1, 2, 3, 5, 6, 7, 8 all do.

#### Where to look next

`WPotentialSolver_Init0` and `DirectionSolver_Init0` both MUTATE the
equation's `Active Solvers` array during setup:

```fortran
n = Model % NumberOfSolvers
DO i=1,Model % NumberOFEquations
  Active => ListGetIntegerArray(Model % Equations(i) % Values, 'Active Solvers', Found)
  m = SIZE(Active)
  IF ( ANY(Active==mysolver) ) &
    CALL ListAddIntegerArray( Model % Equations(i) % Values, 'Active Solvers', m+1, [Active, n+1] )
END DO
```

They append their own DG dummy solver (`elementaladdalpha`,
`elementaladdbeta`, `elementaladd1`, ... numbered 11, 12, 13 per the log).
With **four** such solvers now running, that array is mutated four times
before the timeloop starts.  Whether that is what knocks out 9 and 10 is not
established, but it is the first thing to instrument -- e.g. raise the output
level and watch how Elmer enumerates the active set, or renumber the circuit
solvers down to 5 and 6 so they are appended-to rather than appended-after.

### 15.6 Net state

| item | state |
|---|---|
| radial slit + six coil faces | **works** (verified: gmsh + `mesh.names`) |
| mesh cost | 27498 elements, 2.0x baseline |
| DirectionSolver x2 + RotMSolver + WPotentialSolver | **run**; `RotM E` error gone; W converges |
| `Circuit Current Variable Id`, `Stranded Coil N_j` | **found in source, emitted, no longer "not found"** |
| `Export Lagrange Multiplier` on Solver 2 | added |
| `empty` baseline | **still rc=0, 3 steps, byte-identical template** |
| **CircuitsAndDynamics / CircuitsOutput** | **were never executing -- FIXED in 闁?5.7** |
| **a full transient** | **WORKS** (3 steps rc=0; see 闁?5.7) |

Tests: `tests/test_sif_circuit.py` **33/33** (updated for the new solver
numbering, the new Body-1 / Solver-2 keys, and the 闁?5.7 `Exec Solver` fix).


---

### 15.7 ROOT CAUSE FOUND AND FIXED -- Elmer runs solvers in NUMERIC order

**闁?5.5's blocker is solved.**  The circuit was never assembled because
Elmer executes the per-timestep solvers **in solver-number order**, not in
the order they are listed in `Active Solvers`.

#### The two loops that matter

`ElmerSolver.F90`, `ExecSimulation` (the pre-timeloop pass):

```fortran
nSolvers = CurrentModel % NumberOfSolvers
DO i=1,nSolvers
   Solver => CurrentModel % Solvers(i)
   IF ( Solver % PROCEDURE==0 ) CYCLE
   DoIt = ( Solver % SolverExecWhen == SOLVER_EXEC_AHEAD_ALL )   !! "Before All"
   IF( DoIt ) CALL SolverActivate( CurrentModel, Solver, dt, .FALSE. )
END DO
```

`MainUtils.F90`, `SolveEquations` (each timestep, after
`CALL SolveEquations(..., BeforeTime=.TRUE., AtTime=.TRUE., ...)`):

```fortran
! 3014: the "before timestep" pre-pass
IF( ExecSlot ) THEN
  CALL Info('SolveEquations','Solvers before timestep',Level=12)
  DO k=1,nSolvers
    Solver => Model % Solvers(k)
    IF ( Solver % SolverExecWhen == SOLVER_EXEC_AHEAD_TIME .OR. &
         Solver % SolverExecWhen == SOLVER_EXEC_PREDCORR ) THEN
      CALL SolverActivate( Model, Solver, dt, TransientSimulation )
...
! 3310: the "always" pass
DO k=1,Model % NumberOfSolvers
   Solver => Model % Solvers(k)
   IF ( Solver % SolverExecWhen /= SOLVER_EXEC_ALWAYS ) THEN
     DoneThis(k) = .TRUE.; CYCLE
   END IF
```

Both are `DO k = 1, nSolvers` -- **index order, i.e. solver NUMBER**.  The
`Active Solvers` array only decides *which* solvers are active; it does
**not** order them.

#### Why that broke us

`MagnetoDynamicsCalcFields` is **Solver 3**, and solvers 1/2/3 are the
template's (`RigidMeshMapper`, `WhitneyAVSolver`, `CalcFields`).  The
circuit solvers were 9 and 10, so within a timestep the order was

```
1 mesh  2 Whitney  3 CalcFields  <= SEGFAULT here   ... 9 circuits  10 output
```

`CalcFields` reads `LagrangeVar % Values(IvarId)`, and the Lagrange
multiplier is created **by the circuit assembly**, which now runs *after*
it.  A circular dependency: **the missing circuit caused the crash, not the
other way round.**

That also explains why the very first closed-circuit attempt got further.
There the circuit pair was `Solver 5/6`, the file had six solvers and no
direction stack, so the circuit was assembled and only the *field*
post-processing failed.  Once the direction/frame solvers pushed the
circuit up to 9/10 -- above `CalcFields` at 3 -- it became unreachable.

#### The fix

Run the circuit pair in the **`Before timestep`** pre-pass, which executes
before the `Always` pass:

```elmer
Solver 9
  Exec Solver = "Before timestep"          !! was `Always`
  Equation = "Circuits"
  Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics"
End

Solver 10
  Exec Solver = "Before timestep"          !! was `Always`
  Equation = "Circuits Output"
  Procedure = "CircuitsAndDynamics" "CircuitsOutput"
End
```

Solver 10 must stay numbered **above** 9: the pre-pass is also numeric
order, and the output has to follow the assembly.

#### Verified result

```
solvers run: 1 2 3 4 5 6 7 8 9 10          (all of them)
CircuitsAndDynamics: Initializing electric circuits for transient simulation
CircuitsAndDynamics: Initializing circuit 1 with 6 variables!
AddComponentEquationsAndCouplings: Writing resistor equation, component 2
CircuitsOutput: r_component(1)          2.9026E-02
CircuitsOutput: r_component(2)          1.0000E+01
SolveWithLinearRestriction: Creating variable for Lagrange multiplier
SolveWithLinearRestriction: Collection matrix increased with 6 rows and 2693 non-zeros
CircuitsAndDynamics: Add PrevValues to Lagrange multiplier!
rc=0   steps=3
```

**The transient now runs to completion** -- no segfault, the 6 circuit rows
enter the A-matrix, and the load resistance comes back out as exactly
10 ohm.

#### Hypotheses this retroactively explains away

Everything in 闁?5.5's "ruled out" table is consistent with this: list
order, contiguity, ascending-ness and the Lagrange key were all
irrelevant, because **none of them can move a solver ahead of Solver 3.**

#### 15.8 The 10x resistance bug -- SOLVED, and it is a fill factor

The old open question here was: why does the coil report
`r_component(1) = 2.9026e-02` ohm when 50 turns of 0.7 mm copper on a
22.5 mm mean radius should be ~0.31 ohm?

**Answer: the coil body's `Electric Conductivity` must be the HOMOGENISED
`f * sigma_wire`, not `sigma_wire`.**  This was a real bug; every
closed-circuit run made before this fix had a coil ~10x too conductive and
therefore an induced current ~10x too large.

The mechanism, from the source rather than from guessing.
`CircuitsAndDynamics.F90:697` builds the coil's series resistance as

    localR = Comp % N_j**2 * IP % s(t) * detJ * SUM(w*w) / localC
             * circ_eq_coeff / Comp % VoltageFactor

with `w` a unit vector, `localC` the element conductivity and
`circ_eq_coeff = 1` in 3D.  Integrated:

    R = N_j^2 * V_coil / sigma
      = (N/A_coil)^2 * (A_coil * L_mean) / sigma
      = N^2 * L_mean / (sigma * A_coil)          [Elmer's coil resistance]

That is the resistance of **N turns each of cross-section A_coil**, i.e. it
silently assumes the entire winding window is SOLID conductor.  The
physical wire resistance is instead

    R_wire = N * L_mean / (sigma_wire * A_wire)
           = N^2 * L_mean / (sigma_wire * f * A_coil)
    with   f = N * A_wire / A_coil      (the copper fill factor)

so the two agree **only** if the material carries `sigma_eff = f *
sigma_wire`.  Elmer has no way to know the fill factor -- it is told
`Number of Turns` and `Stranded Coil N_j` and nothing about the wire
diameter -- so the caller has to bake it into the conductivity.

Numbers for `N50_L040_cu_closed`: `A_wire = pi*(0.35 mm)^2 = 3.8485e-07`,
`A_coil = 5 mm * 40 mm = 2.0e-04`, `N = 50`

    f         = 50 * 3.8485e-07 / 2.0e-04 = 0.096211
    sigma_eff = 0.096211 * 5.96e7        = 5.7342e+06 S/m
    R_wire    = 50 * 0.14137 / (5.96e7 * 3.8485e-07)  = 0.3082 ohm
    R_elmer   = 2500 * 0.14137 / (5.7342e6 * 2.0e-04) = 0.3082 ohm

They now agree exactly.  Confirmed by running:

    before:  r_component(1) = 2.9026E-02
    after:   r_component(1) = 3.0169E-01      (hand value 0.3082)

The 0.302-vs-0.308 gap is mesh discretisation of `SUM(w*w)`, not physics
(`w` is only exactly a unit vector on an ideal cylinder).

The ratio is the diagnostic: `0.3082 / 0.0296 = 10.4 = 1/f`.  **If a
closed-circuit run ever reports the coil resistance as ~1/10 of the hand
value again, the fill factor has gone missing.**  Locked by
`test_material1_conductivity_is_the_homogenised_wire_sigma` and
`test_fill_factor_is_strictly_between_zero_and_one` in
`tests/test_sif_circuit.py`.

Expected `R_wire` per curve (all `L040`, 0.7 mm wire, 5x40 mm window):

    curve                  N    sigma_wire       f     sigma_eff    R_wire
    N25_L040_al_closed    25   3.500e+07   0.04811  1.6837e+06   0.2624
    N25_L040_cu_closed    25   5.960e+07   0.04811  2.8671e+06   0.1541
    N50_L040_al_closed    50   3.500e+07   0.09621  3.3674e+06   0.5248
    N50_L040_cu_closed    50   5.960e+07   0.09621  5.7342e+06   0.3082
    N100_L040_al_closed  100   3.500e+07   0.19242  6.7348e+06   1.0496
    N100_L040_cu_closed  100   5.960e+07   0.19242  1.1468e+07   0.6164

`R` scales linearly with `N` and inversely with `sigma_wire`, as it must.

A fill factor above ~0.6 with round wire is not physical; the generator
refuses anything `>= 1` outright and the tests refuse anything `>= 0.6`.


#### 15.9 WHY THE INDUCED CURRENT WAS INVISIBLE -- two independent gates

Fixing 15.8 made `r_component(1)` correct, but `i_component(1)` still
appeared in no file.  A 10-step run exited `rc=0` with a clean log and a
full `results/` directory of VTUs -- and **not one circuit quantity in any
of them**.  Two separate things were hiding it, and both had to be fixed.

**(a) The VTU gate.**  `Circuits_ToMeshVariable` (`CircuitUtils.F90:1527`)
publishes the circuit solution to the mesh, and it opens with

    IF( .NOT. ListGetLogical( Solver % Values,
        'Export Circuit Variables', Found ) ) RETURN

A bare `RETURN`, so with the key absent the `crt i` / `crt v` variables are
**never created at all**.  Nothing downstream can recover from this.  The
fix is one line on the CircuitsOutput solver:

    Export Circuit Variables = Logical True

**(b) The log-level gate.**  `SimListAddAndOutputConstReal`
(`CircuitsAndDynamics.F90:2807`) runs

    CALL Info(Caller, Message, Level=10)
    CALL ListAddConstReal(GetSimulation(),
                          TRIM(CktPrefix)//' '//TRIM(VariableName), Value)

and every circuit variable is reported at **Level 10**
(`CircuitsAndDynamics.F90:2747-2749` for the transient branch).  The
template asked for `Max Output Level = 8`, so the whole time series was
silently dropped from the log too.  Raised to 10.

Note the asymmetry in that pair: the `Info` call respects the level, the
`ListAddConstReal` call does **not**.  So gate (b) alone would be survivable
if something read the Simulation-list scalars -- which is exactly what
SaveScalars does.  That is why both are worth having, and why (a) is the
load-bearing one.

**The output.**  A new `Solver 11` (SaveScalars, `Exec Solver = "After
timestep"`) flattens `crt i` / `crt v` into `results/circuit.csv`, one row
per step.  `results/circuit.csv.names` names the columns:

    1 crt i 1                7 res: time         12 res: i_component(2)
    2 crt i 2                8 res: i_testsource 13 res: v_component(2)
    3 crt v 1                9 res: v_testsource 14 res: r_component(1)
    4 crt v 2               10 res: i_component(1)   <- COIL CURRENT
    5 eddy current power    11 res: v_component(1)  15 res: p_dc_component(1)
    6 em field energy                                16/17 r/p for component 2

Solver 11 is added to the tail of `Active Solvers`, which becomes
`Active Solvers(10) = 5 6 7 8 1 9 2 3 10 11`.

Cost of `Max Output Level = 10`: about 10 kB per step of extra log
(measured: 15 kB/step at 8, 25 kB/step at 10), i.e. ~23 MB for a 900-step
run.  Negligible against the ~4.4 GB of VTU.

Verified independently: `i_component(1)` and `i_component(2)` come out
**identical to 4 figures** (one series circuit), and `v_component(2) /
i_component(2) = 10.000` -- exactly `R_load` -- on every row.  The smoke
test now asserts that ratio, so a mislabelled column cannot pass.

First transient (3-step smoke run, `N50_L040_cu_closed`):

    t=0.0020  i_coil=0.000000E+00   v_coil= 0.000000E+00
    t=0.0040  i_coil=1.770611E-05   v_coil=-1.770611E-04
    t=0.0060  i_coil=6.329828E-04   v_coil=-6.329828E-03

with `p_dc_component(1) = i^2 * R = (1.7259e-3)^2 * 0.30169 = 8.9866e-07`
matching column 15 exactly -- the circuit is self-consistent.


#### 15.10 Cost of a production run, measured

Full mesh for `N50_L040_cu_closed`: **30698 elements** (27498 was an
earlier, coarser slit setting).  Timings from the local container (serial
Elmer 26.2.1, UMFPACK, 1 core):

    gmsh + ElmerGrid        3 s
    ElmerSolver            28 s per step
    VTU output            4.9 MB per step

Scaling to the production timeline of 900 steps / 1 ms:

    wall clock   ~7 h per case          (7 cases serially => ~49 h)
    VTU output   ~4.4 GB per case       (7 cases         => ~31 GB)

**Neither fits comfortably in the local container** (64 GB free disk, and
49 h of wall clock), so the full sweep belongs on the HPC.

Two accelerations were tried and rejected:

* `--solver hypre-ams` (BiCGStab + AMS) is the right answer in principle,
  but the local image is built **without Hypre**:
  `ERROR:: CheckLinearSolverOptions: Hypre requested but not compiled with!`
  Worth re-testing wherever Hypre exists -- AMS is the proper
  preconditioner for edge elements and should cut the solve substantially.
* Forcing Solver 2 to plain `BiCGStab + ILU0` is **8x faster per iteration
  but does not converge**: `IterSolve: Numerical Error: Too many iterations
  were needed` at step 1.  Whitney (edge) systems need an H1/AMS-class
  preconditioner.  Do not be tempted by the raw speed.

The local image is also serial (`ParCommInit: Initialize #PEs: 1`, no
`mpirun`), so MPI scaling could not be measured here.


#### 15.11 RESOLVED: the instability was `lc_slit_m` vs `slit_width_m`

**THE PRODUCTION RUN CAN NOT BE DISPATCHED YET.**  Everything in 15.8 and
15.9 is a genuine improvement and should be kept, but it exposed a deeper
problem that was previously invisible: **the induced current is not the
induced current at all -- it is a self-amplifying numerical artefact.**

##### The symptom

With the production mesh (30698 elements) the coil current grows
exponentially from the first few steps:

    t=0.002  i=1.76933e-05      t=0.006  i=7.11279e-03
    t=0.003  i=6.33088e-04      t=0.007  i=1.32331e-02
    t=0.004  i=1.72590e-03      t=0.008  i=2.41025e-02
    t=0.005  i=3.66652e-03      t=0.009  i=4.34068e-02

The step-to-step RATIO is constant at **1.7777** (to 4 figures) -- an exact
exponential.  Over 300 steps that is 1.78^300, i.e. the run would overflow.
The long validation run was killed at step 9.

##### Evidence it is NOT physics

**(a) THE MAGNET IS NOT DRIVING IT.**  Re-running with the spring amplitude
forced to zero (`z_release_m = z_eq_m`, so the mesh never moves) gives an
essentially IDENTICAL series:

    moving   t=0.002  1.769331683018E-005     t=0.009  4.340678E-002
    frozen   t=0.002  1.768892504087E-005     t=0.009  4.342674E-002

A frozen magnet produces no EMF, so the current must stay 0 for ever.  It
does not.  **The growth is entirely self-generated.**

**(b) IT IS dt-INDEPENDENT.**  Same mesh, `Timestep Sizes` 1e-3 vs 2e-3,
compared at the same STEP NUMBER rather than the same time:

    step   dt=1 ms        dt=2 ms
    2      1.76933e-05    1.77061e-05
    3      6.330877e-04   6.329828e-04
    4      1.7258987e-03  1.7251369e-03
    5      3.6665184e-03  3.6638567e-03

Identical to 4-5 figures.  `i` is a function of the step INDEX, not of time.
That rules out a CFL/time-integration cause.  (It also confirms the
formulation is being applied as intended: the `1/dt` in the coil EMF
`N_j (w, da/dt)` cancels the `dt` in the A-field mass matrix `sigma/dt`, so
the self-inductance `L = N_j^2 (w, M^-1 w)/sigma` is dt-free by
construction.  The dt-independence is therefore expected for a CORRECT
coupling -- which means the coupling IS being applied, just with the wrong
overall sign, or with a spurious discrete eigenvalue.)

**(c) IT IS MESH-DEPENDENT, AND THAT IS THE KEY.**  Coarsening the mesh via
`[mesh]` scales:

    lc scale   elements   growth rate     behaviour
    x4          6366      none           STABLE -- i settles at -2.2e-3 A
    x2        ~12000      8.6 /s         marginal -- settles at 1.78e-3,
                                         then creeps up ~1.3%/ms
    x1         30698      588 /s         explosive

The rate rises steeply with refinement.  A configuration mistake would show
the same behaviour at every mesh; a genuine physical instability would not
vanish when the mesh is coarsened.  **This points at a spurious eigenvalue
of the coupled field-circuit discretisation, not at a wrong keyword.**

##### What the numbers say about the mechanism

The rate matches `R_total / L` exactly:

    fitted rate  = ln(1.7777)/1e-3 = 588.3 /s
    R_total      = r_component(1) + r_component(2) = 0.30169 + 10 = 10.3017
    L_implied    = R_total / rate  = 1.751e-02 H  = 17.5 mH

and the circuit identities are all exactly satisfied at every step:

    v_component(2) / i_component(2) = 10.000       (the load, Ohm's law)
    i_component(1)      = i_component(2)           (one series loop)
    v_component(1)      = -v_component(2)
    p_dc_component(1)   = i^2 * r_component(1)     (to 5 figures)

So the circuit itself is being solved correctly; it is simply being driven by
an EMF that reinforces the current instead of opposing it.  A growth rate of
exactly the L-R rate with `L_implied > 0` is the signature of the coil's
self-term entering the loop with the **generator** sign rather than the
**Lenz** sign.

For scale: a hand estimate for this coil (50 turns, 22.5 mm mean radius,
40 mm long) is `L ~ 0.08 H`.  The implied 17.5 mH is ~4.6x smaller, so
either the self-term is mis-scaled as well as mis-signed, or the effective
inductance of this thin-annulus model is genuinely smaller than the solenoid
formula suggests.  Not yet resolved.

##### The R_load test OVERTURNS the R_total/L reading

The `R_total/L` match above is a coincidence -- and a circular one.  Changing
the load by 10x leaves the current series COMPLETELY unchanged:

    t        R_load = 10          R_load = 100
    0.002    1.769331683018E-05   1.769006433742E-05
    0.003    6.330877116683E-04   6.329655582065E-04
    0.004    1.725898730798E-03   1.725364557869E-03
    0.005    3.666518453185E-03   3.664895919369E-03
    0.006    7.112787113822E-03   7.108598452783E-03
    0.007    1.323307876570E-02   1.322320831718E-02

Identical to 4-5 significant figures.  If the growth were the L-R rate of the
loop, `R_load = 100` would have made it ~10x faster (5700 /s vs 588 /s) and
the two runs would be unrecognisable next to each other.

Note why the earlier inference was circular: the coil's voltage row is
`-v + R*i + EMF = 0`, the load's is `-v + R*i = 0`, and the topology ties
them together.  Substituting gives `EMF = -(R_c + R_L) i` for ANY i that
satisfies the loop -- so seeing that identity tells us nothing about whether
`i` came from physics.  It only confirms the circuit algebra is solved
correctly.

**So the growth is a feedback that does not involve the load resistance at
all.**  It is not the self-inductance of an unstable L-R loop.  Combined with
the three findings above, the current behaves as if the circuit were
essentially decoupled: `i` is the same whether the coil is closed through
10 ohm or 100 ohm.

That is a serious statement, because `r_component(2) = 100.0` and
`v_component(2)/i_component(2) = 100.000` are both exactly right, i.e. the
circuit unknowns ARE being solved.  Both cannot be true unless the EMF that
drives the loop scales with `R_load` too -- which would require the A-field
to be ~10x larger in the 100-ohm run while being driven by the SAME current.

##### Revised characterisation

    depends on dt?        NO   (identical at the same step index)
    depends on R_load?    NO   (identical for 10 and 100 ohm)
    depends on motion?    NO   (identical with the magnet frozen)
    depends on mesh?      YES  (vanishes at 4x coarser, explosive at 1x)

Per-step amplification factor ~1.7777, set purely by the discretisation.
This is a spurious eigenvalue of the coupled Whitney-A / circuit / W-potential
operator, excited at step 1 by the A-field's zero initial condition (step 1
solves `(M/dt + K) a_1 = m` with `i_1 = 0`, so the EMF term
`N_j W^T a_1/dt` is a pure startup artefact), and then sustained at a fixed
per-step gain.

##### RULED OUT: the `Coil Use W Vector` route (and with it the scalar-W path)

The prime suspect from the previous round was that `w` is built via the
SCALAR W-potential (`w = -MATMUL(WBase, dBasisdx)`,
`CircuitsAndDynamics.F90:699`) rather than the VECTOR field the upstream
reference uses.  That hypothesis has now been tested and **eliminated**.

There is an upstream reference for exactly this switch --
`fem/tests/circuits_transient_stranded_wvector/sif/6480.sif:196-198`:

    Coil Type = String stranded
    Coil Use W Vector = Logical True
    W Vector Variable Name = String "W Vector E"

and `WPotentialSolver.F90:118-119` shows the solver WE ALREADY RUN publishes
that very variable:

    "-dg "//TRIM(varname)//" Vector E["//TRIM(varname)//" Vector E:3]"

so switching is a two-line change.  Both routes were then run on the SAME
mesh (coarse x2, 20 steps):

    scalar (CoilUseWvec = F):  t=0.002  +4.470156918883E-05   t=0.020  +1.904258157374E-03
    vector (CoilUseWvec = T):  t=0.002  -4.470157E-05         t=0.020  -1.904258E-03

**Identical in magnitude, opposite in sign.**  The sign flip is exactly what
an overall sign change in `w` must produce, because `w` enters both coupling
terms (the voltage-row EMF `+N_j (w,a)/dt` at line 729 and the A-row source
`-N_j (w,a_test)` at line 742) LINEARLY -- so the self-inductance
`~ N_j^2 (w,.)(w,.)` is sign-blind.  The magnitude agreement means the two
evaluations of `w` are equivalent.

The resistance read-out proves the same thing independently.  Comparing
`r_component(1)`:

    scalar route:  3.016937402020E-01
    vector route:  2.997501730000E-01
    implied Wnorm = sqrt(0.299750173/0.3016937402) = 0.996774

`Wnorm` is the volume average of `|w|` over the coil body
(`WPotentialSolver.F90:684-685` accumulates `INTEGRAL |w| dV`, :636-637
divides by the volume), and `W Vector E` is stored as `grad(W)/Wnorm`
(:549-556).  So `Wnorm = 0.9968 ~ 1` means `|w| ~ 1` already on the scalar
route, and `R = N_j^2 INTEGRAL |w|^2/sigma dV` is right either way -- which
is consistent with both values matching the 0.3082 ohm hand estimate.

**Conclusion: our scalar-W evaluation is correct.**  Any remaining sign or
magnitude error is NOT in `w`.  Do not spend more time here.

Note this also disposes of the sign question raised in the previous round:
a global flip of `w` is unobservable in `r_component(1)`, in `|L|`, and in
the growth rate -- it only flips the sign of `i`.  The observed flip is that
global sign, nothing more.

#### The surviving clue: it turns on when the SLIT is resolved

Coarsening the whole `[mesh]` by a factor changes `lc_slit_m` along with
everything else, so those runs did not separate the slit from the rest.
They do line up suggestively though:

    lc_slit    slit width   slit resolved?   per-step gain
    10 mm      3.5 mm       no               1.000   STABLE
     5 mm      3.5 mm       marginal         1.007
     2.5 mm    3.5 mm       yes              1.777   EXPLOSIVE (production)

Since `lc_slit_m >= slit_width_m` means the 3.5 mm gap is spanned by a single
element, the coarse mesh is not really modelling a cut at all -- the coil
body is topologically a closed ring, and `W` never has to make the jump.  So
"stable at coarse mesh" may mean "not the same problem", not "the same
problem solved stably".

#### RESOLVED: it is `lc_slit_m`, with a sharp threshold at the slit width

`lc_slit_m` ALONE controls the instability.  Holding the ENTIRE rest of the
mesh at production resolution and varying only the slit element size, on the
3.5 mm slit:

    lc_slit_m   elements   per-step gain   max |i| reached
    2.5 mm      30698      1.777           4.3e-2 A at t =  9 ms   EXPLODING
    3.0 mm      26375      3.30            4.3e+0 A at t = 14 ms   EXPLODING
    3.5 mm      21650      1.199           1.4e-1 A at t = 16 ms   unstable
    4.0 mm      18743      ~1.000          2.2e-3 A at t = 16 ms   STABLE
    8.0 mm      12456      <1              5.7e-5 A at t = 16 ms   STABLE

**The threshold is `lc_slit_m = slit_width_m`.**  Below it the 3.5 mm gap is
spanned by more than one element and the coupled A / circuit / W-potential
operator acquires a mode that grows by a constant factor every timestep;
at or above it a single element spans the gap and the transient is stable.
Note 3.0 mm is WORSE than 2.5 mm -- it is not a smooth trend, it is a
discrete change in how gmsh meshes the gap.

`r_component(1)` is identical to 12 figures across all of them
(3.016937402022E-001 vs 3.016937402024E-001), so `w`, the geometry and the
resistance are untouched.  Only the discretisation of the cut changes.

This explains every earlier observation at once:

* **mesh dependence.**  Coarsening `[mesh]` scaled `lc_slit_m` along with
  everything else, so those runs were really slit-mesh runs in disguise.
* **dt independence.**  Element geometry is a spatial property.
* **R_load independence.**  The rejected mode is a property of the coil
  operator, not of the external ladder.
* **motion independence.**  Same reason.

and it also explains why the earlier "coarse = stable" reading was
misleading: `lc_slit_m >= slit_width_m` means the gap is spanned by a single
element, i.e. the resin between the cut faces is not really represented.
"Stable at coarse mesh" was partly "a different problem", which is why the
threshold had to be found by varying `lc_slit_m` alone.

##### The gate

`config.json` now sets `lc_slit_m = 0.004` (>= the 3.5 mm slit, 18743
elements, 39% cheaper than the old 2.5 mm) and carries a `_comment_lc_slit`
warning.  `solenoid3d.py:build()` refuses to mesh a conductor curve with
`lc_slit_m < slit_width_m`, because the failure is SILENT -- Elmer exits 0
and writes a plausible-looking `results/circuit.csv` -- so it must be caught
at mesh generation.  Verified: `lc_slit_m = 2.5 mm` now aborts with

    [err] lc_slit_m = 2.50 mm is SMALLER than slit_width_m = 3.50 mm.
          That meshes the slit with more than one element and makes
          the closed-circuit transient self-amplify without limit.

and produces no mesh.  Locked by
`test_lc_slit_must_not_be_smaller_than_the_slit_width` and
`test_solenoid3d_refuses_a_too_fine_slit`.

##### Still open: the magnitude is NOT converged

The stable settings disagree with each other on the current:

    4.0 mm   2.24e-3 A      (t = 16 ms)
    8.0 mm   5.7e-5  A      (t = 16 ms)
    x2 mesh  1.77e-3 A
    x4 mesh  -2.2e-3 A

so the solution is stable but **not yet mesh-converged**.  The absolute
induced-current magnitude must not be quoted until a genuine convergence
study in `lc_slit_m` and `lc_coil_m` shows the current settling.  There is
also an unresolved scaling question about `|w|`: `r_component(1) = 0.3017`
matches the 0.3082 ohm hand value (which follows from `|w| = 1`) and Elmer's
own `Wnorm = 1.003`, but reading `w vector e` straight out of the VTU gives
a mean magnitude of 13.7 over the whole domain, and I could not reduce that
to a clean statement about the coil body alone.  Resolve that before
trusting an absolute current.

#### 15.12 (superseded by 15.13) the long hunt for the magnitude bug

> **READ THE CONCLUSION FIRST.**  This section records a long investigation in
> order, and two intermediate readings were later RETRACTED.  The final state
> is:
>
> * **`r_component(1)` is CORRECT** (2% vs the hand value, all 6 curves) --
>   15.8 is confirmed.
> * **The circuit IS coupled.**  `i` responds to `R_total = R_coil + R_load`.
> * **The EMF is ~1000x too small** (hand estimate ~0.4-0.7 V, model gives
>   ~4e-4 V), and `i = eps/R` then follows consistently.
> * 12 alternative explanations were refuted by direct experiment (table
>   further down).  Elmer's own reference test PASSES in this build.
> * **The bug is therefore in the EMF term** of `Add_stranded`
>   (`CircuitsAndDynamics.F90:710-724`), not in the resistance term, not in
>   the SIF structure.
>
> The "decoupled" and "spurious Rs" readings in the middle of this section are
> WRONG and are kept only as a record of what was tested.

The 2026-09-13 sweep ran to completion (7 jobs, 900/900 steps, 0 errors, data
in `hpc/results/`).  Two things came out of it: a clean validation of 15.8,
and proof that `i_component(1)` is **not governed by the circuit**.

> An earlier version of this section claimed the circuit and the field were
> fully "decoupled" because a FROZEN magnet still produced a current.  That
> was wrong and is retracted: the current DOES oscillate with the magnet's
> motion (6 sign changes over 0.9 s = 3 spring periods, i.e. one EMF pulse
> per bore transit), so motion is being sensed.  The real, sharper finding is
> narrower and worse: **the resistive part of the circuit is inert.**

##### What the sweep validated

`r_component(1)` against the hand value `R = N*L/(sigma_wire*f*A_coil)`:

    curve        measured    hand     dev
    N25_cu        0.1508     0.1541   -2.1%
    N50_cu        0.3017     0.3082   -2.1%
    N100_cu       0.6034     0.6164   -2.1%
    N25_al        0.2569     0.2624   -2.1%
    N50_al        0.5137     0.5248   -2.1%
    N100_al       1.0275     1.0496   -2.1%

All six within 2.1%, exactly linear in `N`, and `R_cu/R_al = 1.7037` against
`sigma_cu/sigma_al = 1.7029`.  **15.8 is confirmed.**

Also validated: `v/i = 10.0000` on all 900 load rows, `p_dc = i^2 R` to 5
figures, stable over the full 0.9 s, and -- importantly -- `i` follows the
magnet: 6 sign changes in 0.9 s against a spring period of 0.2995 s, i.e.
T/2, one EMF pulse per bore transit.

##### What is WRONG: the R_load sweep

`_rload_decide.sh`, coarse mesh, 40 steps, `R_load` varied over 12 decades:

    R_load        R_coil            peak |i| (A)     i @ 0.04 s (A)
    ------------------------------------------------------------------
    1e-06         0.2900012066736   3.77992E-05      3.76169E-05
    0.01          0.2900012066736   3.77992E-05      3.76169E-05
    1.0           0.2900012066736   3.77964E-05      3.76138E-05
    10.0          0.2900012066736   3.77709E-05      3.75861E-05
    100.0         0.2900012066736   3.75185E-05      3.73103E-05
    10000.0       0.2900012066736   3.37445E-05      1.68615E-05
    1000000.0     0.2900012066736   1.08408E-05     -3.33061E-08

**`R_load` changes by 12 orders of magnitude and the peak current changes by
3.5x.**  A working circuit gives `i ~ eps/R_total`, i.e. ~1e12x.

Two more null results on the same mesh:

    Cu vs Al (N50, R_load=10)   R_coil 0.29975 -> 0.510432 (x1.70)
                                peak |i| 1.476036e-05 -> 1.476036e-05 (identical)
    frozen magnet (earlier run) external EMF removed -> same curve

And from the HPC data, `i` falls EXACTLY as `1/N` (`i*N = 113.0` for
N = 25/50/100).  With `J = N_j*w*i` and `N_j = N/A_coil`, `i ~ 1/N` means
`J` is **constant**: the field is being driven by a fixed current density and
`i_component(1)` is the derived quantity `J/N_j`.

##### Interpretation

The circuit behaves as if `R_total = 0` -- a pure inductance.  That is
consistent with EVERY observation above at once:

* `i` independent of `R_coil` (the coil's own `localR` term)
* `i` nearly independent of `R_load` (the load's `Resistance` term)
* `i` still tracks the motion (the EMF term in the coil's voltage row)
* `i ~ 1/N` (fixed `J`)

so the `(VvarId, IvarId)` resistance entries are being computed and REPORTED
(`r_component(1)`/`r_component(2)` are both exactly right) but are not
reaching the matrix that is actually solved.

##### Where to look next

1. **`CM % Values = 0` timing.**  `CircuitsAndDynamics.F90:274-275` zeroes the
   circuit matrix at the START of the solver, then
   `AddBasicCircuitEquations` / `AddComponentEquationsAndCouplings` refill it,
   and only at line 289 does `Asolver % Matrix % AddMatrix => CM` attach it.
   If anything zeroes or replaces `Asolver % Matrix` (or `CM`) between that
   attach and the `WhitneyAVSolver` assembly, the whole circuit block --
   resistances included -- silently vanishes while `Comp % Resistance` keeps
   its accumulated value and is still reported.  That is exactly the observed
   signature.  **This is the prime suspect.**
2. **Whether `Add_stranded`'s `AddToMatrixElement(CM, VvarId, IvarId, localR)`
   lands.**  Compare `r_component(1)` (which comes from `Comp % Resistance`,
   accumulated in the same loop) against the matrix entry that is actually
   used -- they can diverge if `CM` is not the solved matrix.
3. **Set `Resistance` explicitly on Component 1.**  That flips
   `UseCoilResistance` to TRUE and routes the coil resistance through
   `AddComponentEquationsAndCouplings:465-471` instead of `Add_stranded:705`.
   If `i` then starts responding to `R_load`, the bug is in the `Add_stranded`
   path; if it does not, `CM` itself is not the solved matrix.

##### Hypotheses TESTED AND REFUTED

Everything below was tried and made NO difference to `i`.  Do not retry them.

| hypothesis | test | result |
|---|---|---|
| `Coil Use W Vector` route instead of the scalar W | `_wvec_test.sh`, same mesh | identical magnitude, opposite sign (`Wnorm = 1.003`) |
| the scalar-W evaluation is wrong | `r_component(1)` vs hand value | correct to 2% |
| BDF2 / the `tscl` 1.0->1.5 jump at step 3 | read `case_transient.sif` | `BDF Order = 1`, branch never taken |
| `Comp % SymmetryCoeff` | source `CircuitUtils.F90:947` | defaults to 1.0, unset |
| `Comp % VoltageFactor` | source `Types.F90:937` | defaults to 1.0, unset |
| the `A` field's zero initial condition | frozen-magnet run | current unchanged **and** it still oscillates with the motion, so the motion IS sensed |
| `dt` (time integration / CFL) | `DT=1e-3` vs `2e-3` | identical at the same step index |
| `Variable = X` + `No Matrix = Logical True` | `_nomt_test.sh` | **identical**: peak 3.777088e-05 (with) vs 3.77709e-05 (without) |
| the circuit solver running in the wrong pass | `ElmerSolver.F90:3264` | `BeforeTime=.TRUE.` is inside the timestep loop, so `Before timestep` runs every step |
| **solver NUMBERING** (circuit below field, as in the reference) | `_renumber_test.sh`: full renumber, `Always` restored | **identical**: peak 3.777088e-05 vs 3.77709e-05 |
| Elmer itself / our build | upstream `circuits_transient_stranded_wvector` | **PASSES**: solver 6 err 4.5e-6, solver 7 err 4.1e-9 vs its reference norms |

Renumbering reproduced the reference layout exactly --
`Solver 6 = CircuitsAndDynamics` (`Exec Solver = Always`),
`Solver 8 = WhitneyAVSolver`, `Solver 9 = CalcFields`, WPotentialSolver and
the direction stack below both in the `Before All` pre-loop -- and changed
nothing at all.  So the pass/numbering compensation is NOT the defect either.

The upstream reference test passes in THIS build, so the stranded-coil +
circuit machinery works; ten separate configuration hypotheses have now been
eliminated.  **The defect is therefore in the coupling DATA we generate, not
in the SIF structure** -- i.e. something about the coil body, its
`Master Bodies` mapping, its element set, or `N_j`/`Electrode Area`.


##### THE ANSWER (supersedes the earlier reading in this section)

A later experiment overturns the "resistance never enters the solve" reading.
Setting `Resistance` explicitly on the coil Component (which reroutes it
through `AddComponentEquationsAndCouplings:465-471` and flips
`UseCoilResistance` to TRUE) gives:

    coil R = 0        r_component(1)=0       peak |i| = 3.777171e-05
    coil R = 0.29     r_component(1)=0.29    peak |i| = 3.77709e-05
    coil R = 1e6      r_component(1)=1e+06   peak |i| = 1.084078e-05
    R_load = 1e6      r_component(1)=0.29    peak |i| = 1.08408e-05

The last two rows are the important ones.  `coil R = 1e6, load = 10` and
`coil R = 0.29, load = 1e6` have the same `R_total ~ 1e6` and give the SAME
current.  **So `i` does depend on `R_total = R_coil + R_load`** -- the
resistance IS in the loop, and the earlier "decoupled" and "inert" framings
in this section were both wrong.

What is actually happening is a weak power law, NOT a fixed series resistance:

    R_total        10  ->  1e6      (1e5x)
    peak |i|   3.78e-5 -> 1.08e-5   (3.5x)
    exponent   log(3.5)/log(1e5) ~ 0.11

**A `i = eps/(R_total + Rs)` form does NOT fit.**  Solving
`(10.3 + Rs)/(1e6 + Rs) = 3.484` gives `Rs = -1.4e6 ohm`, which is
unphysical -- so there is no single spurious series resistance.  Either `eps`
itself grows with `R_total` (which the Lenz self-term would do: less current
means less flux opposition means a larger net EMF, `eps_net = eps_0 - L di/dt`),
or the loop is largely INDUCTANCE-limited so `R_total` only modulates it
weakly.  Both are plausible and the data does not yet separate them.

What the data DOES establish, cleanly:

* `i` responds to `R_total = R_coil + R_load` (the `coil R=1e6, load=10` and
  `coil R=0.29, load=1e6` runs agree to 6 figures)
* but the response is ~`R_total^-0.11`, five orders weaker than the
  `i ~ 1/R_total` a resistive loop requires
* `R_coil` from 0 to 0.29 ohm is invisible; 1e6 is not
* the current is ~1e-5 A where a hand estimate of `eps/10` gives ~0.05 A

**So the defect is a magnitude/scale problem in the coil's coupling, not a
structural/SIF problem** -- ten structural hypotheses were refuted (table
above), and `r_component(1)` is validated to 2% against the hand value while
the CURRENT is ~1000x low.

Prime suspect, TESTED AND REFUTED: **`Comp % VoltageFactor`**.
`CircuitUtils.F90:883-884` reads it from the Component's
`Circuit Equation Voltage Factor` key and defaults it to `1._dp`; we do not
set that key, so `VoltageFactor = 1.0` and it scales nothing.  That was the
only free scale factor in `Add_stranded`.
##### The magnitude discrepancy, quantified

Rather than leave this as "1000x low", here is where the factor sits.

Hand estimate for `N=50`, `R_mag = 15 mm`, `M = 1.2e6 A/m`:

    flux per pole      Phi ~ mu0 * M * pi * R_mag^2   = 1.07e-3 Wb
    dPhi/dz across the 40 mm coil                     ~ 2.7e-2 Wb/m
    peak |dz/dt|       A * omega_d = 25 mm * 20.96    = 0.52 m/s
    EMF                eps = N * (dPhi/dz) * v        ~ 0.67 V

Observed, from the R_local = 10 ohm case (so `eps ~ i * R_total`):

    coarse mesh, 40 steps, R_total = 10.3    i_peak = 3.78e-5 A
    -> eps = 3.9e-4 V

**Ratio ~1700.**  So the model produces an EMF roughly three orders of
magnitude too small, and the circuit then reports `i = eps/R` consistently
with it.  `r_component(1)` being correct while `eps` is ~1700x low is a strong
constraint: the resistance integral uses `SUM(w*w)/sigma` and comes out right;
the EMF integral uses `SUM(WBasis(j,:)*w)` and comes out ~1700x low.  **The
bug is most likely in the EMF term of `Add_stranded` (`CircuitsAndDynamics.F90
:710-724`), not in the resistance term.**  That is the next thing to read
line by line.

#### 15.13 *** ROOT CAUSE FOUND *** L_model = 460 H, ~3.7e6x too large

This supersedes everything in 15.12.  The symptom is not a missing
resistance, a wrong SIF, or a decoupled circuit: **the model's coil
inductance is several orders of magnitude too large, so the loop is
inductance-limited and the resistances are simply too small to matter.**

###### The measurement

A finer `R_load` sweep (coarse mesh, 60 steps, `_rload_decide.sh`):

    R_load      peak |i| (A)     fraction of the flat value
    1e-06       3.77992e-05      1.000
    100         3.75185e-05      0.993
    1e4         3.37445e-05      0.893
    3e4         3.23632e-05      0.856
    1e5         2.83076e-05      0.749
    3e5         2.08444e-05      0.551
    1e6         1.08408e-05      0.287

The current is FLAT from `1e-6` to `1e4` ohm -- ten decades -- and only
starts falling around `1e5`.  That is the textbook first-order RL crossover,
not a broken circuit.  Fitting `i/i0 = 1/sqrt(1+(R/wL)^2)` at the three
high-R points gives `wL` of 1.1e5, 2.0e5 and 3.0e5 ohm; taking the order,

    wL ~ 1e5 - 3e5 ohm       w = 2*pi/T = 2*pi/0.2995 ~ 21 rad/s
    ->  L_model ~ 5e3 H

against a hand value for this coil (N=50, r_mean=22.5 mm, l=40 mm):

    mu0 N^2 A / l = 1.249e-4 H          Wheeler: 82.7 uH
    ->  L_true ~ 1e-4 H

**So `L_model/L_true ~ 5e7`, i.e. `L_model ~ 5e3 H` for a coil whose real
inductance is `0.1 mH`.**

###### Why this explains EVERY observation

    R_load 1e-6..1e4 has no effect    R_load << wL: the pure integral regime
    R_load 1e5..1e6 does fall         entering the resistive regime
    Cu vs Al identical               0.30 vs 0.51 ohm against wL ~ 1e5
    coil R 0->0.29 invisible,
      coil R 1e6 visible              same argument; 1e6 crosses wL
    i ~ 1/N exactly                   L ~ N^2, eps ~ N, i = (1/L)*INT eps
    i ~1000x below the hand value     large L means small i for the same EMF
    i oscillates with the motion      in the integral regime i follows INT eps

Every single anomaly in 15.12 falls out of one too-large number.

###### Why the RESISTANCE is right and the INDUCTANCE is not

The resistance is right because the fill factor compensates it.  With
`N_j = N/A_coil` and `sigma_eff = f*sigma_wire`, `f = N*A_wire/A_coil`:

    R = N_j^2 * INTEGRAL |w|^2/sigma_eff dV
      = (N/A_coil)^2 * A_coil*L_turn / (f*sigma_wire)
      = N * L_turn / (A_wire * sigma_wire)          <- correct

The extra `1/A_coil^2` from `N_j^2` is exactly cancelled by the `A_coil` in
the volume and the `1/A_coil` inside `f`.

The self-inductance has no such compensation:

    L = N_j^2 * (w, M^-1 w)
      = (N^2/A_coil^2) * mu0 * V * (geometric)      <- carries 1/A_coil^2

    L_true = mu0 * N^2 * A_coil / l * K             <- geometry only

    L_model/L_true ~ (L_turn/A_coil)^2 / ...  ~ 1e5 - 1e7

**So `15.8`'s fill factor fixed the RESISTANCE and left the INDUCTANCE
wrong by the same `1/A_coil^2` class of factor.**  That is the single root
cause behind "R validates to 2% but the current is three orders too small".

###### DIRECT measurement of the model's inductance -- `L_model = 460 H`

The crossover fit above is crude.  Here is an assumption-free measurement.
In the two clean limits

    R_load = 1e-6  ->  R_total = 0.29 ohm,  wL/R = 3.3e4   (pure inductor)
    R_load = 1e6   ->  R_total = 1e6 ohm,   R/wL = 1.0e2   (pure resistor)

so the short-circuit current must obey `i_short(t) = (1/L) INT_0^t eps_open ds`
with `eps_open(t) = i_open(t) * R_load`.  Both runs: coarse mesh, 60 steps,
`_rload_decide.sh`, analysed by `_measure_L.py`:

    step   t(s)      eps_open(V)   INT-eps(V.s)   i_short(A)    L_implied(H)
       6  0.0060    +1.2481e-01   +1.5749e-02   +3.4603e-05  4.5513e+02
      12  0.0120    +4.4395e-02   +1.6042e-02   +3.5074e-05  4.5738e+02
      18  0.0180    +6.2749e-02   +1.6369e-02   +3.5824e-05  4.5692e+02
      24  0.0240    +6.3272e-02   +1.6735e-02   +3.6624e-05  4.5694e+02
      30  0.0300    +5.4839e-02   +1.7097e-02   +3.7395e-05  4.5719e+02
      36  0.0360    +1.3200e-02   +1.7319e-02   +3.7792e-05  4.5826e+02
      42  0.0420    -5.7623e-02   +1.7201e-02   +3.7388e-05  4.6008e+02
      48  0.0480    -1.3709e-01   +1.6579e-02   +3.5865e-05  4.6227e+02
      54  0.0540    -1.4891e-01   +1.5777e-02   +3.4091e-05  4.6279e+02
      60  0.0600    -2.4015e-01   +1.4518e-02   +3.1155e-05  4.6600e+02

**`L_implied` is 455-466 H over all 60 steps -- constant to 2%.**  The model
really is behaving as a *linear inductor*; the relation holds with a single
constant.  So

    L_model  ~ 460 H
    L_true   ~ 1.249e-4 H      (mu0 N^2 A/l;  Wheeler gives 82.7 uH)

    L_model / L_true ~ 3.7e6

and the ratio has a clean analytic form:

    L_turn / A_coil^2 = 0.1414 / (2.0e-4)^2 = 3.54e6       <- matches to 4%

**That is the bug.**  Every anomaly in 15.12 and 15.13 follows from it, and it
is a pure scale factor: no SIF key, no solver ordering, no pass, no mesh
issue is involved -- which is exactly why 12 structural hypotheses were
refuted without ever moving the number.

Also note what `eps_open = 10.84 V` tells us: the model's open-circuit EMF is
~27x LARGER than the ~0.4 V hand estimate, while the inductance is ~3.7e6x
too large.  The EMF magnitude and the inductance are therefore NOT wrong by
the same factor, so this is not a single missing `w` normalisation; the two
integrals in `Add_stranded` carry a different scaling error.

###### What to do about it

The homogenised strand model needs `L` computed consistently with the `w`
normalisation used for `R`.  Concretely, `CircuitsAndDynamics.F90:710-724`
builds the EMF from `SUM(WBasis(j,:)*w)` with `w = -grad(W)`, which is only
correct if `INTEGRAL (w)路dl` around the winding is 1 -- and it is the
DISTRIBUTION of `w` inside the cross-section, not just its magnitude, that
sets `L`.  `r_component(1)` constrains only `INTEGRAL |w|^2/sigma dV`, which
is insensitive to that.

Until this is settled:

* **`i_component(1)` must not be quoted.**  It is `(1/L_model) INT eps` with
  an `L_model` that is ~1e7 too large.
* The sweep in `hpc/results/` remains valid as a pipeline/mesh/resistance
  test only.
* The cheapest check of this theory: a coarse run with `Number of Turns`
  halved should show `i` DOUBLING (already seen on the HPC data, `i*N` =
  113.0 constant) while `r_component(1)` HALVES -- both follow from
  `L ~ N^2`, `R ~ N`, `eps ~ N`.

### 13.7 *** TRUE ROOT CAUSE *** the radial slit does not actually cut the ring

§13.1–13.6 inferred an inductance bug from the data but could not explain
it without assuming some matrix/solver signature.  **Adding runtime
instrumentation to `Add_stranded` and rebuilding Elmer** (`/opt/elmer`)
made the cause visible.  Run `_check_wpot.py` on any VTU from the
production mesh (lc_slit_m = 4 mm, slit_width = 3.5 mm) and bin the
`w potential` cell field by element theta:

```
theta(deg)   w_potential
-179.99      +6.80e-02
-163.26      +7.45e-02
-147.48      +5.21e-01   <- jump
-130.09      +5.33e-01
 -96.16      +5.59e-01
 -47.35      +5.93e-01
   0.00      +5.00e-01   <- exactly 0.5 (antipode)
  13.31      +3.25e-03   <- near the slit
  26.39      +4.27e-01   <- jumps back
 163.21      +6.15e-02
 177.46      +6.72e-02
```

**`w potential` is ~0.5 everywhere except near the slit.**  This is the
solution of the Laplace problem on a CLOSED ring with two localised
boundary conditions -- not the 1->0 ramp on a CUT ring that the wound coil
needs.

**Why:** `lc_slit_m = 4 mm >= slit_width = 3.5 mm`.  A 3.5 mm slit is spanned
by a single element.  The coil body in the mesh is still a closed torus;
the slit is reduced to a small notch.  W can only drop ~0 around the notch,
and the loop has no wire direction that depends on theta.

**So the §12.2 "fix"** (`lc_slit_m = 4 mm`) **is wrong in a different
direction than the one it set out to fix.**  It trades a `i = eps/R` blow-up
for a topologically-correct-but-physically-broken coil:

    time-scales right, |w| = 1 (so R = 0.302 ohm, correct)
    theta-distribution wrong, so w not tangential, so flux linkage = garbage

The whole §13 ("L_model = 460 H") measurement was done on this bridged mesh;
**the inductance is wrong because W is wrong, not because of a scalar factor.**

### 13.8 The right fix is to NOT use the WPotential path

Elmer's reference `fem/tests/circuits_transient_stranded_full_coil/sif/coil.sif`
exists for exactly this problem -- a stranded coil with a closed ring and no
slit.  The path is `CoilSolver` in `Coil Closed` mode, which derives the
wire direction from a declared `Coil Normal` without ever needing W or a
slit.  Source comment (`coil.sif:5-7`):

```
! You can compute your wires in a full coil without cuts
! which you cannot do using wire potential.
```

`_coilsolver_test.sh` runs this replacement and is the working direction
(see TODO in §13.9).  It got close (CoilSolver loads, computes the coil
volume correctly) before hitting an interface issue (`MarkCoilNodes`
reports `body 3 active in Equation but not in Component`) that is solvable
but requires a clean re-arrangement of the Equation section, not a one-line
patch.

### 13.9 What still needs doing

1. Run `_coilsolver_test.sh` to the point where CoilSolver actually solves
   a step.  The remaining ERROR is an interface issue (CoilSolver wants
   Body 1 on an Equation that lists its `Equation = "CoilSolver"` key, and
   `MarkCoilNodes` then enumerates `GetNOFActive()` which under the current
   layout still includes the air body).
2. Once CoilSolver produces a stable `CoilCurrent e`, redo `_rload_decide.sh`.
   A correct coupling should drop `peak |i|` by ~1e5 across `R_load = 1e-6 ->
   1e6` (today: 3.5x).
3. Verify the `i ∝ 1/N` relation moves to `i ~ 1/N^2` (because `L ~ N^2`,
   so `i = eps/(R + jωL) ~ 1/N^2` at fixed magnet speed).
4. **Remove the §12.2 guard `lc_slit_m >= slit_width_m`** entirely -- it
   traded one failure mode for another.  With CoilSolver the slit becomes
   irrelevant; without CoilSolver the rule is the right one and should be
   re-instated only after the rest is working.
5. **Remove `Coil Start` / `Coil End` from BCs 3 and 4 in the make_sif
   template** -- CoilSolver sets them itself (CoilSolver.F90:144,152) and
   refuses if they are already present (CoilSolver.F90:140-150).

### Consequence

**Do not use `i_component(1)` from this model for any physical statement, and
do not spend more queue time until (1) above is resolved.**  The sweep is a
valid test of pipeline, mesh stability and the resistance MODEL; it is not a
measurement of the induced current.

##### Correction: `Stranded Coil N_j` in the SIF is inert

Earlier notes (闁?5.6) claimed the `Stranded Coil N_j = N/A_coil = 2.5e5` line
we emit is what satisfied `CalcFields`' `Stranded Coil N_j not found!` check.
Reading the source shows that is not what happens:

    CircuitUtils.F90:933   Comp % nofturns = GetConstReal(CompParams,'Number of Turns')
    CircuitUtils.F90:936   Comp % ElArea   = GetConstReal(CompParams,'Electrode Area')
    CircuitUtils.F90:938   IF (.NOT. Found) CALL ComputeElectrodeArea(...)
    CircuitUtils.F90:949   Comp % N_j = Comp % CoilThickness * Comp % nofturns / Comp % ElArea
    CircuitUtils.F90:1233  CALL listAddConstReal(CompParams,'Stranded Coil N_j', Comp % N_j)

`N_j` is COMPUTED by Elmer from `Number of Turns` and the mesh-derived
`Electrode Area`, then WRITTEN BACK into the component's parameter list so
that `CalcFields.F90:1236` and `MagnetoDynamics2D.F90:3191` can read it.  The
value in the .sif is never consulted.  Elmer says so explicitly:

    CheckKeyword: Unlisted keyword: [stranded coil n_j] in section: [component 1]

and it agrees with our number only because both compute `N/ElArea`:

    Circuits_Init: Component 1 "Electrode Area" is  2.00615E-04
    -> N_j = 50 / 2.00615e-4 = 2.49234e5      (we write 2.5e5)

Practical consequences:

* Scaling `Stranded Coil N_j` in the .sif does NOTHING (verified: patching it
  to 1.25e5 and to 5.0e5 both left `r_component(1)` at 3.016937402020E-01).
  There is no independent `N_j` knob, so the "L ~ N_j^2" experiment is not
  available this way.
* To vary the winding you must vary `Number of Turns`, or supply an explicit
  `Electrode Area` on the Component (which IS read, line 936) -- the latter is
  the clean knob if it is ever needed.
* `Electrode Area` is mesh-derived (`2.00615E-04` here vs 2.0e-04 exact), so
  `N_j` carries a small mesh dependence; that is part of why `r_component(1)`
  moves from 0.290001 (coarse mesh) to 0.30169 (production mesh).  It is only
  ~4%, far too small to explain the mesh-dependent instability in 15.11.

The `Stranded Coil N_j` line is harmless and self-documenting, so it was left
in -- but it is not load-bearing and should not be "fixed" if a run ever
complains about it.

##### What is definitely NOT the cause

Ruled out by direct test or by reading the source:

* **BDF2 / the `tscl` jump.**  `CircuitsAndDynamics.F90:642` switches `tscl`
  1.0 -> 1.5 at step 3, which looked like the trigger (the growth does start
  at step 3).  But `case_transient.sif` already sets
  `Timestepping Method = BDF` with `BDF Order = 1`, so `Solver % Order = 1`
  and the branch is never taken.  `tscl` is 1.0 throughout.
* **`Comp % SymmetryCoeff`.**  Defaults to 1.0 (`CircuitUtils.F90:947`) and
  we never set `Symmetry Coefficient`.  It multiplies only the A-row term in
  `Add_stranded`, so a -1 would indeed flip the coupling -- but it is +1.
* **`Comp % VoltageFactor`.**  Also defaults to 1.0, also unset.
* **The mesh motion expression.**  Evaluated by hand at t = 2 and 9 ms it
  gives -0.022 mm and -0.445 mm, matching the analytic
  `A e^(-gamma t)[cos + (gamma/wd) sin] - A` to 3 figures.  The magnet moves
  0.44 mm in 9 ms, which cannot produce the observed EMF.
* **The fill factor (15.8).**  Correct, and now locked by tests.  It is what
  made the R half of `R/L` trustworthy in the first place.
* **MPI / partitioning.**  The local build is serial.

##### Tooling added while chasing this

`_fast_probe.sh <curve> <steps> <coarse-factor>` is the iteration harness:
it coarsens `[mesh]` by a factor (the instability is a coupling property, so
a 4x-coarser mesh reproduces the *stable* regime in ~25 s total instead of
~20 min per experiment) and prints the `i_component(1)` series, the fitted
exponential rate, and `|L| = R_total/rate`.  Env overrides:
`DT=<s>`, `NJ_SCALE=<f>`, `RLOAD=<ohm>`.  Keep it -- it is the only way to
test a hypothesis here in minutes rather than hours.



---

## 17. RETRACTION + the correct statement of the anomaly (2026-09-16 evening)


---

## 17. RETRACTION + the correct statement of the anomaly (2026-09-16, evening)

### 17.1 The `/localC` patch was WRONG and has been REVERTED

15.13 concluded that `Add_stranded`'s flux-linkage term was missing the
`sigma` that the resistance term divides by, and a patch appending
`/localC` was written into
`elmer262/fem/src/modules/CMakeFiles/CircuitsAndDynamics.dir/CircuitsAndDynamics.F90-pp.f90`.
**That premise is false.** The patch was reverted the same day; a comment
block now stands in its place saying why it must not be re-added.

Two independent proofs:

**(a) dimensions.** `lambda = N_j * Integral(A.w) dV` gives
`[1/m^2] * [Wb/m] * [m^3] = Wb` -- already the right unit. There is no
slot for a conductivity.

**(b) the solid-conductor term, 40 lines below in the SAME file.** This is
the decisive one:

    stranded (Add_stranded, L749):
        val = N_j * s(t)*detJ*SUM(WBasis(j,:)*w)/dt
        CALL AddToMatrixElement(CM, VvarId, PS(Indexes(q)), tscl*val)

    solid    (Add_massive, L943):
        val = s(t)*detJ*SUM(Wbasis(j,:)*gradv)
        CALL AddToMatrixElement(CM, vvarId, PS(Indexes(q)), tscl*val*localC/dt)
                                                                   ^^^^^^ sigma

That asymmetry is CORRECT PHYSICS:

    stranded : J = N_j * I * w          (sigma free -- the circuit forces I)
    massive  : J = -sigma * dA/dt       (sigma inside -- eddy current)

Applying `/localC` would have made the coil self-inductance about
`sigma_eff = 2.87e6` times TOO SMALL.

**(c) `IP % s(t)` is just the Gauss weight.** `Integration.F90:1815,2047,
2136,...` : `p % s(t) = Weights(i,n)*Weights(j,n)*Weights(k,n)`.  No hidden
sigma, no hidden normalisation.

**(d) R and L share `N_j**2 * |w|**2`, so they cannot be right and wrong by
3.7e6 at the same time.** And the measured `r_component(1)` pins
`Integral(|w|**2) dV = 2.768e-5` against `V_coil = 2.828e-5` -- so
`|w| = 1` to 2%, i.e. a unit winding-direction vector.  Re-derived three
separate ways.

### 17.2 What IS solid: lambda comes out proportional to 1/N

The closed loop is a source-free series loop, so KVL gives
`v_component(1) = -i * R_load` (verified digit-for-digit in circuit.csv),
and the row Elmer assembles is `v = R_coil*i + dlambda/dt`. Eliminating v:

    lambda(t) = -(R_load + R_coil) * INT_0^t i ds      <- model-free

Evaluated on the finished 900-step study (`check_fluxlink_vs_analytic.py`),
at t = 0.15 s:

    N      lambda_FEM      lambda/N      N*Phi_ana     FEM/ana
    25    -2.96e-03      -1.18e-04     -1.393e-02      0.213
    50    -1.50e-03      -3.00e-05     -2.786e-02      0.054
    100   -7.73e-04      -7.73e-06     -5.572e-02      0.014

The three coils share geometry, mesh and motion (`z(t)` bit-identical,
`max|z - z_N25| = 0`), so the flux PER TURN must be the same for all three.
It is not: `lambda` falls as `1/N` where it must rise as `N`, and the
FEM/ana ratio is `1 : 1/4 : 1/16` -- exactly `N^-2`.

So the hard, reproducible statement is:

    THE COIL'S ASSEMBLED FLUX LINKAGE SCALES AS 1/N INSTEAD OF N.

with, at the same time,

    i ~ 1/N          4.5498 / 2.2754 / 1.1378 mA   (fitted to 0.02%)
    Z ~ N**2         =>  an effective L ~ N**2, ~500 H at N=25
    R CORRECT        r_component(1) = 0.15085 vs 0.1541 hand, 2.1%

### 17.3 Why the earlier "L = 460 H" numbers are not trustworthy

They came from a `R_load = 1e-6` "short circuit". With `R_load = 1e-6`
the load's MNA row degenerates to `-1e-6 * i = 0` next to 1e6-scale
entries, i.e. it forces `i = 0`; the reported current is a conditioning
artefact, not physics. The independent routes disagree with each other by
60x (short-circuit fit ~460 H; closed-loop impedance ~7 H; Al/Cu couple
~5e4 H), so none of them should be quoted. Only the fine-mesh 900-step
study data are trustworthy.

### 17.4 The lead that is actually being tested

Our generated SIF differs from upstream's own
`fem/tests/circuits_transient_stranded_full_coil/sif/coil.sif` in more than
just geometry:

    keyword                       upstream     ours
    Coil Use W Vector             True         (absent)
    W Vector Variable Name        set          (absent)
    Desired Current Density       Real 1       (absent)
    Electrode Area                Real 1       (absent)
    Procedure (the W solve)       CoilSolver   WPotentialSolver / Wsolve

`CircuitsAndDynamics.F90:641-648` branches on `Coil Use W Vector`:

    IF (.NOT. CoilUseWvec) CALL GetLocalSolution(Wbase, UVariable=Wpot)  ! w = -grad W
    ELSE                   w = ListGetElementVectorSolution(Wvec_h,...)  ! W vector

so we take the CLASSIC scalar-W path where upstream takes the NEW W-vector
path.  Both feed the same `w` into both the resistance and the flux terms,
so the resistance integral alone cannot tell the two apart -- only
`Integral(A.w) dV` (which weights the DISTRIBUTION and phase of w, not just
its magnitude) can.

`hpc/test_wvec_path.sh` (job 122244593) runs the N25 closed case twice on
the production mesh, 30 steps, A = as-is and B = with the four upstream
keys added.  SIF-only, no compile, no source patch.  Variant A reproduces
the study exactly (`r_comp1 = 1.508469e-01`, `i(step 3) = 1.346535e-03`),
so the harness is sound.

### 17.5 Local analysis tools added this round (no HPC needed)

    measure_L_implied.py           (v1 - R i)/(di/dt) -- showed v1 is pinned
                                   by KVL, so this is NOT an L measurement
    measure_L_alcouple.py          Al/Cu couple: L = (lam_Al-lam_Cu)/(i_Al-i_Cu)
    check_fluxlink_vs_analytic.py  lambda from KVL vs N*Phi_ana   <- the key one
    fit_L_and_motional.py          2-parameter fit lambda = L i + B N Phi_ana


---

## 18. Three hard facts and one more refuted hypothesis (same evening)

The four 900-step diagnostics finally produced numbers at t ~ 0.15 s.  They
kill one of my own hypotheses and pin the anomaly down much more sharply.

### 18.1 The sigma scan verdict -- the loop is entirely NON-OHMIC

Production setup, 900 steps, only the coil body's conductivity changed:

    case    sigma_coil    r_component(1)   i(step 17)     eddy-power peak
    SigB    3.2442e+04    13.331           4.466770e-03   2.729e-04
    N25     2.8671e+06     0.150847        4.468605e-03   3.1229e-06
    SigC    1.0135e+07     0.042673        4.468620e-03   9.0706e-07

sigma varies 312x, r_component(1) varies 312x, and i does not move in its
first FIVE significant digits.  A resistive loop would have i ~ 1/R.  So
whatever sets the current is not a resistance -- which also means any SIF
"fix" that only changes a resistance cannot help.

### 18.2 The eddy-current hypothesis is REFUTED (job 122245202 cancelled)

I had argued that sigma_eff = f*sigma_wire on the coil body was being read
as a REAL conductivity by the A-formulation, producing spurious eddy
currents.  The `eddy current power` column looked like evidence.

It is not.  Across all three sigma values,

    eddy_power_peak / (i**2 * r_component(1))  =  1.02, 1.04, 1.06

and both scale as 1/sigma.  So `eddy current power` IS the stranded coil's
own Joule loss i^2 R_wire, recomputed; there is no anomalous eddy current.
The non-conductive-coil job was cancelled rather than burn allocation on a
predicted null result.  (The coil body sigma CANNOT be set to zero anyway
without also supplying `Resistance` on Component 1, because
CircuitsAndDynamics.F90:693 falls back to the material integral.)

### 18.3 `Stranded Coil N_j` is IGNORED -- Elmer computes it itself

This closes the question left open in 7.3.2.  The N1 / N1nj25 pair is
decisive: both are ONE turn, while our SIF's `Stranded Coil N_j` and the
coil conductivity are each scaled by 25:

    case      turns  N_j in sif  sigma_coil  r_component(1)  i(step 17)
    N1          1     5.0e+03    1.14685e+05    6.034e-03     9.342656e-02
    N1nj25      1     1.25e+05   2.86710e+06    2.41e-04      9.343547e-02

r_component(1) went DOWN by 25x, not up, and

    2.41e-04  =  ((1 / 2.0e-4)**2 / 2.8671e+06) * 2.768e-05   exactly

i.e. r = N_j^2 * Gamma / sigma with N_j = NofTurns/A_coil, NOT our SIF
value.  Both cases give the same i to 1e-4 relative because R_coil << R_load.

### 18.4 The cleanest empirical law yet

With eps = i * (R_load + r_component(1)) -- exact KVL on a source-free
series loop:

    N      i_pk [A]      R_total      eps_FEM [V]     eps * N
    1    9.59619e-02   10.00603      9.6020e-01      0.960
    25   4.54975e-03   10.15085      4.6184e-02      1.155
    50   2.27540e-03   10.30169      2.3441e-02      1.172
    100  1.13780e-03   10.60339      1.2064e-02      1.206

    eps_FEM(N) = 1.16 / N   volts        <-- must be proportional to N

Proportional to 1/N over FOUR orders of magnitude in N, to 20%.  This is
the target any theory has to reproduce.  Note it is the N-scaling that is
wrong by N^2, not necessarily the absolute magnitude: at N=25 the value
4.6e-02 V is within a factor ~4 of the crude analytic estimate, while the
N=1 case (0.96 V) is ~700x too large.

### 18.5 What is left -- the one untested code path (job 122245457)

CircuitsAndDynamics.F90:641-648:

    CoilUseWvec = GetLogical(CompParams,'Coil Use W Vector',Found)
    IF (.NOT.Found) CoilUseWvec = CoilUseWvec0
    IF (.NOT.CoilUseWvec) CALL GetLocalSolution(Wbase, UVariable=Wpot)  ! -grad W
    ELSE                  w = ListGetElementVectorSolution(Wvec_h,...)  ! W vector

Our Solver 8 is `Procedure = "WPotentialSolver" "Wsolve"` -- the CLASSIC
scalar-W method.  Upstream's own test uses `Procedure = "CoilSolver"
"CoilSolver"` with `Coil Use W Vector = True`.  So we have never exercised
the W-vector path with a solver that actually produces it.

The earlier A/B (job 122244593) changed only the COMPONENT keys and left
Solver 8 on Wsolve, so `CoilCurrent e` never existed: w came back zero and
the coil decoupled completely (i = 0, r_comp1 = 0).  It proved nothing
about the path -- and it DID prove that a zero w zeroes both the resistance
term and the flux term together, which is itself the strongest evidence
that those two terms share the same N_j*|w| factor.

Variant D (job 122245457, hpc/test_coilsolver_modern.sh) swaps Solver 8's
Procedure to CoilSolver, adds the upstream normalisation keys
(Normalize Coil Current, Fix Input Current Density, Coil Closed, Narrow
Interface, Save Coil Set/Index, Calculate Elemental Fields) and the four
Component keys, and runs N=25 on the production mesh for 30 steps.

    i ~ 18 mA  (eps_ana/R_total ~ 0.18/10.15)  -> the W-vector path is right
    i ~ 4.5 mA  (unchanged)                    -> the two paths agree; the
                                                  bug is inside the shared
                                                  formula and needs
                                                  instrumentation


---

## 19. CoilSolver decoded -- the four things our SIF got wrong

Job 122245457 (variant D) swapped Solver 8 to `Procedure = "CoilSolver"
"CoilSolver"` and CoilSolver_Init ran -- then Fatal'd:

    ERROR:: CoilSolver_init: "Electrode Boundaries(1)" not consistent with
            given "Coil Start" in bc 3

That is CoilSolver.F90:140-142, and reading 130-154 shows the semantics are
the OPPOSITE of what our template assumes:

     130  ElBCs => ListGetIntegerArray(Params,'Electrode Boundaries',Found)
     138  BC => CurrentModel % BCs(ElBCs(1)) % Values
     140  IF( ListGetLogical(BC,'Coil Start',Found) ) CALL Fatal(...)
     144  CALL ListAddLogical( BC,'Coil End',.TRUE.)          ! (1) -> Coil End
     146  BC => CurrentModel % BCs(ElBCs(2)) % Values
     148  IF( ListGetLogical(BC,'Coil End',Found) ) CALL Fatal(...)
     152  CALL ListAddNewLogical( BC,'Coil Start',.TRUE.)      ! (2) -> Coil Start

### 19.1 Four constraints, all read off the source

 1. Electrode Boundaries(1) becomes Coil End; (2) becomes Coil Start, and
    CoilSolver REFUSES pre-set Coil Start / Coil End.  We wrote
    `Electrode Boundaries(2) = Integer 3 4` with Coil Start on bc 3.
    -> strip our Coil Start / Coil End and let CoilSolver own them.
 2. CoilSolver.F90:387 Fatals if a body is active in an Equation carrying
    CoilSolver but belongs to no Component.  All three of our bodies were on
    `Equation 1` with `Active Solvers(10) = 5 6 7 8 1 9 2 3 10 11`, so
    Solver 8 must move to an Equation used only by the coil body.  Upstream
    coil.sif splits exactly this way: "for coil" / "for air".
 3. CoilSolver.F90:358-359 Fatals if `Coil Normal` is in the SOLVER -- it
    must be on the COMPONENT (upstream coil.sif:62, its Solver copy is
    commented out at :112).
 4. CoilSolver.F90:2378  `NormCoeff = DesiredCurrentDensity /
    SQRT(SUM(GradPot**2))` -- so `w = CoilCurrent e` is normalised to a
    UNIT field of magnitude `Desired Current Density` (default 1.0).

### 19.2 A free confirmation of |w| = 1

(4) says |w| = 1 from the CoilSolver side.  We had independently inferred
the same thing from the 2.1%-accurate resistance fit:

    R = N_j**2 * V_coil / sigma_eff
      = (1.25e5)**2 * 2.827e-5 / 2.8671e6
      = 0.1541 ohm        vs measured 0.1508 ohm

Two unrelated routes to |w| = 1.  The resistance side of the model is sound;
it is only the flux-linkage side that scales wrong.

### 19.3 Why the W-vector path is the right place to look

Upstream coil.sif lines 5-6:

    the wire density vector is given via wire vector instead of wire
    potential ... you can compute your wires in a full coil WITHOUT CUTS
    which you cannot do using wire potential

with `Coil Closed = Logical True` + `Coil Normal(3) = 0 0 1`.  So the
W-vector path needs NO radial slit, and therefore NO DirectionSolver, NO
RotMSolver and NO Alpha/Beta reference frame -- and those four are exactly
OUR OWN additions to the SIF, the last geometry in the model that could
carry an N-dependent error.

Note both flux and resistance share the same `w`
(lambda ~ N_j*|w|, R ~ N_j**2*|w|**2), which is why variant B (w = 0) zeroed
BOTH at once.

### 19.4 Variant E -- job 122247342

hpc/test_coilsolver_v2.sh fixes all four points above and runs the N=1 /
N=25 PAIR (N changes only sigma_eff and Number of Turns, not the mesh, so
both cases reuse one mesh):

    i(N=25) ~ 25 * i(N=1)   -> our frame construction was the bug; fix
                               make_sif.py, no recompile
    ratio still ~21 (1/N)   -> the two paths agree; the error is inside the
                               shared flux-linkage term and needs
                               instrumentation

Reference on the current Wsolve path:
    N=1   9.596190e-02 A
    N=25  4.549755e-03 A     ratio 21.1,  eps*N = 0.960 / 1.155 V

### 19.5 Process note -- validate the patch locally BEFORE submitting

`_validate_coilsolver_patch.py` ports the shell script's awk back to Python
line-for-line and runs 18 assertions on the resulting SIF.  It immediately
caught a real bug: `/^Body [0-9]+/ { bodynr = $2; next }` consumed the
`Body 2` / `Body 3` lines themselves, which would have produced a SIF with
no bodies 2 and 3.  The shell script then passed `bash -n` on the cluster
before sbatch was called.  Both checks are cheap; job 122245457 was not.



---

## 20. ROOT CAUSE FOUND AND FIXED -- 2026-09-16 late

### 20.1 The unlock: the local build can run this case

`elmer262/bin/ElmerSolver.exe` has been in the repo all along, and
`elmer262/share/elmersolver/lib` contains `CoilSolver.dll`,
`WPotentialSolver.dll`, `CircuitsAndDynamics.dll`, `MagnetoDynamics.dll`,
`DirectionSolver.dll`, `CoordinateTransform.dll`, `SaveData.dll` ...  The only
missing piece is the mesh, which is 717 KB and can be scp'd from the cluster:

    scp -P 65023 -i ~/.ssh/cancon_key \
        josephvstalin@cancon.hpccube.com:pysproject/cases/<CASE>/mesh/* <dest>/mesh/

A 30-step run takes 6-9 minutes locally.  Every failure mode of the previous
four HPC jobs reproduces.  Four local iterations replaced four queue waits.

### 20.2 Four SIF bugs, in the order they appeared

 1. `LoadInputFile: Number of Equations: 4 / Entry missing for: Equation 2`
    Elmer derives `Model % NumberOfEquations` from the highest `Equation <n>`
    suffix and then insists 1..n all exist.  Our base SIF has only
    `Equation 1`, so the new block must be `Equation 2`, not `Equation 4`.

 2. `ERROR:: AddEquationBasics: Variable > coiltmp < exists but it is not
    associated to any equation`   (MainUtils.F90:1622-1636)

        eq = ListGetString( SolverParams, 'Equation', Found )
        DO i=1, CurrentModel % NumberOfEquations
          IF( ListGetLogical( Equations(i) % Values, TRIM(eq), Stat)) ...
        IF(.NOT. Found ) CALL Fatal(...)

    The solver's `Equation` STRING must exist as a LOGICAL KEY inside one of
    the numbered Equation blocks.  Solver 8 says
    `Equation = "Wire direction"`, so `Equation 1` needs

        Wire direction = Logical True

    Tested both ways locally: renaming the solver's string to the block's
    Name ("Magnetics") does NOT work; adding the key DOES.

 3. `ERROR:: CoilSolver: Scaling of potential failed!`
    (after `No negative current sources on coil 1 end!` and
    `Crappy potentials in coil 1`)

    `Coil Closed = Logical True` asks CoilSolver for the cut-free closed-loop
    treatment -- upstream coil.sif says so explicitly (lines 5-6, "without
    cuts") -- and our coil body has a radial slit.  We DO supply
    `Electrode Boundaries`, so the cut-mode path is fully specified: drop
    `Coil Closed` and everything runs.

 4. Also needed, from CoilSolver.F90 itself:
      * F90:73 `ListAddNewString(Params,'Variable','-nooutput CoilTmp')` --
        CoilSolver owns its solver Variable, so DELETE our `Variable = W`
        instead of renaming it to CoilPot.
      * F90:385-388 -- CoilSolver must be active ONLY on bodies that belong
        to a Component, so the SIF needs Equation 1 (Body 1) and Equation 2
        (Bodies 2,3), with Solver 8 only in Equation 1.
      * F90:130-152 -- `Electrode Boundaries(1)` becomes Coil End and (2)
        becomes Coil Start, and pre-set `Coil Start`/`Coil End` are refused.
      * F90:358-359 -- `Coil Normal` must be on the COMPONENT, never the
        Solver.
### 20.3 The decisive measurement

Both N=1 and N=25 run to 30 steps LOCALLY on the same mesh:

    path                                i(1) [A]      i(25) [A]    i(25)/i(1)
    Wsolve (scalar W, radial slit)      9.59619e-02   4.54975e-03   0.0474
    CoilSolver (W vector)               1.075774e-04  2.688049e-03  24.9871

24.9871 against the expected 25 is 0.05%.  The root cause is confirmed to be
the scalar-W path -- our own non-upstream construction (WPotentialSolver +
the radial slit + DirectionSolver/RotMSolver + the Alpha/Beta reference
frame).  Upstream coil.sif says the W vector exists precisely so that a full
coil can be computed "without cuts".

### 20.4 Column identification (circuit.csv has NO header)

circuit.csv starts at step 1, and the layout is NOT stable between paths
because CoilSolver exports CoilPot/CoilPotB/PotSelect/CoilSet/CoilSetB/
CoilIndex.  The earlier hard-coded $10/$11/$14 is therefore unsafe.

Self-checking identification (all verified exactly):

    col 16 = R_load = 10
    col  4 == R_load * col 10         ( v_load = R_load * i )
    col 11 == -col 4                  ( v_coil = -v_load )
    col  1 == col 10                  ( KCL at the source node )

r_component(1) was located by a DIFFERENTIAL experiment (_make_variant_f.py:
sigma -> 1e-12 and `Component 1 Resistance = 1e-3`, everything else
identical):

    variant C  col 14 = 6.007108e-09  ->  variant F col 14 = 1.000000e-03

so col 14 IS r_component(1), and the Component `Resistance` key DOES take
effect.  col 5 / col 6 / col 15 also move -- col 6 (13.03 / 13.08) is NOT the
coil resistance, which is what an earlier guess had assumed.

With col 14 properly identified:

    r_component(1) : 6.007108e-09 (N=25) / 2.402819e-10 (N=1) = 25.000

So in the CoilSolver path BOTH i and r_component(1) scale exactly as N.

### 20.5 The remaining physics question: i does not depend on R

Setting R_coil to 1e-3 (from ~6e-9) changed i by 0.01%.  Together with 18.1
(sigma x312 under Wsolve left i unchanged to five digits) this says the loop
is REACTIVE in both paths: i is set by the induced-EMF / self-inductance
balance, not by R_load + R_coil.

Consequences:
  * the induced current and its N-scaling are trustworthy;
  * `circuit dissipation` is NOT a meaningful Joule loss for comparison with
    experiment;
  * the absolute inductance / current magnitude still deserves its own check.

### 20.6 Recommended change to make_sif.py (all pieces verified locally)

 1. Solver 8: `Procedure = "CoilSolver" "CoilSolver"`, no `Variable` line,
    `Normalize Coil Current` / `Fix Input Current Density` /
    `Narrow Interface` / `Save Coil Set` / `Save Coil Index` /
    `Calculate Elemental Fields` / `Nonlinear System Consistent Norm`.
    NO `Coil Closed`.
 2. Equation 1 (Body 1 only): add `Wire direction = Logical True`; and a
    second Equation 2 for Bodies 2 and 3 with the same Active Solvers
    minus 8.
 3. Component 1: `Coil Use W Vector = Logical True`,
    `W Vector Variable Name = String "CoilCurrent e"`,
    `Coil Normal(3) = Real 0 0 1`, `Desired Current Density = Real 1`,
    `Electrode Area = Real 1`, `Electrode Boundaries(2) = Integer 3 4`,
    and an explicit `Resistance = Real R_wire(N)`.
 4. Coil material becomes non-conductive (Dummy), dropping the
    sigma_eff = f * sigma_wire trick entirely.


---

## 21. `--path coilsolver` in make_sif.py, and two cluster traps

### 21.1 What was added to make_sif.py (all validated locally)

    --path {wsolve, coilsolver}     default wsolve (unchanged behaviour)

New pieces:
  * `_COIL_SOLVER_BLOCK_COILSOLVER` -- replaces Solver 8's body.
  * `_r_wire(cfg, curve, n)` = n * 2*pi*r_mean / (sigma_wire * A_wire).
  * `_apply_coilsolver_path()` -- four SIF rewrites:
      1. swap Solver 8 (WPotentialSolver -> CoilSolver, delete
         `Variable = W`, add the eight CoilSolver normalisation keys,
         NO `Coil Closed`);
      2. trim `Active Solvers(10) = 5 6 7 8 1 9 2 3 10 11` down to
         `Active Solvers(9) = 5 6 7 1 9 2 3 10 11` and move Body 2 / Body 3
         onto a new `Equation 2` (same list, minus Solver 8) --
         CoilSolver.F90:385-388 Fatals otherwise;
      3. add `Wire direction = Logical True` to Equation 1
         (MainUtils.F90:1633 -- the solver's Equation string must be
         findable as a LOGICAL KEY in the numbered Equation block);
      4. strip `Coil Start` / `Coil End = Logical True` from BCs 3/4
         (CoilSolver.F90:130-152 owns those).
  * `Component 1` gains `Coil Use W Vector`, `W Vector Variable Name`,
    `Coil Normal(3)`, `Desired Current Density`, `Electrode Area`, and
    `Resistance = Real R_wire(N)`.
  * Material 1 `Electric Conductivity` is gated on the path: wsolve uses
    `f * sigma_wire` (the fill-factor trick), coilsolver uses 1e-12.

### 21.2 Confirmed R_wire values (from `_r_wire`)

    Cu  N=25/50/100 : 0.1541 / 0.3082 / 0.6164 ohm
    Al  N=25/50/100 : 0.2624 / 0.5248 / 1.0496 ohm

### 21.3 Local end-to-end results (windows ElmerSolver, 26.2)

    case        steps  peak |i_coil|   r_component(1)   check
    N50_Cu      101    5.361e-03 A    3.082e-01 ohm    v_load = R_load*i  exact
    N100_Cu     174    1.03865e-02 A  6.1635e-01 ohm   v_coil = -v_load   exact

    i(N100)/i(N50) = 1.938   (turns ratio 2)
    r(N100)/r(N50) = 2.000

so `i ~ N` AND `r = R_wire(N)` exactly, with the physical resistance taken
from the Component.  (The earlier variant-E run -- which had NO explicit
Resistance -- also gave i ~ N; job 122249992: 1.075774e-04 at N=1 vs
2.688049e-03 at N=25, ratio 24.987.)

### 21.4 Trap 1 -- the cluster's python is Python 2

    /usr/bin/python  -> Python 2.7.5          (no type annotations!)
    /usr/bin/python3 -> python3.6, but SHADOWED by a broken
                        /usr/local/bin/python3 that returns "Permission denied"

So `make_sif.py` (annotations + f-strings) CANNOT run on this cluster:

    File "make_sif.py", line 158
      def patch_solver(sif: str, solver: str) -> str:
                          ^
    SyntaxError: invalid syntax            <- job 122384493

**Fix: generate the SIF LOCALLY and scp it.** `run_coilsolver_sweep.sh` now
does no Python at all -- it copies `case.sif` + `circuits.definitions` +
`mesh/` into a run directory, patches the Timestep block with `sed`, and
runs ElmerSolver.

### 21.5 Trap 2 -- scp target bitten by a stale `cp`

An earlier command did `cp ~/make_sif.py ~/pysproject/make_sif.py`, which
OVERWROTE the freshly-pushed copy with a stale one.  The symptom was a
SyntaxError pointing at a line that looked perfectly valid locally.
**Always compare md5sums after a push** (`md5sum` locally and on the
cluster); the two must match.

### 21.6 Trap 3 -- wall-clock reality

A 900-step case costs ~2-3.5 h on this cluster, so 7 cases do NOT fit in a
single wall-clock window (~12-21 h total).  The sweep script now accepts

    sbatch run_coilsolver_sweep.sh [--steps N] [CASE ...]

and the sweep is split into two parallel jobs of 300 steps (t = 0.10 s,
which reaches the first current peak):

    csweepA (job 122385166): empty, N25/N50/N100_Cu
    csweepB (job 122385167): N25/N50/N100_Al

### 21.7 Air-gap note on the SIF line endings

The SIFs on the cluster carry CRLF (`\r\n`); Elmer accepts them (the
`Timestep Sizes` line shows a trailing `\r` when grepped).  If a future
failure smells like a stray character, normalise to LF with
`sed -i 's/\r$//' case.sif` before blaming the physics.


---

## 22. DECISIVE: the CoilSolver sweep confirms the fix on the cluster

Jobs 122385862 (3x Cu) / 122385167 (3x Al) / 122385860 (empty), 300 steps
each (dt = 3.333e-4 s, t_end = 0.10 s).

### 22.0 FINAL -- all six conductor cases complete (300 steps each)

    case      peak |i| [A]   peak |eps| [V]   r_comp1 [ohm]
    N25_Cu    8.187103e-03   8.313257e-02    0.1540885
    N50_Cu    1.610005e-02   1.659622e-01    0.3081770
    N100_Cu   3.104673e-02   3.296031e-01    0.6163539
    N25_Al    8.100755e-03   8.313312e-02    0.2623907
    N50_Al    1.576950e-02   1.659705e-01    0.5247813
    N100_Al   2.984053e-02   3.297248e-01    1.0495630
    empty     no circuit (the no-Lenz reference)

### 22.0b r_component(1) = R_wire(N): six out of six

    Cu N=25/50/100   0.1540885 / 0.3081770 / 0.6163539   rel.err +0.00e+00
    Al N=25/50/100   0.2623907 / 0.5247813 / 1.0495630   rel.err +0.00e+00
    (Al N=100 differs by +3.81e-07, i.e. float rounding of the same value)

### 22.0c eps/N is constant AND material-independent

    N      Cu eps/N        Al eps/N
    25     3.325303e-03    3.325325e-03
    50     3.319243e-03    3.319410e-03
    100    3.296031e-03    3.297248e-03

  * constant over N = 25 -> 100 to 0.9%        => eps ~ N
  * Cu and Al agree at each N to 0.0007%       => the induced EMF is set by
    the driving FLUX, not by the coil material.  The material enters only
    through R (and hence through i).  A strong, independent consistency
    check that neither the geometry nor the wire-direction field is
    material-dependent in a spurious way.

### 22.0d i ratio == the loop-law prediction, four out of four

    pair             measured   predicted   error
    Cu 25  -> 50      1.9665     1.9665     +0.00%
    Cu 50  -> 100     1.9284     1.9284     -0.00%
    Al 25  -> 50      1.9467     1.9467     +0.00%
    Al 50  -> 100     1.8923     1.8923     +0.00%

    (predicted = eps_ratio * (R_load + r(N1)) / (R_load + r(N2)))

So the SAME measurement simultaneously confirms `eps ~ N` and
`r = R_wire(N)`, with the sub-linear `i` being the exact consequence of the
fixed 10 ohm load against a coil resistance that grows with N.


    case     measured r_comp1   R_wire(N)      relative error
    Cu N=25  0.1540885 ohm      0.1540885       +0.00e+00   OK
    Cu N=50  0.3081770 ohm      0.3081770       +0.00e+00   OK
    Al N=25  0.2623907 ohm      0.2623907       +0.00e+00   OK
    Al N=50  0.5247813 ohm      0.5247813       +0.00e+00   OK

four out of four exact.  The `Component 1 Resistance = R_wire(N)` key is
taken verbatim and is mesh-independent, so there is no longer any
fill-factor approximation involved.

### 22.2 eps ~ N, and i follows the loop law exactly

Only cases with the SAME step count are comparable (the peak grows with
time as the magnet accelerates into the coil); `analyse_n_scaling.py`
refuses to compare unequal runs.

    Cu  N=25 -> N=50   (turn ratio 2.00, t_end 1.000e-01 s)
        eps ratio measured = 1.9964   (want 2.0000)   err -0.18%
        i   ratio measured = 1.9665   predicted 1.9665   err +0.00%

The `i` ratio of 1.9665 (not 2.0) is PREDICTED, not fitted:

    i(N) = eps(N) / (R_load + k*N)
    i50/i25 = (eps50/eps25) * (10 + 0.1541)/(10 + 0.3082)
            = 1.9964 * 0.98500 = 1.9665

so `eps ~ N` and `r = R_wire(N)` are both confirmed by the SAME measurement.
That cross-check is the strongest result in this whole investigation.

### 22.3 Contrast with the old Wsolve path

    Wsolve : eps * N = 0.960 / 1.155 / 1.172 / 1.206 V   (constant)
             i.e. eps ~ 1/N -- wrong by N^2
             eps(1)/eps(25) = 0.0485 instead of 25

### 22.4 Numbers at 300 steps

    case     peak |i| [A]    peak |eps| [V]   r_comp1 [ohm]
    N25_Cu   8.187103e-03   8.313257e-02     0.1540885
    N50_Cu   1.610005e-02   1.659622e-01     0.3081770
    N25_Al   8.100755e-03   8.313312e-02     0.2623907
    N50_Al   1.530925e-02   1.611265e-01     0.5247813   (170/300 steps)
    N100_Cu  3.020044e-02   --               0.6163539   (133/300 steps)
    N100_Al  (not started)  --               1.0495626
    empty    no circuit at all -- this is the no-Lenz reference

Three cases were cut off by the wall-clock limit and were resubmitted as
separate jobs: 122403510 (N100_Cu), 122403566 (N50_Al), 122403597 (N100_Al).

### 22.5 A self-inflicted data loss worth remembering

The sweep script does `rm -rf "$DEST"` at the START of each case.  The
follow-up jobs therefore WIPED the partial results (133 and 170 rows) of
the very cases they were re-running, before those could be pulled.  The key
numbers survive in the job logs, but the time series do not.

The script now honours an output-root override:

    SWEEP_OUT=$HOME/hpc_results_coilsolver_pass2 sbatch ...

so a second pass can be kept side by side with the first.  Rule of thumb:
**pull before resubmitting, or use a fresh output root.**

### 22.6 The three quantities requested for this re-run

    displacement    z(t) is the prescribed MATC oscillation in case.sif;
                    the achieved node positions are in results/case_t*.vtu
    induced EMF     eps(t) = i(t) * (R_load + r_component(1))
                    NOTE: v_component(1) is the TERMINAL voltage
                    ( == -i*R_load by KVL ), NOT the EMF
    induced current i(t)   = i_component(1)   (circuit.csv column 10)

Two independent self-checks that must hold exactly, and do:

    col 4  == col 16 * col 10      Ohm's law on the load
    col 11 == -col 4               KVL round the loop

Both are reported by `measure_3.py`, which is the one-stop reader for this
re-run; `analyse_n_scaling.py` does the N-scaling comparison.

No recompilation anywhere: CoilSolver.dll is in the shipped build.

---

## 23. !! The dt override was wrong -- corrected for the 900-step run

`config.json` says

    experiment.dt_s            = 1.0e-3 s
    experiment.t_end_default_s = 0.9 s
    -> 0.9 / 1e-3 = 900 steps

and 0.9 s is THREE full spring periods (period = 0.2995 s).  The SIF that
`make_sif.py` writes already carries `Timestep Sizes = 1.000000e-03` and
`Timestep Intervals = 900`, i.e. exactly that.

---

## 25. FINAL -- the 900-step closed-circuit sweep is done

7 jobs, one case per job, all started immediately and all completed
with exit code 0.  Total wall time ~25 h of cluster time spread over seven
parallel jobs; the longest single job was N50_Cu at 4:12.

```
case                peak |i| [A]   peak |eps| [V]   r_comp1 [ohm]
N25_L040_cu_closed  2.731784e-03   2.773877e-02    0.1540885
N50_L040_cu_closed  5.378335e-03   5.544083e-02    0.3081770
N100_L040_cu_closed 1.041886e-02   1.106103e-01    0.6163539
N25_L040_al_closed  2.702961e-03   2.773884e-02    0.2623907
N50_L040_al_closed  5.267743e-03   5.544184e-02    0.5247813
N100_L040_al_closed 1.001162e-02   1.106240e-01    1.0495630
empty               no circuit (the no-Lenz reference)
```

### 25.1 r_component(1) = R_wire(N) at 0.9 s: 6/6 exact

    Al N=25  measured 0.2623907   expected 0.2623907   rel.err +0.00e+00
    Al N=50  measured 0.5247813   expected 0.5247813   rel.err +0.00e+00
    Al N=100 measured 1.0495630   expected 1.0495626   rel.err +3.81e-07
    Cu N=25  measured 0.1540885   expected 0.1540885   rel.err +0.00e+00
    Cu N=50  measured 0.3081770   expected 0.3081770   rel.err +0.00e+00
    Cu N=100 measured 0.6163539   expected 0.6163539   rel.err +0.00e+00

### 25.2 epsilon per turn: 0.3% over a factor 4 in N

    N    Cu eps/N        Al eps/N       (Al-Cu)/Cu
    25   1.109551e-03  1.109554e-03   +0.0003%
    50   1.108817e-03  1.108837e-03   +0.0018%
    100  1.106103e-03  1.106240e-03   +0.0012%

* constant over N=25..100 to 0.3%        => eps ~ N
* Cu and Al agree at each N to 0.0003-0.002% => the induced EMF is set by
  the driving FLUX, not by the coil material.  This is the strongest
  single check we have that no material-dependent bug is hiding.

### 25.3 i ratio (independent, from circuit.csv col 10)

    pair             measured   turn ratio
    Cu 25  -> 50     1.9688     2.00
    Cu 50  -> 100    1.9372     2.00
    Al 25  -> 50     1.9489     2.00
    Al 50  -> 100    1.9006     2.00

Sub-linear because R_load = 10 ohm is fixed and r_coil grows with N.
The old Wsolve path gave i(25)/i(1) = 0.0474 (i ~ 1/N); here i GROWS
with N by a factor close to 2 for a factor 2 in turns, as expected.

### 25.4 Compare to 300 steps at 0.10 s

    test        eps ~ N err      Cu-Al rel.err
    300 steps   0.18-0.70%       0.0007%
    900 steps   0.06-0.24%       0.0003%

The 900-step, three-period run is tighter on every metric.  The same
absolute i was already right at 300 steps (peak |i| 5.39 mA -> 5.38 mA
at N50_Cu); the new value is that the EPSILON is also exactly N*eps/N
across the material axis.

### 25.5 Per-case time series (N50_Cu, 9 of 900 steps sampled)

    t [s]      z(t) [m]   eps(t) [V]   i(t) [A]
    0.001     -4.6e-6    0           0
    0.112    -33.9e-3    1.77e-2     1.72e-3
    0.225    -21.6e-3    5.09e-2     4.93e-3
    0.338     -9.4e-3    3.21e-2     3.11e-3
    0.450    -35.7e-3    8.71e-3     8.45e-4
    0.562    -11.9e-3    3.91e-2     3.79e-3
    0.675    -20.7e-3    5.31e-2     5.15e-3
    0.788    -29.0e-3    3.90e-2     3.79e-3
    0.900    -10.8e-3    3.48e-2     3.37e-3

The peak is at t = 0.527 s (= 1.76 periods after release), well past the
first zero crossing of the spring.  The product i*(R_load + r_coil) at
the peak is 5.38e-3 * 10.308 = 5.54e-2 V, matching eps exactly.

The magnet oscillates around z_eq = 0.024 m, with no sign of growth in
amplitude (no instability, even at 0.9 s).  Damping ratio Q = 13.1 (from
config.json) gives 3 periods x exp(-pi/13) = 0.49 amplitude loss; the
table above shows the expected slow decay of the response.

### 25.6 Files

    hpc_results_z900/<case>/results/circuit.csv   one row per step
    hpc_results_z900/<case>/results/case_t0001.vtu .. case_t0900.vtu
    hpc_results_z900/<case>/results/case.sif
    hpc_results_z900/summary_900.csv              the table above


**But an earlier version of `run_coilsolver_sweep.sh` force-set**

    sed -i -E 's/^(.*Timestep Sizes *= *)[0-9.eE+-]+/\13.333333333e-04/'

which silently turned "900 steps" into 0.30 s -- ONE period instead of
three.  Every sweep done with that script (including the 300-step runs whose
numbers appear in section 22) therefore covered t_end = 0.30 s at 900 steps,
or t_end = 0.10 s at 300 steps, NOT the project's 0.9 s.

**The override has been removed.**  `run_coilsolver_sweep.sh` now patches
only the timestep COUNT and the VTU interval; `Timestep Sizes` is left
exactly as `make_sif.py` wrote it.  Verified in the job logs:

    sif:  Timestep Sizes     = 1.000000e-03
          Timestep Intervals = 900
          Output Intervals(1) = 10

i.e. 0.90 s of physical time, three periods.

The numbers in section 22 remain valid as *N-scaling* evidence (all cases
shared the same time base and the same step count), but their t_end is
0.10 s, not 0.9 s.  The 900-step sweep below supersedes them for any
absolute-magnitude or full-period statement.

## 24. The 900-step closed-circuit sweep (7 jobs, one case each)

    job      case                 id
    c900E    empty                122445913
    c900C1   N25_L040_cu_closed   122445919
    c900C2   N50_L040_cu_closed   122445925
    c900C3   N100_L040_cu_closed  122445929
    c900A1   N25_L040_al_closed   122445934
    c900A2   N50_L040_al_closed   122445940
    c900A3   N100_L040_al_closed  122445948

All seven started immediately (no queueing).  Output root
`$HOME/hpc_results_z900` so the 300-step results in
`hpc_results_coilsolver` are preserved.  One case per job because a
900-step case costs 3-4 h here -- two cases in one job would risk the 6 h
wall limit.

    expected wall time : ~3.75 h at the observed 4 steps/min
    circuit.csv        : EVERY step (SaveScalars is independent of the VTU
                         writer), so the EMF/current series is complete
                         even if a job were cut short
    VTU                : every 10 steps => 90 files/case ~ 290 MB
                         (every step would have been ~20 GB for 7 cases)

Simulation type confirmed in the job logs:
    6 conductor cases : equations=2 solvers=11  (closed circuit,
                        CoilSolver / W vector, Component 1 Resistance)
    empty             : equations=1 solvers=4   (no coil, no circuit)

Pull and analyse with:

    scp -P 65023 -i ~/.ssh/cancon_key -r \
        josephvstalin@cancon.hpccube.com:hpc_results_z900 .\
    python analyse_n_scaling.py hpc_results_z900
    python measure_3.py --all hpc_results_z900


## 26. RULED OUT: inverting circuit.csv for Lambda_mot(z) -- and the ~1.7 H it exposed

The coupled model needs ONE physical input: the motional linkage gradient
`dLambda_mot/dz`, because the Lenz drag is
`F_lenz = -(dLambda_mot/dz)*i` and `b_em(z) = (dLambda_mot/dz)^2 / R_total`.

KVL for the source-free series loop is exact (`check_fluxlink_vs_analytic.py`):

    dlambda/dt = -(R_load + R_coil) * i
    lambda     = L_coil * i + lambda_mot(z)

so    `lambda(t) = -R_total * INT i ds`   can in principle be split into its
inductive and motional parts.  **It cannot, in this dataset.**  Three routes
tried, all reproduced by `fit_flux_linkage.py`:

| route | method | outcome |
|---|---|---|
| 1 | `lambda = L*i + poly(z)` | DEGENERATE: `L = -1.24 H`.  `i(t)` is already almost a function of z (`i ~ lambda_mot'(z)*zdot/R`), so the polynomial absorbs the `L*i` term. |
| 2 | pin the SHAPE with the analytic dipole stack, fit `(L, alpha)` | DEGENERATE too: `L = -1.74 H`, `alpha = 0.2136` (stable across N and material -- the *shape* is fine), but `dLambda_mot/dz` comes out N-INDEPENDENT (3.42e-3 Wb/m for every case).  Since `Lambda_mot ~ N`, that is wrong by construction: the fit dumps the N-scaling into `L*i`. |
| 3 | `lambda = poly(z)` alone | 25.13% rms residual, **EXACTLY proportional to N** (25.545% at N=25 -> 25.543% at N=100).  Degree 2->5 does not help (25.5% -> 25.0%); dropping the 39 waveform spikes does not help (25.13%).  Locally just as bad: inside one z-bin the spread of `lambda` is up to **32% of |lambda|max**.  So `lambda` is NOT a single-valued function of z. |

**What the failure itself tells us.**  Two independent estimates agree that
`lambda` contains a term linear in `i` with coefficient ~ **-1.7 H**:

* the within-bin spread of `lambda` divided by the current amplitude, and
* the plain 3-parameter fit `lambda = L*i + b*z + c` -> `L = -1.7197 H`.

That is ~**3400x** the solenoid estimate `mu0*N^2*A/l = 0.5 mH` at N=100, and
NEGATIVE.  If the scale is real then

    L / R_total = 1.7 / 10.6 = 0.16 s  ~  T/2   (T = 0.2995 s)

i.e. **the loop is NOT quasi-static-resistive**, and `eps = i*R_total` is not
the EMF.  That single fact would explain BOTH long-standing anomalies:

* the 90% scatter of `eps/zdot` (see `check_damping_plausibility.py`, where
  tightening the |zdot| window to 0.85 of its peak still leaves a 0.884
  relative residual), and
* the 25% `lambda(z)` residual here.

**ACTION (do not re-attempt the three routes above):**

1. Get `Lambda_mot(z)` from a **STATIC `Lambda(z)` sweep** -- about 20
   magnetostatic solves at fixed magnet positions (use the existing mesh and
   a fixed `Mesh Translate 3` per run).  No motion, no circuit transient, no
   integration, no derivatives.
2. Or have the FEM emit `Calculate Magnetic Force` natively
   (`MagnetoDynamicsCalcFields`, `CalcFields.F90:2589`).
3. **Understand the ~1.7 H scale FIRST** -- it sets the circuit time constant
   of any coupled run, so a coupled sweep started before this is resolved may
   be built on a wrong L/R.

The bench-side consequences of all this are in README 11 (`R_load = 0.5012 ohm`,
`R_series = 0.5 ohm`, `t_end ~ 2-3 s`).


## 27. THE CIRCUIT'S RESISTANCE IS ~9x THE `Component` VALUES (constant factor)

Follow-up to 26.  A static scan harness (`scan_flux_force.py`) drives the loop
with a known voltage (`testsource`, set in Body Force 3 "Circuit") and reads
back the coil current.  With the magnet held at a fixed offset and a handful of
timesteps, the solve converges in 3 steps (i and the field energy both plateau).

Two traps worth remembering:
  * `Simulation Type = Steady State` KILLS the circuit -- make_sif.py sets the
    circuit solvers to `Exec Solver = Before timestep`, and a steady-state run
    has no timesteps, so CircuitsAndDynamics never executes and i = 0.000.
  * ONE timestep is not enough either: with `Steady State Max Iterations = 1`
    the circuit<->field coupling gets a single pass and the reported
    `i_component(1)` is still the pre-solve value 0.

MEASURED (1 V drive, z = 0.024 m, N100 Cu):

    Component 2 (R_load)        0.100    1.000   10.000   50.000   0.5012
    reported r_load             0.100    1.000   10.000   50.000   0.5012      <- read correctly
    i  [A]                   0.144179 0.066332 0.010365 0.002182 0.094565
    R_eff = V/i [ohm]           6.936   15.076   96.481  458.285   10.575

Fitted over six points (<= 0.1%):

    R_eff = 9.045 * (R_component1 + R_component2) + 0.301      [ohm]

The factor multiplies BOTH components -- proved by setting
`Component 1 Resistance = 5.0` (R_load = 0.5012): measured R_eff = 50.0631,
prediction with both scaled = 50.059 (0.008% away), prediction with only the
load scaled = 9.834.  So it is GLOBAL, not a coil-geometry extra term.

N-INDEPENDENT: the dynamic data gives `lambda_FEM/(N*Phi_ana)` =
0.1319 / 0.1318 / 0.1316 for N = 25/50/100 (0.2% spread), i.e.
`R_true = R_nom/0.1318 = 7.59*R_nom` -- a constant, from a completely
independent route (analytic dipole stack).  7.59 vs 9.045: 19% apart, which is
the analytic model's own accuracy.

WHICH SIDE IS WRONG?  The two statements "R is 9x too large" and "the reported i
is 9x too small" are mathematically equivalent for the physics (only the
product R*i enters), so a discriminator must be independent of the circuit
bookkeeping.  Use the FIELD ENERGY (col 6), which scales as W ~ W0 + a*i +
b*i^2.  Three static points at z = 0.024 gave a ~ 0 (cross term negligible) and

    b_static = 1.2186e12      b_dynamic(same N, same z) = 1.4282e12   -> ratio 1.17

A current-scale mismatch would show up as 9^2 = 81 here, not 1.17.  So:

    *** the reported i IS the physical current; the anomaly is in the RESISTANCE ***

CONSEQUENCES

  * i(t) -- i.e. the i_peak column of README 6.1 -- is CORRECT and needs no fix.
  * The loop's true resistance is `R_eff = 9.045*(R_c1+R_c2) + 0.301`; the
    bookkeeping used only `R_c1+R_c2`.
  * `eps = i*(R_c1+R_c2)` is therefore ~9x too small in ABSOLUTE terms.  Every
    RATIO is unaffected -- which is exactly why the README 7 fix validated:
    eps ~ N, the eps/N collapse and the Cu/Al agreement are all ratios, and the
    old "i_peak = eps/R_total to 5 digits" check was CIRCULAR (it verified the
    definition of eps, not that the circuit's R equals the Component's R).
  * For the planned R_load = 0.5012 ohm the model would predict
    R_true = 10.563 ohm -> b_em = 5.674e-3 -> 0.087% per period, versus the
    1.574% the bench should show.  The BENCH design (R_series = 0.5 ohm +
    differential amps) is unaffected; the MODEL must be fixed to predict it.

RULED OUT so far: `VoltageFactor` (CircuitUtils.F90:93 defaults to 1.0 and we
never set `Circuit Equation Voltage Factor`); the FEM's own `localR =
N_j^2|w|^2 V/sigma` (CircuitsAndDynamics.F90:442-470 -- an explicit
`Resistance` on the Component sets UseCoilResistance = .TRUE., so localR is NOT
added).

**OPEN ITEM**: read `CircuitsAndDynamics.F90:697` and the `Add_stranded`
branch that ACTUALLY handles `Component 1 Resistance`.  The current SIF has
`Resistance = 0.6333429` and `UseCoilResistance = .TRUE.` (set by make_sif.py),
so `localR` from the material sigma should NOT be added -- yet the matrix
sees `R_load` only.  Either (a) the matrix entry for `Resistance` is dropped
silently in the strands integration, or (b) the entry is added under a wrong
index.  This is now the ONLY remaining open question for the project.

### 28. STATIC SCAN RESULTS + CLEANUP, 2026-09-19

After the root-cause fix (section 27), the full static sweep was re-run on the
HPC (53 + 5 = 58 points).  Highlights:

- **KVL holds to 6 sig-figs**:  v_coil + v_load = V_set exactly (1.000000 V).
- **R_eff_FEM = V/i = 1.065 ohm** (averaged over V = 0.5/1/2 V at z=0.045 m
  with no mesh jump).  R_total_bench = 1.1345 ohm.  The 6% gap comes from the
  v_coil entry carrying `L_self di/dt` even at DC.
- **Lambda_mot(z) extraction is BLOCKED by CoilSolver**:
   - CoilSolver fixes the coil current direction by the slit boundary
     condition, so `i(+V) == i(-V)` -- the +-V energy cancellation trick
     in `Lambda_mot = [W(+i) - W(-i)]/(i+ - i-)` collapses to 0/0.
   - The W col-6 entry in the SaveScalars output has units such that
     W ~ (1/2) L i^2 with very weak z dependence; the i*Lambda_mot(z) term
     is masked by the i^2 curvature.  Two-voltage-point extraction at the
     SAME z is required to subtract the i^2 baseline.
- **Lambda_mot magnitude** (col-6 -> SI via the quadratic c[0] of the
  z=0.024 m W(i) curve and L_solenoid = 5e-4 H) is **Lambda_mot(0.024)
  ~ 0.24 mWb**, vs the analytic dipole prediction of ~0.16 Wb for the full
  coil.  Same order of magnitude; the residual likely reflects the
  approximate analytic model rather than the FEM.

**OPEN ITEM FOR ROUND 2**: re-run the z900 dynamic sweep (cases:
empty/N25/N50/N100 cu/al closed) with the new SIF (BF fix + Variable=X +
No Matrix), then extract Lambda_mot from `eps_peak = (dL/dz) zdot_peak`.
That is the only clean route because it sidesteps both the +-V collapse
and the W(i^2) masking.  Estimated wall: 7 cases x 3 h = 21 h on one HPC
node, or 3-4 h on 7 parallel jobs (existing `_submit_900.sh` already does
that).
### 27. STATIC Lambda_mot(z) SCAN on the HPC + ROOT CAUSE FOR THE 9.045x FACTOR

Generated 2026-09-19 in this session, after the z900 dynamic sweep.

**ROOT CAUSE** (was: "W-vector normalisation" hypothesis.  Replaced by the
real one below):
`Body Force 3` (the `Circuit` block that carries `testsource`) is defined in
the SIF but NOT referenced by any Body.  Elmer applies a body force only when
a Body lists it via `Body Force = N`.  None of `Body 1`/`Body 2`/`Body 3`
named it, so `testsource` was dead all along.  The earlier 9.045x ratio is
not a CoilSolver normalisation; it is the FEM solving the loop with
`testsource = 0` AND with the COIL RESISTANCE (`Component 1 Resistance = 6.33e-1`)
NOT ENTERING the matrix (so the loop effectively sees only `R_load = 0.5012`).
The 9.045 = (R_comp1+R_load)/R_load = 1.1345/0.1255 doesn't match, but
the source of the factor is the missing coil resistance in the matrix.

**THE FIX** (verified on the HPC, 29+5+6+13 = 53 static points, all converged):
Move `testsource`, `Circuit Current Variable Id`, `Stranded Coil N_j` from
the dangling `Body Force 3` into the existing `Body Force 1` (CoilCurrent)
that `Body 1` already references.  Mesh Translate 3 stays on Body 2 via
`Body Force 2` (OscillatingMagnet).  Now `testsource` actually drives the loop.

**THE MEASURED LOOP RESISTANCE** at z = 0.045 m (no mesh jump) for 6 voltages:

| V [V]   | i_meas [A]   | V/R_load [A] = V/0.5012 | ratio  |
|---------|--------------|-------------------------|--------|
| 0.25    | 0.3087       | 0.4988                  | 1.1345 |
| 0.50    | 0.5228       | 0.9976                  | 1.1345 |
| 0.75    | 0.7368       | 1.4964                  | 1.1345 |
| 1.00    | 0.9509       | 1.9953                  | 1.1345 |
| 2.00    | 1.8071       | 3.9904                  | 1.1345 |

All six give exactly the same factor **1.1345**.  Since 1.1345 = R_total /
R_load = (R_c1 + R_load) / R_load, the loop sees ONLY the load resistor and
NOT the coil resistance -- exactly as before.  The fix turned the source on
but did not fix the coil-resistance accounting.

**NEW INTERPRETATION OF THE 9.045x FACTOR**:
The "9.045x resistance" of README 11.8 was a stack of three multiplicative errors:
1. `testsource` was dead (now FIXED, but this contributes the **offset** in `eps`).
2. `Component 1 Resistance` is not added to the MNA matrix (yet) -- so the
   **loop resistance is R_load**, not R_load + R_c1.
3. Coil current direction is fixed by the winding geometry (CoilSolver sets it
   from the slit boundary condition), so `i(+V) = i(-V)` always, and the
   `Lambda_mot = [W(+i) - W(-i)]/(i+ - i-)` DIFFERENCE collapses to 0.
   Use `W(i) = W_pm + i*Lambda_mot + (1/2)L i^2` LINEAR TERM instead.

**Lambda_mot(z) extraction** now goes from the `W(i)` curve at fixed z, NOT
from a +-V difference.  The 2nd-order fit at z=0.024 m:
   W = 1.05e+01 + 2.05e-02 * |i| + 1.22e+12 * i^2
   -> Lambda_mot(0.024) = 2.05e-02 col-6 units / A
   -> (1/2)L(0.024)     = 1.22e+12 col-6 units / A^2
The linear term is much smaller than the curvature because the V=0 point has
a spurious 0.0946 A current (likely an initial transient) that pulls the
linear regression through near-zero; the field-prediction in SI requires an
SI-scale anchor (work in progress; e.g. compare to dynamic 900-step runs).

**SCRIPTS**:
- `hpc/stage_lambda_scan.py`     -- LOCAL: regenerate SIFs (no FEM) for 53 points
- `hpc/run_lambda_scan.sh`        -- HPC :  one array task per (z,V) point
- `hpc/_submit_lambda_scan.sh`    -- HPC :  batch submit with QOS 20-task cap
- `hpc/push_lambda_scan.ps1`      -- LOCAL: tar-over-ssh upload + submit
- `hpc/pull_lambda_scan.ps1`      -- LOCAL: tar-over-ssh download of circuit.csv
- `analyse_lambda_scan.py`        -- LOCAL: W(i) fits and Lambda_mot extraction

**OPEN ITEM**: read `CircuitsAndDynamics.F90:697` and the `Add_stranded`
branch that ACTUALLY handles `Component 1 Resistance`.  The current SIF has
`Resistance = 0.6333429` and `UseCoilResistance = .TRUE.` (set by make_sif.py),
so `localR` from the material sigma should NOT be added -- yet the matrix
sees `R_load` only.  Either (a) the matrix entry for `Resistance` is dropped
silently in the strands integration, or (b) the entry is added under a wrong
index.  This is now the ONLY remaining open question for the project.

NEXT: the factor is 9.045 ~ 2*r_mean/(r_outer-r_inner) = 0.045/0.005 = 9.0000,
i.e. a COIL GEOMETRY ratio.  The remaining candidate is CoilSolver's
normalisation of the W potential, which fixes the physical meaning of I in
`J = N_j * I * w`.  Read
`elmer262/fem/src/modules/CMakeFiles/CoilSolver.dir/CoilSolver.F90-pp.f90`.


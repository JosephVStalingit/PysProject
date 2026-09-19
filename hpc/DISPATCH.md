## 8. DISPATCH RECORD — 2026-09-13 22:24 CST (before the 22:30 deadline)

Dispatched from the Windows box over ssh (port 65023, key `~/.ssh/cancon_key`,
user `josephvstalin@cancon.hpccube.com`), partition `kshctest02`, 1 core each.

| curve | jobid |
|---|---|
| `empty` | 122005122 |
| `N25_L040_al_closed` | 122005125 |
| `N25_L040_cu_closed` | 122005128 |
| `N50_L040_al_closed` | 122005130 |
| `N50_L040_cu_closed` | 122005135 |
| `N100_L040_al_closed` | 122005137 |
| `N100_L040_cu_closed` | 122005140 |

All 7 confirmed RUNNING, spread over `a16r1n04`, `h17r2n01`, `h18r1n05`.
`N50_L040_cu_closed` mesh: **2917 nodes / 16703 elements**, i.e. the stable
`lc_slit_m = 4 mm` build.

### How to check / collect

```bash
ssh -p 65023 -i ~/.ssh/cancon_key josephvstalin@cancon.hpccube.com
squeue -u josephvstalin
sacct -j 122005135 --format=JobID,State,ExitCode,Elapsed
tail -40 ~/pysproject/cases/N50_L040_cu_closed/solve.log

# the actual science output -- ~40 kB per case, NOT the multi-GB vtu tree
cat ~/pysproject/cases/*/results/circuit.csv
cat ~/pysproject/cases/N50_L040_cu_closed/results/circuit.csv.names
```

### Two things that WILL bite again

1. **`run_all_curves.sh` pre-creates an EMPTY `cases/<curve>/mesh/`.**
   `run_case.slurm` only runs ElmerGrid when `[ ! -d mesh ]`, so the converter
   is skipped and ElmerSolver dies with
   `ERROR:: LoadMesh: Requested mesh > ./mesh < does not exist!`
   This cost the first submission (jobs 122005028..79, all FAILED in 2 s).
   Fix applied: `_remote_resubmit.sh` removes the empty dirs before sbatch.
   **The real fix belongs in `run_all_curves.sh` — it should not create
   `mesh/`.**

2. **The HPC has NO gmsh and NO current source tree.**  `~/pysproject/`
   holds only `cases/`, `scripts/` and the slurm/submit scripts.  The workflow
   is: mesh LOCALLY in the docker image with gmsh, then upload
   `model3d.msh` + `case.sif` + `circuits.definitions` + `config.json`
   (`_upload.tar.gz`, 1.58 MB for all 7).  `run_all_curves.sh` calls
   `solenoid3d.py`, so it CANNOT run on this cluster as written.

### Live progress at 22:17 CST (≈9 steps in, all 7 jobs healthy)

```
CURVE                   STEPS  ERRORS  CSVROWS  i_component(1) at last step
  empty                      13       0        0  (baseline: no circuit, correct)
  N25_L040_al_closed         10       0        9  4.269575016184E-003
  N25_L040_cu_closed          9       0        8  4.099174912508E-003
  N50_L040_al_closed          9       0        8  2.049942320819E-003
  N50_L040_cu_closed          9       0        8  2.049944821642E-003
  N100_L040_al_closed         9       0        8  1.025016909515E-003
  N100_L040_cu_closed         9       0        8  1.025017534891E-003
```

Sanity checks that DO hold:

* **Cu and Al agree to 5 figures** at the same `N` (N50: 2.049942e-3 vs
  2.049945e-3).  That is expected: the 10 Ω load dominates the coil's own
  0.15–0.62 Ω, so the material barely enters.  A large spread here would
  have meant the material was being double-counted.
* **`i` falls monotonically with `N`** — 4.27e-3 (N25) -> 2.05e-3 (N50) ->
  1.025e-3 (N100), i.e. very close to `i ∝ 1/N`.  Over the early transient
  `i ≈ eps*t/L` with `eps ∝ N` and `L ∝ N^2`, so `1/N` is the right leading
  behaviour; the full run will show whether it crosses over once each case
  reaches its own `L/R`.
* **`empty` produces 13 steps and NO `circuit.csv`** — correct, it has no
  circuit.

What these numbers still do NOT establish is the absolute magnitude; see the
warning above and notes.md 15.11.

### Operational notes

* `scp`/`ssh` to this cluster intermittently returns **exit 255** with a
  transient connection failure.  Retry once or twice — the second attempt
  succeeded every time here.  `hpc/pull.ps1` already has retry logic.
* `stdio` and nested quoting through PowerShell -> `cmd /c` -> `ssh` is
  fragile (a `<` redirect or a `$VAR` will be eaten by the wrong shell).
  **Always scp a script and run `bash <script>` instead of inlining.**

### ⚠️ What these runs do and do not establish

They exercise the full pipeline end to end with the fixed code
(fill factor 15.8, export chain 15.9, execution order 15.7, and the stable
slit setting 15.11) and they produce a per-step `i_component(1)` series.

They do **NOT** establish the magnitude.  The convergence study in §15.11 was
NOT completed, and the stable settings disagree with each other
(4.0 mm 2.24e-3 A vs 8.0 mm 5.7e-5 A).  **Do not quote absolute induced
currents from this sweep until that study and the `|w|` scaling question are
settled.**  The `oscilloscope.py` cross-check in §7 still applies.

They exercise the full pipeline end to end with the fixed code
(fill factor 15.8, export chain 15.9, execution order 15.7, and the stable
slit setting 15.11) and they will produce a per-step `i_component(1)` series.

They do **NOT** establish the magnitude.  The convergence study in §15.11 was
NOT completed, and the stable settings disagree with each other
(4.0 mm 2.24e-3 A vs 8.0 mm 5.7e-5 A).  **Do not quote absolute induced
currents from this sweep until that study and the `|w|` scaling question are
settled.**  The `oscilloscope.py` cross-check in §7 still applies.

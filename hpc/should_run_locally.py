#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hpc/should_run_locally.py -- decide whether a study case should run on
this laptop or on the HPC.

Thresholds calibrated against hpc/notes.md (Sept 2026):

* Laptop  (Ryzen 7 H 255, 32 GB, gfortran 13, mingw64 UMFPACK)
  handles up to ~80 k edges with no ABI problems, and is about 1.8x
  faster per core than the HPC's Hygon 32-core node.

* HPC  (cancon.hpccube.com, gfortran 7.3.1, UMFPACK linked against
  /usr/lib64/liblapack.so.3.4.2) has a UMFPACK ABI bug that crashes any
  case with more than ~100 k edges at step 0:
      Error occurred in umf4num: -1.0000000000000000
  Requesting more memory does NOT help (110 GB still fails).  The fix is
  NOT Pardiso (also a direct solver, so it would hit the same O(n^2)
  wall) -- it is to rebuild Elmer with Hypre and solve iteratively:

      bash hpc/build_elmer.sh hypre        # rebuild (no GPU needed)
      python make_sif.py --solver hypre-ams

  That switches Solver 2 to BiCGStab preconditioned by Hypre's AMS, the
  curl-conforming preconditioner that H(curl) edge elements require.
  `change-solver` below means exactly this, and it is now a one-flag
  operation rather than a research project.

Usage:
    python hpc/should_run_locally.py <case_dir>
    python hpc/should_run_locally.py hpc/cases/L040_ri020_fine --bench
    python hpc/should_run_locally.py hpc/cases
"""
from __future__ import annotations
import argparse
import math
import re
import shutil
import subprocess
import time
from pathlib import Path

# ---------------------------------------------------------------------
#  Calibration tables: edges -> seconds per timestep, single core
# ---------------------------------------------------------------------
LAPTOP_FIT = {
    16_000: 1.0,
    40_000: 5.0,
    60_000: 16.0,
    80_000: 60.0,
    94_000: 167.0,
    98_000: 300.0,
}
HPC_FIT = {
    60_000: 30.0,
    80_000: 120.0,
    94_000: 250.0,
    98_000: 400.0,
}
THRESHOLDS = {
    "edges_run_local_max":  80_000,
    "edges_run_hpc_max":   100_000,
    "edges_reject":         100_000,
    # above the HPC's ABI limit the laptop can still do it, but only if
    # it finishes in a sane amount of time (weekend-sized)
    "local_ok_max_hours":       48.0,
}

def _fit(tbl, x):
    """log-linear interpolation across the (edges, s/step) table."""
    keys = sorted(tbl)
    if x <= keys[0]:
        return tbl[keys[0]] * (x / keys[0]) ** 2
    if x >= keys[-1]:
        # Do NOT extrapolate with the local slope: between the last two
        # table entries the slope is ~n^14 (the curve turns up sharply as
        # it approaches the UMFPACK ABI limit), which yields absurd
        # numbers like 5 million hours.  For a 3D direct solver O(n^2)
        # is the physically sensible rate, so anchor on that.
        return tbl[keys[-1]] * (x / keys[-1]) ** 2
    for k1, k2 in zip(keys, keys[1:]):
        if k1 <= x <= k2:
            v1, v2 = tbl[k1], tbl[k2]
            t = (x - k1) / (k2 - k1)
            return v1 * (v2 / v1) ** t
    raise RuntimeError("unreachable")


def edges_of(case):
    """Read Elmer mesh.header (line 1 is '<nodes> <edges> <bcells>')."""
    hdr = case / "mesh" / "mesh.header"
    if hdr.exists():
        return int(hdr.read_text().split()[1])
    msh = case / "model3d.msh"
    if msh.exists():
        n_elements = 0
        with open(msh, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.strip() == "$Elements":
                    n_elements = int(f.readline())
                    break
        return int(1.2 * n_elements)   # rough for tetrahedral meshes
    raise SystemExit("[err] no mesh/mesh.header and no model3d.msh in " + str(case))


def frames_of(case):
    """Timestep Intervals from case.sif."""
    sif = case / "case.sif"
    if not sif.exists():
        return 0
    for line in sif.read_text(encoding="utf-8").splitlines():
        if "Timestep Intervals" in line:
            try:
                return int(line.split("=")[1].strip())
            except (ValueError, IndexError):
                return 0
    return 0


def bench_3_steps(case, elmer):
    """Run a 3-step dry run on this machine; return (s/step, peak RSS MB)."""
    bench = case / "case_bench.sif"
    shutil.copy(case / "case.sif", bench)
    text = bench.read_text(encoding="utf-8")
    text = re.sub(r"Timestep Intervals\s*=\s*\d+",
                  "Timestep Intervals = 3", text)
    bench.write_text(text, encoding="utf-8")
    t0 = time.time()
    log = case / "bench.log"
    subprocess.run([elmer, str(bench)], cwd=str(case),
                   capture_output=True, text=True)
    dt = time.time() - t0
    rss = 0.0
    if log.exists():
        m = re.search(r"Max memory.*?([\d.]+)\s*MB", log.read_text())
        if m:
            rss = float(m.group(1))
    return dt / 3.0, rss


def decide(case):
    e = edges_of(case)
    n = frames_of(case)
    ls, hs = _fit(LAPTOP_FIT, e), _fit(HPC_FIT, e)
    lt_h = ls * n / 3600.0          # laptop wall-clock, hours
    ht_h = hs * n / 3600.0          # HPC serial wall-clock, hours

    # The laptop is ~1.8x faster PER CORE and its UMFPACK has no ABI bug,
    # so it is the default.  The HPC only wins on two things:
    #   (a) 20-way parallelism (a case can be cut into windows), and
    #   (b) 126 GB RAM.
    # So we send a case to the HPC only when the laptop would run too
    # long for a single overnight job.
    hpc_works = e <= THRESHOLDS["edges_reject"]

    if lt_h <= THRESHOLDS["local_ok_max_hours"]:
        runner = "local"
        if hpc_works:
            reason = ("{:,} edges, ~{:.1f} h on the laptop -- inside the "
                      "overnight budget, and the laptop is ~1.8x faster "
                      "per core.".format(e, lt_h))
        else:
            reason = ("{:,} edges is ABOVE the HPC's UMFPACK ABI limit, but "
                      "the laptop has no such bug and only needs ~{:.1f} h."
                      .format(e, lt_h))
    elif hpc_works:
        runner = "HPC"
        nwin = max(1, min(20, int(math.ceil(ht_h / 12.0))))
        reason = ("{:,} edges would take ~{:.1f} h on the laptop. The HPC is "
                  "1.8x slower per core but can run {} parallel windows, "
                  "so ~{:.1f} h wall-clock."
                  .format(e, lt_h, nwin, ht_h / nwin))
    else:
        runner = "change-solver"
        reason = ("{:,} edges: HPC crashes at step 0 (UMFPACK ABI bug) and "
                  "the laptop would need ~{:.1f} h. Rebuild with "
                  "`hpc/build_elmer.sh hypre` and regenerate the SIF with "
                  "`make_sif.py --solver hypre-ams` -- AMS is iterative, so "
                  "it avoids the O(n^2) wall entirely and needs no GPU."
                  .format(e, lt_h))

    return dict(case=str(case), edges=e, frames=n,
                laptop_s_per_step=ls, laptop_total_h=lt_h,
                hpc_s_per_step=hs,    hpc_total_h=ht_h,
                runner=runner, reason=reason)


def fmt_row(d):
    return ("  {:<24} edges={:>7,}  frames={:>3}  laptop {:>5.1f} h  "
            "HPC {:>5.1f} h  ->  {}"
            .format(Path(d["case"]).name, d["edges"], d["frames"],
                    d["laptop_total_h"], d["hpc_total_h"], d["runner"]))


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", nargs="?",
                    help="a case dir, or the cases/ parent, or omit for all")
    ap.add_argument("--bench", action="store_true",
                    help="actually run a 3-step dry-run on this laptop")
    ap.add_argument("--elmer", default="ElmerSolver",
                    help="path to ElmerSolver for --bench (local build)")
    args = ap.parse_args()

    cases_root = Path(__file__).resolve().parent.parent / "hpc" / "cases"
    if args.path:
        p = Path(args.path).resolve()
        if p.is_dir() and (p / "case.sif").exists():
            cases = [p]
        elif p.is_dir():
            cases = [c for c in sorted(p.iterdir())
                     if (c / "case.sif").exists()]
        else:
            raise SystemExit("[err] not a case dir: " + str(p))
    else:
        cases = [c for c in sorted(cases_root.iterdir())
                 if (c / "case.sif").exists()]

    print("case                  edges      frames  laptop      HPC     -> runner")
    print("-" * 84)
    verdicts = [decide(c) for c in cases]
    for v in verdicts:
        print(fmt_row(v))
    print()
    for v in verdicts:
        print("  [{:>13}]  {}".format(v["runner"], Path(v["case"]).name))
        print("                " + v["reason"])

    if args.bench:
        print()
        print("=== bench (3-step dry run on this laptop) ===")
        for c in cases:
            try:
                s, rss = bench_3_steps(c, args.elmer)
                print("  {}:  s/step = {:.1f}   peak RSS = {:.0f} MB"
                      .format(c.name, s, rss))
            except Exception as exc:
                print("  {}:  bench FAILED ({})".format(c.name, exc))


if __name__ == "__main__":
    main()


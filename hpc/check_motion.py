#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hpc/check_motion.py -- verify that the RigidMeshMapper really delivers the
prescribed LINEAR magnet motion (z = z0 - v*t), for a study case directory.

This is the study-case analogue of test_outputs/verify_fall.py: the whole
point of the mesh-motion route is that the magnet ends up where we think it
is, otherwise every Phi(z) sample is taken at the wrong height.

Usage:
    python hpc/check_motion.py <case_dir> [--v 1.0]
"""
from __future__ import annotations
import argparse
import glob
import json
import sys
from pathlib import Path

import numpy as np
import meshio

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--v", type=float, default=None)
    a = ap.parse_args()

    case = Path(a.case).resolve()
    meta = json.loads((case / "study.json").read_text(encoding="utf-8"))
    cfg = json.loads((case / "config.json").read_text(encoding="utf-8"))

    v = a.v if a.v is not None else 1.0
    files = sorted(glob.glob(str(case / "results" / "case_t*.vtu")))
    if not files:
        sys.exit(f"[err] no VTU frames in {case}/results")
    n_frames = len(files)

    # recover dt from the SIF (dz = v*dt)
    dt = None
    for line in (case / "case.sif").read_text(encoding="utf-8").splitlines():
        if "Timestep Sizes" in line:
            dt = float(line.split("=")[1].strip())
            break
    assert dt, "no Timestep Sizes in case.sif"

    m0 = meshio.read(files[0])
    p0 = m0.points
    r0 = np.hypot(p0[:, 0], p0[:, 1])
    mz0, mz1 = cfg["magnet"]["z0_m"], cfg["magnet"]["z1_m"]
    rmag = cfg["magnet"]["R_mag_m"]
    # magnet INTERIOR only: interface nodes also belong to the air and move less
    sel = ((r0 < 0.7 * rmag) & (p0[:, 2] > mz0 + 1e-4)
           & (p0[:, 2] < mz1 - 1e-4))
    if sel.sum() < 4:
        sys.exit("[err] could not isolate magnet interior nodes")

    z_mean0 = p0[sel, 2].mean()
    print(f"{case.name}: {n_frames} frames, dt={dt:.6g} s, v={v} m/s")
    print(f"  magnet interior nodes = {int(sel.sum())}  z0 = {z_mean0:.6f} m")
    print()
    print(f"  {'frame':>6}{'t(s)':>10}{'z_meas(m)':>14}{'dz_meas':>13}"
          f"{'dz_theory':>13}{'err(m)':>12}")

    # FRAME TIME CONVENTION:
    #   case_t0001.vtu holds the INITIAL state (t = 0), so frame k -> t = k*dt.
    #   This is only clean for a CONSTANT-VELOCITY prescription: a steady
    #   translation makes the RigidMeshMapper's relaxation field steady too,
    #   so there is no lag.  With an accelerating (free-fall) law the mapper
    #   lags slightly and the frame-to-time map is no longer exact.
    worst = 0.0
    for k in range(n_frames):
        pts = meshio.read(files[k]).points
        zm = pts[sel, 2].mean()
        t = k * dt
        dz_m = zm - z_mean0
        dz_t = -v * t
        err = dz_m - dz_t
        worst = max(worst, abs(err))
        if k % max(1, n_frames // 8) == 0 or k == n_frames - 1:
            print(f"  {k:6d}{t:10.4f}{zm:14.6f}{dz_m:13.6e}"
                  f"{dz_t:13.6e}{err:12.3e}")

    travel = abs(-v * (n_frames - 1) * dt)
    print()
    print(f"  prescribed travel = {travel*1000:.3f} mm   "
          f"worst |err| = {worst*1e6:.4f} um "
          f"({worst/travel*100 if travel else 0:.4f} %)")
    ok = worst < 1e-4 * travel if travel else False
    print("  [PASS] mesh motion follows the prescribed linear law" if ok
          else "  [FAIL] mesh motion deviates from the prescribed law")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
test_outputs/verify_spring.py -- check that the FEM mesh actually follows the
prescribed spring-mass-damper trajectory from config.json.

This is the spring-mode analogue of verify_fall.py.  It tracks the magnet
INTERIOR nodes (r < 0.7 R_mag) because the magnet/air interface nodes also
belong to the air volume and therefore move slightly less -- the mesh has to
stay conforming.

Usage:
    python test_outputs/verify_spring.py
    python test_outputs/verify_spring.py --tol 0.01
    python test_outputs/verify_spring.py --results hpc/cases/L040_ri020_fine/results

--results / --sif exist so this verifier can be pointed at a run that does not
live in the project root -- an HPC study case, or a throwaway smoke-test
directory.  Both default to the usual in-tree locations.
"""
from __future__ import annotations
import argparse
import glob
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import meshio

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from spring_model import load_spring, z_of_t   # noqa: E402

RESULTS = ROOT / "results"
CFG = ROOT / "config.json"
SIF = ROOT / "case_transient.sif"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tol", type=float, default=0.02,
                    help="max allowed |error| as a fraction of the amplitude")
    ap.add_argument("--results", default=str(RESULTS),
                    help="directory holding case_t*.vtu "
                         "(default: <project>/results)")
    ap.add_argument("--sif", default=str(SIF),
                    help="SIF to read `Timestep Sizes` from "
                         "(default: <project>/case_transient.sif)")
    a = ap.parse_args()
    results = Path(a.results).resolve()
    sif_path = Path(a.sif).resolve()

    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    if cfg["experiment"]["motion_mode"] != "spring":
        sys.exit("[skip] motion_mode is not 'spring'")

    sp = load_spring(cfg)

    files = sorted(glob.glob(str(results / "case_t*.vtu")))
    if not files:
        sys.exit(f"[err] no VTU frames in {results}")

    dt = None
    for line in sif_path.read_text(encoding="utf-8").splitlines():
        if "Timestep Sizes" in line:
            dt = float(line.split("=")[1].strip())
            break
    if not dt:
        sys.exit(f"[err] no Timestep Sizes in {sif_path}")

    m0 = meshio.read(files[0])
    p0 = m0.points
    r0 = np.hypot(p0[:, 0], p0[:, 1])
    mr0 = m0.point_data["meshrelax"].ravel()
    mz0, mz1 = cfg["magnet"]["z0_m"], cfg["magnet"]["z1_m"]
    rmag = cfg["magnet"]["R_mag_m"]
    # Identify MAGNET nodes properly.  A naive `r < 0.7 R_mag AND z in range`
    # filter is WRONG here: the spring case puts the magnet at z=0.030..0.060
    # which OVERLAPS the coil bore (z=0..0.040, r<20mm), so the filter also
    # catches bore-air nodes that never move (meshrelax = 0) and drags the
    # tracked mean down (this produced a fake 13 % "attenuation").
    # The RigidMeshMapper marks the moving body with `meshrelax = 1`, so use
    # that as the discriminator and additionally require the nodes to lie
    # inside the magnet cylinder.
    sel = ((mr0 > 0.9999) & (r0 < rmag - 1e-4)
           & (p0[:, 2] > mz0 + 1e-4) & (p0[:, 2] < mz1 - 1e-4))
    if sel.sum() < 4:
        sel = (r0 < 0.7 * rmag) & (p0[:, 2] > mz0 + 1e-4) & (p0[:, 2] < mz1 - 1e-4)
    if sel.sum() < 4:
        sys.exit("[err] could not isolate magnet interior nodes")

    z0 = p0[sel, 2].mean()
    # FRAME TIME CONVENTION (verified numerically for both motion modes):
    #   case_t0001.vtu ... case_tNNNN.vtu hold t = 1*dt ... N*dt
    # i.e. frame k (0-based) is at t = (k+1)*dt.  Using t = k*dt instead
    # makes the mesh look like it lags by exactly one timestep
    # (err = -v*dt), which is easy to mistake for a real attenuation.
    z_t0 = z_of_t(sp, dt)
    offs = z0 - z_t0
    A = abs(sp["amplitude"])
    print(f"motion_mode   : spring")
    print(f"  T = {sp['period']:.4f} s   Q = {sp['Q']:.1f}   "
          f"A = {A*1000:.1f} mm   z_eq = {sp['z_eq_m']*1000:.2f} mm")
    print(f"  mesh magnet centre z0 = {z0:.6f} m  "
          f"(z_release = {sp['z_release_m']:.6f} m)   "
          f"interior nodes = {int(sel.sum())}")
    print(f"  constant mesh offset  = {offs*1000:+.3f} mm "
          f"(node-mean vs geometric centre; removed below)")
    print()
    print(f"  {'frame':>6}{'t(s)':>10}{'z_meas(m)':>14}{'z_theory':>14}"
          f"{'err(m)':>12}{'err/A':>10}")

    worst = 0.0
    n = len(files)
    for k in range(n):
        pts = meshio.read(files[k]).points
        zm = pts[sel, 2].mean()
        t = (k + 1) * dt                 # see note above
        zt = z_of_t(sp, t) + offs
        err = zm - zt
        worst = max(worst, abs(err))
        if k % max(1, n // 8) == 0 or k == n - 1:
            print(f"  {k:6d}{t:10.4f}{zm:14.6f}{zt:14.6f}"
                  f"{err:12.3e}{abs(err)/A:10.2e}")

    print()
    print(f"  worst |err| after removing the constant offset = {worst*1e6:.3f} um"
          f"   ({worst/A*100:.4f} % of the amplitude A)")
    ok = worst < a.tol * A
    print(f"  [{'PASS' if ok else 'FAIL'}] the mesh follows the prescribed "
          f"spring trajectory to < {a.tol*100:g} % of A")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

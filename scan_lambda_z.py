#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scan_lambda_z.py -- STATIC scan of the motional flux linkage Lambda_mot(z),
then the BENCH-side coupled prediction (no FEM dynamics at all).

WHY THIS WORKS WITHOUT TOUCHING THE CIRCUIT'S RESISTANCE
-------------------------------------------------------
The field energy decomposes as

    W(z, i) = W_pm(z) + i * Lambda_mot(z) + (1/2) L(z) i^2

so running each magnet position at +V and -V and differencing cancels BOTH the
permanent-magnet self energy and the (1/2)Li^2 term:

    Lambda_mot(z) = [ W(+i) - W(-i) ] / (2 i)

This is a pure FIELD statement -- the circuit's resistance bookkeeping never
enters (it only sets how large i happens to be).  That is why the ~9.045x
resistance anomaly (README 11.8) does NOT block this measurement.

CALIBRATION OF THE col-6 UNITS: Run the same z at several voltages, fit
W = W0 + a*i + b*i^2; then a = Lambda_mot(z) and b = (1/2)L(z) *in col-6 units*.
Since L(z_eq) is known from the solenoid formula (~0.5 mH at N=100), the unit
scale follows and Lambda_mot converts to Wb.

THEN THE PREDICTION IS PURE PYTHON (spring_model.coupled_z), using the BENCH
resistance R_total = R_wire(N) + series + shunt + leads -- i.e. what the copper
wire and the 0.5 ohm resistor actually do, not what the FEM's circuit believes.

Run:  python scan_lambda_z.py --case N100_L040_cu_closed --scan
      python scan_lambda_z.py --case N100_L040_cu_closed --predict
"""
from __future__ import annotations

import argparse
import math
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

import scan_flux_force as s
from spring_model import coupled_z, fit_gamma, load_spring

ROOT = s.ROOT
OUT = os.path.join(ROOT, "_static", "lambda_scan.csv")
SERIES = 0.5          # bench series resistor
SHUNT = 0.0012        # ACS712 internal conductor
C_AIR = 1.3284e-4     # air drag (N.s/m)
R_WIRE = 0.6333429    # cu, N=100
N_TURNS = 100


def point(base, z, volt, tag):
    """Copy the prepared tree, patch (z, volt), run, return (i, W)."""
    d = os.path.join(base, "pt_%s" % tag)
    if os.path.exists(d):
        shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    for f in ("case.sif", "circuits.definitions"):
        shutil.copy2(os.path.join(base, f), os.path.join(d, f))
    for sub in ("mesh",):
        src = os.path.join(base, sub)
        if os.path.exists(src):
            shutil.copytree(src, os.path.join(d, sub))
    s.patch(d, z, volt, steps=4)
    if s.run(d) is None:
        return None
    row = s.last_row(d)
    if row is None:
        return None
    return dict(z=z, v=volt, i=row[9], W=row[5], rc=row[13], rl=row[15])


def do_scan(case, zs, volts, workers):
    base = s.prepare(case)
    jobs = [(z, v) for z in zs for v in volts]
    print("  %d points (%d z x %d V), %d workers -> ~%d s"
          % (len(jobs), len(zs), len(volts), workers,
             int(math.ceil(len(jobs) / workers) * 45)))
    res = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(point, base, z, v, "z%05.1f_v%+.2f" % (z * 1000, v)): (z, v)
                for z, v in jobs}
        for f in futs:
            pass
        for f, (z, v) in futs.items():
            r = f.result()
            if r is None:
                print("   [fail] z=%.5f V=%+.2f" % (z, v))
            else:
                res.append(r)
                print("   z=%.5f V=%+.2f  i=%+.6e A  W=%.8e" % (z, v, r["i"], r["W"]))
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("z_m,volt,i_A,W_col6\n")
        for r in sorted(res, key=lambda q: (q["z"], q["v"])):
            fh.write("%.6f,%.3f,%.10e,%.10e\n" % (r["z"], r["v"], r["i"], r["W"]))
    print("  wrote %s  (%d points)" % (OUT, len(res)))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", default="N100_L040_cu_closed")
    ap.add_argument("--scan", action="store_true")
    ap.add_argument("--predict", action="store_true")
    ap.add_argument("--workers", type=int, default=max(2, min(8, (os.cpu_count() or 4) - 2)))
    a = ap.parse_args()
    if a.scan:
        zs = [0.006, 0.010, 0.014, 0.018, 0.022, 0.024, 0.026, 0.030, 0.034, 0.038, 0.042]
        return 0 if do_scan(a.case, zs, (1.0, -1.0), a.workers) else 1
    if a.predict:
        return predict(a.case)
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())

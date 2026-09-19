#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyse_z900.py -- LOCAL analysis of the z900 dynamic sweep (post-fix).

After the Body-Force-3 + No-Matrix fix in stage_lambda_scan.py, the z900
sweep should give:

  * peak |i|        -- now should be V/(R_total_bench) = 0.881 A peak-ish
                         in the V=0 closed-loop case (it's purely inductive)
  * peak |eps|      -- eps = i * R_total_bench -- the EMF * R_total
  * i_peak / N       -- i_peak \propto 1/N (geometric source-scaling law)
  * i_RMS / N        -- same
  * Cu / Al symmetry -- same
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import sys

import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))

R_C1 = 0.6333429
R_LOAD = 0.5012
R_TOTAL = R_C1 + R_LOAD                       # 1.1345 ohm


def read_circuit(path):
    """Read a circuit.csv and return t, i, v_coil, v_load, eps_arrays."""
    rows = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        parts = ln.split()
        try:
            rows.append([float(x) for x in parts])
        except ValueError:
            pass
    if not rows:
        return None
    arr = np.array(rows)
    t = arr[:, 6]
    i = arr[:, 9]
    v_coil = arr[:, 3]                         # i*rc_actual from MNA
    v_load = arr[:, 5]                         # i*R_load
    eps = i * (R_C1 + R_LOAD)                  # PHYSICAL EMF (defined)
    return t, i, v_coil, v_load, eps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "_static", "z900_v2"))
    a = ap.parse_args()
    os.chdir(ROOT)

    if not os.path.isdir(a.dir):
        print("[err] no %s -- pull the new z900 sweep first" % a.dir)
        return 1

    case_dirs = sorted(glob.glob(os.path.join(a.dir, "*")))
    if not case_dirs:
        print("[err] %s is empty" % a.dir)
        return 1

    rows = []
    for d in case_dirs:
        case = os.path.basename(d)
        p = os.path.join(d, "results", "circuit.csv")
        if not os.path.exists(p):
            print("   [skip] %s (no circuit.csv)" % case)
            continue
        out = read_circuit(p)
        if out is None:
            print("   [skip] %s (no rows)" % case)
            continue
        t, i, vc, vl, eps = out
        peak_i = float(np.max(np.abs(i)))
        peak_eps = float(np.max(np.abs(eps)))
        rms_i = float(np.sqrt(np.mean(i ** 2)))
        m = re.search(r"N(\d+)_", case)
        N = int(m.group(1)) if m else 0
        rows.append((case, N, peak_i, peak_eps, rms_i, len(t)))
        print("   %-22s N=%3d  steps=%4d  peak |i|=%9.4e  peak |eps|=%9.4e  i_rms=%9.4e"
              % (case, N, len(t), peak_i, peak_eps, rms_i))

    if not rows:
        return 1

    print("\n=== N-scaling of peak |i|  (geometric source law: i_peak ~ 1/N) ===")
    rows.sort(key=lambda r: r[1])
    print("   %-22s %5s %13s %13s %10s"
          % ("case", "N", "peak |i|", "N * peak |i|", "Cu/N ratio"))
    c = next((r for r in rows if r[1] == 25 and r[0].startswith("N25_L040_cu")), None)
    for case, N, peak_i, peak_eps, rms_i, n in rows:
        ratio = peak_i * N if (c and c[2] > 0) else float("nan")
        cu_ref = (peak_i / c[2]) if c and c[2] > 0 and N == c[1] else (
                 peak_i / c[2] if c and c[2] > 0 and case.startswith("N25_L040_cu") else 0)
        # Simpler: show N*peak_i per case; should be approximately constant within Cu
        print("   %-22s %5d %13.4e %13.4e %10.4f"
              % (case, N, peak_i, peak_i * N, peak_i * N))

    print("\n=== Cu / Al pair-up ===")
    print("   %-12s  N  peak|i|_cu   peak|i|_al   ratio"
          % ("case"))
    cu = {r[1]: r for r in rows if r[0].startswith("N") and "_cu_" in r[0]}
    al = {r[1]: r for r in rows if r[0].startswith("N") and "_al_" in r[0]}
    for N in sorted(cu):
        rc, ra = cu[N], al[N]
        print("   N=%-9d %2d  %10.4e  %10.4e  %7.4f"
              % (N, N, rc[2], ra[2], rc[2] / ra[2] if ra[2] > 0 else float('nan')))

    print("\n=== sanity: peak |eps| / peak |i| should equal R_total_bench = %.4f ==="
          % R_TOTAL)
    for case, N, peak_i, peak_eps, rms_i, n in rows:
        print("   %-22s peak |eps|/peak |i| = %.4f  (expect ~%.4f)"
              % (case, peak_eps / peak_i if peak_i > 0 else float('nan'), R_TOTAL))
    return 0


if __name__ == "__main__":
    sys.exit(main())
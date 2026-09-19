#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""analyse_lambda_scan.py -- LOCAL analysis of the HPC static scan."""
from __future__ import annotations
import argparse, glob, os, re, sys
from dataclasses import dataclass
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

COL_V_TESTSRC, COL_V_LOAD, COL_W, COL_TIME = 1, 3, 5, 6
COL_I_COIL, COL_V_COIL, COL_I_LOAD, COL_R_COIL, COL_R_LOAD = 9, 10, 11, 13, 15

R_C1 = 0.6333429
R_LOAD = 0.5012
R_TOTAL_BENCH = R_C1 + R_LOAD
L_SOL_SI = 0.5e-3
C_AIR = 1.3284e-4


@dataclass
class Point:
    tag: str
    V_set: float
    i_coil: float
    i_load: float
    v_testsource: float
    v_coil: float
    v_load: float
    R_coil: float
    R_load: float
    W: float = 0.0


def _parse_V(tag):
    if tag.startswith("sv_"):
        return 1.0
    if tag.startswith("mv"):
        m = re.search(r"v([+-]\d+\.\d+)$", tag)
        return float(m.group(1)) if m else 0.0
    m = re.search(r"(?:^|_)v(?:(\d+)(?!\d)|(0))$", tag)
    if m:
        v = float(m.group(1) or m.group(2))
        # legacy f*-tag quirk: 'v05' means 0.5 V (one decimal) when the digit
        # string starts with 0 and has more than one digit (e.g. v05, v025,
        # v075).  When v > 0 the literal was the original voltage * 10 with
        # the decimal point omitted -- unwrap.
        s = m.group(1) or m.group(2)
        if v >= 5 and len(s) > 1 and s[0] == '0':
            return v / 10.0
        return v
    return 0.0


def read_pt(t, path):
    rows = [ln for ln in open(path, encoding="utf-8", errors="replace").read().splitlines()
            if ln.strip()]
    if not rows:
        return None
    rec = rows[-1].split()
    return Point(t, _parse_V(t),
                 float(rec[COL_I_COIL]), float(rec[COL_I_LOAD]),
                 float(rec[COL_V_TESTSRC]), float(rec[COL_V_COIL]),
                 float(rec[COL_V_LOAD]), float(rec[COL_R_COIL]),
                 float(rec[COL_R_LOAD]), float(rec[COL_W]))


def load_family(prefix):
    out = []
    for tag in sorted(glob.glob(os.path.join(ROOT, "_static", "lambda_scan_results",
                                             prefix + "*"))):
        t = os.path.basename(tag)
        p = read_pt(t, os.path.join(tag, "results", "circuit.csv"))
        if p is None:
            print("   [missing] %s" % t)
            continue
        out.append(p)
    return out


def section_1(f):
    print("=== 1. FEM LOOP RESISTANCE from the f* diagnostics ===")
    pts = sorted([p for p in f if p.V_set > 0], key=lambda p: p.V_set)
    for p in pts:
        R_eff = p.V_set / p.i_coil
        print("   %-15s V=%.3f  i=%+.4e  R_eff=%.4f  (i*R_load=%.4f)"
              % (p.tag, p.V_set, p.i_coil, R_eff, p.i_coil * R_LOAD))
    if pts:
        avg = np.mean([p.V_set / p.i_coil for p in pts])
        print("   average R_eff_FEM = %.4f ohm   R_total_bench = %.4f   ratio = %.4f"
              % (avg, R_TOTAL_BENCH, avg / R_TOTAL_BENCH))
        for p in pts:
            print("   %s   v_coil+v_load = %+.6f   (should = V_set = %.4f)"
                  % (p.tag, p.v_coil + p.v_load, p.V_set))
    return f                            # return the FULL family so V=0 is included
def section_2_5(mv, sv, f_pts):
    print("\n=== 2. W(i) CURVE at z = 0.024 m  (mv*)  -- SI-scale calibration ===")
    mv_pts = sorted([p for p in mv if p.V_set > 0], key=lambda p: p.V_set)
    if not mv_pts:
        print("   (no mv* with V>0)"); return 0
    i_arr = np.array([p.i_coil for p in mv_pts])
    W_arr = np.array([p.W for p in mv_pts])
    c2 = np.polyfit(i_arr, W_arr, 2)
    print("   W(i) = %.6e + %.6e*|i| + %.6e*|i|^2" % (c2[2], c2[1], c2[0]))
    S = L_SOL_SI / (2 * c2[0])
    print("   =>  (1/2)L col-6 = %.4e   SI scale S = %.4e J/col6" % (c2[0], S))
    print("   =>  Lambda_mot(0.024) col-6 (linear) = %.4e" % c2[1])

    W0 = next((p.W for p in f_pts if p.V_set == 0.0), 0.0)
    print("\n=== 3. Lambda_mot(z) col-6 from sv* + f1 (V=0) baseline ===")
    print("   W(V=0, z=0.045) = %.4e" % W0)
    sv_pts = sorted(sv, key=lambda p: float(re.search(r"z([\d.]+)v", p.tag).group(1)))
    zs = np.array([float(re.search(r'z([\d.]+)v', p.tag).group(1)) / 1000.0 for p in sv_pts])
    ii = np.array([p.i_coil for p in sv_pts])
    WW = np.array([p.W for p in sv_pts])
    Lz_col6 = (WW - W0) / np.maximum(ii, 1e-30)
    print("   %-10s %13s %15s" % ("z[m]", "i_coil", "Lambda_col6"))
    for z, i_, l_ in zip(zs, ii, Lz_col6):
        print("   %-10.4f %13.4e %15.4e" % (z, i_, l_))

    print("\n=== 4. SI-scaled Lambda_mot(z) and b_em(z) ===")
    Lz_SI = Lz_col6 * S
    dLz_dz_SI = np.gradient(Lz_SI, zs)
    b_em_SI = dLz_dz_SI ** 2 / R_TOTAL_BENCH
    print("   %-10s %15s %17s %17s"
          % ("z[m]", "Lambda SI", "dLambda/dz SI", "b_em"))
    for z, l, dl, b_ in zip(zs, Lz_SI, dLz_dz_SI, b_em_SI):
        print("   %-10.4f %15.4e %17.4e %17.4e" % (z, l, dl, b_))

    print("\n=== 5. Spring-mass-damper PREDICTION  (bench R_total = %.4f) ==="
          % R_TOTAL_BENCH)
    try:
        from spring_model import load_spring
        sp = load_spring()
        m, k = float(sp.m), float(sp.k)
    except Exception as e:
        print("   [warn] load_spring failed (%s); using m=0.5 kg, k=220 N/m" % e)
        m, k = 0.5, 220.0
    T = 2 * np.pi / np.sqrt(k / m)
    bmax = float(np.max(b_em_SI))
    print("   m = %.4f kg   k = %.1f N/m   T = %.6f s   c_air = %.4e N.s/m"
          % (m, k, T, C_AIR))
    print("   b_em,max = %.5f N.s/m" % bmax)
    if bmax > 0:
        tau10 = 2 * m / bmax * np.log(10 / 9)
        print("   10%% decay time = %.3f s  (= %.2f periods)"
              % (tau10, tau10 / T))
    for t_end in (0.9, 2.0, 3.0):
        print("   over t_end = %.1f s: amplitude falls to %.2f%%"
              % (t_end, 100 * np.exp(-t_end * bmax / (2 * m))))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "_static", "lambda_scan_results"))
    a = ap.parse_args()
    os.chdir(ROOT)
    f = load_family("f")
    mv = load_family("mv")
    sv = load_family("sv")
    f_pts = section_1(f)
    section_2_5(mv, sv, f_pts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
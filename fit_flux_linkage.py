#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fit_flux_linkage.py -- RULED-OUT PATHS for extracting Lambda_mot(z) from the
900-step circuit.csv, plus the open question they uncovered.

STATUS: the extraction FAILS, and this file exists so nobody retries these
three routes (same spirit as README 7.6 "paths already ruled out").

WHAT WE WANTED
--------------
The coupled model needs one physical input, the motional linkage gradient
dLambda_mot/dz, because the Lenz drag is
    F_lenz = -(dLambda_mot/dz) * i    =>    b_em(z) = (dLambda_mot/dz)^2 / R_total

KVL for the source-free series loop is exact (check_fluxlink_vs_analytic.py):
    dlambda/dt = -(R_load + R_coil) * i
    lambda     = L_coil * i + lambda_mot(z)          [the decomposition]

so in principle  lambda(t) = -R_total * INT i ds  can be split into its
inductive and motional parts.  It cannot, in this dataset:

ROUTE 1 -- fit lambda = L*i + polynomial(z)
    DEGENERATE.  i(t) is already almost a function of z
    (i ~ lambda_mot'(z)*zdot/R), so the polynomial absorbs the L*i term and
    lstsq returns L = -1.24 H (negative, ~2500x the solenoid value).

ROUTE 2 -- pin the SHAPE with the analytic dipole stack, fit only (L, alpha)
    ALSO DEGENERATE.  L = -1.74 H, alpha = 0.2136 (remarkably stable across N
    and material -- the shape is fine), and dLambda_mot/dz comes out
    N-INDEPENDENT, 3.42e-3 Wb/m for every case.  Since Lambda_mot ~ N, that is
    wrong by construction: the fit is dumping the N-scaling into L*i.

ROUTE 3 -- fit lambda against a polynomial in z ALONE (no inductance term)
    25% rms residual, and the residual is EXACTLY proportional to N
    (25.545% at N=25, 25.543% at N=100).  Raising the degree from 2 to 5 does
    not help (25.5% -> 25.0%), and removing the 39 waveform spikes does not
    help either (25.13%).  So the residual is structure, not noise, and
    LOCALLY it is just as bad: inside a single z-bin the spread of lambda is
    up to 32% of |lambda|max, i.e. lambda is NOT a single-valued function of z.

WHAT THE FAILURE ITSELF TELLS US
--------------------------------
Two independent estimates agree that lambda contains a term linear in i with
coefficient ~ -1.7 H:
  * the within-bin spread of lambda divided by the current amplitude, and
  * the plain 3-parameter fit lambda = L*i + b*z + c  ->  L = -1.7197 H.
That is ~3400x the solenoid estimate mu0*N^2*A/l = 0.5 mH at N=100, and
NEGATIVE.  If it is real, then

    L/R_total = 1.7 / 10.6 = 0.16 s  ~  T/2

so the loop is NOT quasi-static-resistive at all, and `eps = i*R_total` is not
the EMF -- which would explain BOTH the 90% scatter of eps/zdot
(check_damping_plausibility.py) and the 25% lambda(z) residual here.

CONCLUSION: do not invert circuit.csv for Lambda_mot(z).  Get it from a STATIC
Lambda(z) sweep (about 20 magnetostatic solves at fixed magnet positions, no
motion, no circuit transient), or from a native `Calculate Magnetic Force`
output.  The ~1.7 H scale is an open question and must be understood BEFORE any
coupled run, because it sets the circuit's time constant.

Run:  python fit_flux_linkage.py
"""
from __future__ import annotations

import math
import os
import sys

import numpy as np

from spring_model import (b_em_from_linkage, coupled_z, fit_gamma, load_spring)

# reuse the on-axis dipole-stack model rather than duplicating it
from check_fluxlink_vs_analytic import flux_per_turn      # noqa: E402

ROOT = os.path.dirname(os.path.abspath(__file__))
Z900 = os.path.join(ROOT, "hpc_results_z900")

# 0-based columns (see circuit.csv.names): 7 time, 10 i_component(1),
# 11 v_component(1), 14 r_component(1), 16 r_component(2)
C_T, C_I, C_R, C_RL = 6, 9, 13, 15
DEG = 4                 # polynomial degree of Lambda_mot(u)
ZREF, ZSCALE = 0.024, 0.020     # so that u = (z - z_eq)/ZSCALE is O(1)
CASES = [("N25_L040_cu_closed", 25, "Cu"), ("N50_L040_cu_closed", 50, "Cu"),
         ("N100_L040_cu_closed", 100, "Cu"), ("N25_L040_al_closed", 25, "Al"),
         ("N50_L040_al_closed", 50, "Al"), ("N100_L040_al_closed", 100, "Al")]


def read_case(case):
    """t, i, R_total (r_component(1) + r_component(2)) from the 900-step run."""
    a = np.loadtxt(os.path.join(Z900, case, "results", "circuit.csv"))
    return a[:, C_T], a[:, C_I], a[:, C_R] + a[:, C_RL]


def spike_mask(i):
    """False on the 39 isolated waveform spikes (same rule as fig6)."""
    d = np.abs(np.diff(i))
    m = np.ones(len(i), bool)
    m[1:] = d < 10.0 * np.median(d)
    return m


def analytic_z(sp, t):
    e = np.exp(-sp["gamma"] * t)
    return sp["z_eq_m"] + sp["amplitude"] * e * (
        np.cos(sp["omega_d"] * t)
        + (sp["gamma"] / sp["omega_d"]) * np.sin(sp["omega_d"] * t))


def lam_ana(z, N):
    """Analytic MOTIONAL linkage (N turns) for a magnet centre at z.

    Reuses the on-axis dipole-stack model from check_fluxlink_vs_analytic.py
    instead of duplicating it, so the two scripts cannot drift apart.
    """
    return N * np.array([flux_per_turn(float(zz)) for zz in np.atleast_1d(z)])


def dlam_ana_dz(z):
    """d/dz of the per-turn analytic flux (central difference, h = 1 um)."""
    h = 1.0e-6
    return (flux_per_turn(float(z) + h) - flux_per_turn(float(z) - h)) / (2.0 * h)


def fit_case(sp, case, n_turns, use_poly=False, keep_spikes=False):
    """Fit  -(R_total) INT i dt  =  L * i(t)  +  alpha * lambda_ana(z)  +  beta.

    WHY THE ANALYTIC SHAPE: with a free polynomial in z the fit is DEGENERATE,
    because i(t) is already almost a function of z (i ~ lambda_mot'(z)*zdot/R),
    so the polynomial absorbs the L*i term -- it returned L = -1.24 H, i.e.
    negative and 2500x the solenoid value.  Pinning the SHAPE of Lambda_mot(z)
    to the dipole stack leaves only 3 unknowns (L, the scale alpha, the
    integration constant), which is well posed AND checkable: alpha must come
    out the same for every N and every material.
    """
    t, i, rtot = read_case(case)
    rtot = float(np.median(rtot))
    integ = np.concatenate([[0.0], np.cumsum(0.5 * (i[1:] + i[:-1]) * np.diff(t))])
    y = -rtot * integ                       # == Lambda(t) by KVL
    z = analytic_z(sp, t)
    u = (z - ZREF) / ZSCALE
    if use_poly:
        A = np.column_stack([i] + [u ** k for k in range(DEG + 1)])
        mode = "poly"
    else:
        A = np.column_stack([i, lam_ana(z, n_turns), np.ones(len(t))])
        mode = "ana"
    keep = spike_mask(i) if not keep_spikes else np.ones(len(i), bool)
    c, *_ = np.linalg.lstsq(A[keep], y[keep], rcond=None)
    resid = y - A @ c
    out = dict(t=t, i=i, Rtot=rtot, z=z, u=u, y=y, mode=mode, L=c[0],
               keep=keep, rms=float(resid[keep].std()),
               ymax=float(np.abs(y).max()),
               chi=float(resid[keep].std() / np.abs(y[keep]).max()),
               ana=lam_ana(z, n_turns))
    if mode == "ana":
        out["alpha"], out["beta"] = c[1], c[2]
    else:
        out["alpha"], out["beta"], out["coef"] = None, None, c[1:]
    return out


def dlmot_dz(fit, z):
    """dLambda_mot/dz = alpha * d(lambda_ana)/dz for the analytic-shape fit."""
    if fit["mode"] == "ana":
        return fit["alpha"] * dlam_ana_dz(z)
    u = (np.asarray(z, dtype=float) - ZREF) / ZSCALE
    s = 0.0
    for k in range(1, DEG + 1):
        s = s + k * fit["coef"][k] * u ** (k - 1)
    return s / ZSCALE


def lmot(fit, z):
    u = (np.asarray(z, dtype=float) - ZREF) / ZSCALE
    s = 0.0
    for k in range(DEG + 1):
        s = s + fit["coef"][k] * u ** k
    return s


def main():
    sp = load_spring()
    print("=== RULED OUT: inverting circuit.csv for Lambda_mot(z) ===\n")
    print("  case              |lam|max[Wb]  route3 rms resid   L(route1)[H]"
          "   L(route2)[H]  L_sol[H]")
    print("  " + "-" * 88)
    A_ = math.pi * 0.0225 ** 2
    for case, N, mat in CASES:
        t, i, rtot = read_case(case)
        integ = np.concatenate([[0.0], np.cumsum(0.5 * (i[1:] + i[:-1]) * np.diff(t))])
        lam = -rtot * integ
        z = analytic_z(sp, t)
        r3 = lam - np.polyval(np.polyfit(z, lam, DEG), z)        # route 3
        f1 = fit_case(sp, case, N, use_poly=True)                # route 1
        f2 = fit_case(sp, case, N)                               # route 2
        lsol = 4.0e-7 * math.pi * N * N * A_ / 0.04
        print(f"  {case:<18} {np.abs(lam).max():11.4e}  {100*r3.std()/np.abs(lam).max():12.3f}%"
              f"  {f1['L']:14.4f}  {f2['L']:14.4f}  {lsol:.5f}")
    print()
    print("  route 3 residual is ~25% and EXACTLY proportional to N (25.545% ->")
    print("  25.543%); raising the degree 2->5 or dropping the 39 spikes does not")
    print("  help.  Locally it is as bad: inside one z-bin the spread of lambda is")
    print("  up to 32% of |lam|max, so lambda is NOT a function of z.")
    print()
    print("  routes 1 and 2 both return L ~ -1.2 .. -1.9 H, i.e. ~3400x the")
    print("  solenoid value and NEGATIVE.  The plain 3-parameter fit")
    print("  lambda = L*i + b*z + c gives L = -1.7197 H for N25_cu.")
    print("  If that scale is real, L/R = 0.16 s ~ T/2, the loop is NOT")
    print("  quasi-static, and eps = i*R_total is not the EMF.")
    print()
    print("  ACTION: get Lambda_mot(z) from a STATIC Lambda(z) sweep (about 20")
    print("  magnetostatic solves at fixed magnet positions) or from a native")
    print("  `Calculate Magnetic Force` output.  Understand the ~1.7 H scale")
    print("  first -- it sets the circuit time constant of any coupled run.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

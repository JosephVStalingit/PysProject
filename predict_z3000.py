#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""predict_z3000.py -- PREDICTED z(t), i(t), decay envelope for the z3000 sweep.

Run:  python predict_z3000.py
"""
from __future__ import annotations

import numpy as np
import os, sys, glob, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ---- spring params ---------------------------------------------------------
m = 0.5
k = 220.0
z_eq = 0.024
z_release = 0.045
A = z_release - z_eq
omega0 = np.sqrt(k / m)
T = 2 * np.pi / omega0

R_c1 = 0.6333429
R_load = 0.5012
R_total = R_c1 + R_load
c_air = 1.3284e-4

# ---- analytic dipole stack ------------------------------------------------
from check_fluxlink_vs_analytic import flux_per_turn

def lam_ana(z, N=100):
    return N * flux_per_turn(z)

zs_ana = np.linspace(0.006, 0.044, 41)
Lam_B = np.array([lam_ana(z) for z in zs_ana])
dLam_dz_B = np.gradient(Lam_B, zs_ana)
b_em_B = dLam_dz_B ** 2 / R_total

print("=== Lambda_mot(z) from analytic dipole stack ===")
print("   %-10s %13s %13s %13s"
      % ("z[m]", "Lambda[Wb]", "dL/dz[Wb/m]", "b_em[N.s/m]"))
for z, L, dL in zip(zs_ana[::4], Lam_B[::4], dLam_dz_B[::4]):
    print("   %-10.4f %13.4e %13.4e %13.4e" % (z, L, dL, dL ** 2 / R_total))

bmax_B = float(np.max(b_em_B))
print("   b_em,max = %.4e N.s/m" % bmax_B)

# ---- PREDICTION -----------------------------------------------------------
g0 = c_air / (2 * m)
g1 = (c_air + bmax_B) / (2 * m)

print("\n=== Spring-mass response (analytic Lambda_mot) ===")
print("   m=%.2f kg  k=%.1f N/m  omega0=%.4f rad/s  T=%.4f s"
      % (m, k, omega0, T))
print("   gamma (no Lenz)   = %.4e /s" % g0)
print("   gamma (with Lenz) = %.4e /s" % g1)
print("   b_em,max = %.4e N.s/m" % bmax_B)
for t_end in (0.9, 2.0, 3.0):
    print("   over t_end = %.1f s: amplitude = %6.2f%%  (no-Lenz would be %6.2f%%)"
          % (t_end, 100 * np.exp(-g1 * t_end),
             100 * np.exp(-g0 * t_end)))

dt = 1e-3
tt = np.arange(0, 3.0 + dt, dt)
g = g1
z_traj = z_eq + A * np.exp(-g * tt) * np.cos(omega0 * tt)
zdot = np.gradient(z_traj, dt)
Lam = np.interp(z_traj, zs_ana, Lam_B)
eps = -Lam * zdot
i = -eps / R_total
print("   peak |i| in [0, 3s]   = %.4e A" % float(np.max(np.abs(i))))
print("   peak |eps| in [0, 3s] = %.4e V" % float(np.max(np.abs(eps))))
print("   z(0.9 s) = %+.4e m   z(1.99 s) = %+.4e m   z(3.0 s) = %+.4e m"
      % (z_traj[900], z_traj[1990], z_traj[3000]))

# ---- i_peak under the SOURCE-DRIVEN limit (V=0 closed loop -> pure EMF) ---
# at z_eq with A*omega = peak velocity, peak eps = Lam(z_eq) * A * omega0
peak_eps_eq = abs(Lam_B[20]) * A * omega0       # ~at z=0.024 (index 20)
peak_i_eq = peak_eps_eq / R_total
print("\n=== Peak induced EMF / current at z_eq (V=0 closed loop) ===")
print("   Lambda_mot(z_eq) = %.4e Wb   A*omega0 = %.4e m/s"
      % (abs(Lam_B[20]), A * omega0))
print("   peak |eps| ~ %.4e V    peak |i| ~ %.4e A"
      % (peak_eps_eq, peak_i_eq))

print("\n=== Expected FEM numbers for the z3000 sweep (sanity check) ===")
print("   If R_total = R_total_bench (1.1345 ohm) and Lambda_mot = 0.16 Wb (analytic),")
print("   the CLOSED loop (no source) should show eps_peak ~ %.4e V and i_peak ~ %.4e A"
      % (peak_eps_eq, peak_i_eq))
print("   Compare to the OLD (pre-fix) z900 measurements: peak |i| ~ 1e-2 A, peak |eps| ~ 1e-2 V")
print("   That ratio of ~ 80x is the 9.045^2 == 81.8 effect of the resistance anomaly.")
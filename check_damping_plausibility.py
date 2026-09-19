#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_damping_plausibility.py -- is config.json's damping physically real?

The whole "how much does the Lenz force matter?" question hinges on ONE number:
the mechanical damping c.  Adding the Lenz drag b_em changes the decay rate by

    gamma_eff / gamma = (c + b_em) / c

so b_em is either negligible (b_em << c) or dominant (b_em >> c) depending
entirely on c.  config.json ships c = 0.8 N.s/m, i.e. Q = 13.1 -- a heavily
damped oscillator that dies in ~3 periods.  A real magnet on a steel spring in
air does not do that.  This script estimates the damping mechanisms that could
physically be present and compares each with b_em read off the measurements.

Mechanisms
----------
1. AIR DRAG (quadratic).  F = 1/2 rho Cd A v^2.  For a sinusoidal velocity the
   drag is linearised at the fundamental with the standard 8/(3 pi) factor:
       c_air = 8/(3 pi) * (1/2) rho Cd A v0
2. SPRING MATERIAL (HYSTERETIC) DAMPING.  For a loss factor eta the equivalent
   viscous coefficient at the drive frequency is
       c_hyst = eta * k / omega
   eta ~ 1e-3 (steel spring) to 1e-2 (bolted joints); 1e-1 would be rubber.
3. LENZ DRAG (electromagnetic) -- read from the 900-step data, see
   `analyse_lenz_coupling.py`;  b_em(N) = (dLambda/dz)^2 / R_total.

Run:  python check_damping_plausibility.py
"""
from __future__ import annotations

import math
import sys

from spring_model import load_spring

RHO_AIR = 1.225          # kg/m^3 at 15 C, 1 atm
CD_AXIAL = 0.82          # short cylinder (L/D = 1) in axial flow


def main():
    sp = load_spring()
    r_mag = 0.015
    area = math.pi * r_mag ** 2          # frontal area, axial motion
    v0 = sp["amplitude"] * (sp["omega0"] ** 2 / sp["omega_d"])   # 1st |zdot| peak

    print("=== modelled oscillator (config.json) ===")
    print(f"  m = {sp['m']} kg   k = {sp['k']} N/m   c = {sp['c']} N.s/m"
          f"   gamma = {sp['gamma']:.4f} 1/s   Q = {sp['Q']:.2f}")
    print(f"  amplitude A = {sp['amplitude']*1000:.3f} mm   "
          f"peak |zdot| = {v0:.4f} m/s   period = {sp['period']*1000:.3f} ms")
    print(f"  magnet: R = {r_mag*1000:.1f} mm,  frontal area = {area*1e6:.3f} mm^2")

    # ---- 1. air drag ------------------------------------------------------
    k_air = 0.5 * RHO_AIR * CD_AXIAL * area
    c_air = 8.0 / (3.0 * math.pi) * k_air * v0
    f_drag = k_air * v0 ** 2
    print()
    print("=== mechanism 1: AIR DRAG (quadratic, linearised at the fundamental) ===")
    print(f"  (1/2) rho Cd A       = {k_air:.4e} kg/m")
    print(f"  drag force at peak   = {f_drag:.3e} N    (spring force kA = "
          f"{sp['k']*sp['amplitude']:.3f} N -> {100*f_drag/(sp['k']*sp['amplitude']):.5f}%)")
    print(f"  c_air                = {c_air:.4e} N.s/m")
    print(f"  c_config / c_air     = {sp['c']/c_air:.0f}x")
    print(f"  Q with air drag only = {math.sqrt(sp['k']*sp['m'])/c_air:.4e}")

    # ---- 2. spring hysteresis --------------------------------------------
    print()
    print("=== mechanism 2: SPRING MATERIAL (HYSTERETIC) DAMPING ===")
    print("  loss factor eta    c_hyst = eta*k/omega    c_hyst/c_config")
    for eta in (1e-3, 1e-2, 5e-2, 1e-1):
        ch = eta * sp["k"] / sp["omega_d"]
        print(f"      {eta:7.3f}         {ch:10.4e} N.s/m        {ch/sp['c']:9.3e}")

    # ---- 3. Lenz drag (measured) -----------------------------------------
    # b_em for the CLOSED circuit (R_load = 10 ohm) and for a SHORT circuit;
    # b_em scales as 1/R_total.
    dl = {25: 6.138006e-2, 50: 1.226888e-1, 100: 2.448276e-1}
    # R_wire (Cu) from the CATALOGUE resistivities -- see check_wire_resistance.py.
    # dLambda/dz is a FIELD quantity measured at the velocity peak, so it does not
    # depend on this choice; only b_em = (dLambda/dz)^2/R_total does.
    r_coil = {25: 0.1583357, 50: 0.3166714, 100: 0.6333429}
    r_load = 10.0
    print()
    print("=== mechanism 3: LENZ DRAG (from the measurements) ===")
    print("  N    dLambda/dz[Wb]    b_em(10 ohm)[N.s/m]   b_em(short)[N.s/m]"
          "    b_em/c_config")
    for n in (25, 50, 100):
        b_closed = dl[n] ** 2 / (r_coil[n] + r_load)
        b_short = dl[n] ** 2 / r_coil[n]
        print(f"  {n:3d}   {dl[n]:14.6e}    {b_closed:18.6e}   {b_short:18.6e}"
              f"   {100*b_closed/sp['c']:8.4f}% / {100*b_short/sp['c']:.1f}%")

    # ---- verdict ---------------------------------------------------------
    b100 = dl[100] ** 2 / (r_coil[100] + r_load)
    c_hyst_mid = 1e-2 * sp["k"] / sp["omega_d"]
    c_lo = c_air
    c_hi = c_air + c_hyst_mid
    print()
    print("=== VERDICT: which damping dominates physically? ===")
    print(f"  plausible mechanical damping c_phys ~ {c_lo:.2e} .. {c_hi:.2e} N.s/m")
    print(f"  config.json ships c = {sp['c']:.2f} N.s/m -> {sp['c']/c_hi:.0f}x .."
          f" {sp['c']/c_lo:.0f}x LARGER than physics")
    print()
    print(f"  At N = 100 the Lenz drag is b_em = {b100:.3e} N.s/m:")
    print(f"     b_em / c_config = {100*b100/sp['c']:8.3f}%   -> Lenz is a rounding error")
    print(f"     b_em / c_phys   = {b100/c_hi:8.1f}x .. {b100/c_lo:.0f}x"
          f"   -> Lenz DOMINATES")
    print()
    print("  So 'how much does the Lenz force matter' is NOT a property of the")
    print("  apparatus at all.  It is a property of the CHOSEN c: c = 0.8 hides the")
    print("  very effect the experiment is about.")

    print()
    print("=== ring-down: how long does it take to stop? ===")
    print("  scenario                        c_eff[N.s/m]      Q    e-fold[s]"
          "   after 0.9 s   after 60 s")
    rows = (("as modelled (c_config)", sp["c"]),
            ("air drag only", c_lo),
            ("air + spring hysteresis", c_hi),
            ("air + hyst + Lenz(N100,10ohm)", c_hi + b100),
            ("air + hyst + Lenz(N25,10ohm)",
             c_hi + dl[25] ** 2 / (r_coil[25] + r_load)),
            ("air + hyst + Lenz(N100,short)",
             c_hi + dl[100] ** 2 / r_coil[100]))
    for name, cc in rows:
        tq = 2.0 * sp["m"] / cc
        print(f"  {name:<32} {cc:11.4e}  {math.sqrt(sp['k']*sp['m'])/cc:8.1f}"
              f"  {tq:9.2f}  {100*math.exp(-0.9/tq):10.3f}%"
              f"  {100*math.exp(-60.0/tq):9.3f}%")

    print()
    print("=== REALISTIC model per user: weak air drag + Lenz (coil), air only (empty) ===")
    print("  The load resistor sets the Lenz damping: b_em = (dLambda/dz)^2/(R_load+r).")
    print("  case      mechanism              c_eff[N.s/m]      Q       e-fold[s]"
          "   amplitude after 1 period   after 0.9 s")
    rows2 = (("N25(10ohm)", c_lo + dl[25] ** 2 / (r_coil[25] + r_load)),
             ("N50(10ohm)", c_lo + dl[50] ** 2 / (r_coil[50] + r_load)),
             ("N100(10ohm)", c_lo + b100),
             ("empty", c_lo))
    for name, cc in rows2:
        tq = 2.0 * sp["m"] / cc
        per = math.exp(-sp["period"] / tq)
        print(f"  {name:<12} air+Lenz / air only  {cc:11.4e}  "
              f"{math.sqrt(sp['k']*sp['m'])/cc:8.1f}  {tq:9.2f}  "
              f"{100*per:22.4f}%  {100*math.exp(-0.9/tq):14.4f}%")

    print()
    print("=== load resistor is the main design knob (N=100, Cu) ===")
    print("  R_load[ohm]   R_total[ohm]   b_em[N.s/m]   Q_em     per-period loss"
          "   10% decay [s]")
    for rl in (0.0, 0.5, 1.0, 10.0, 100.0):
        rt = r_coil[100] + rl
        b = dl[100] ** 2 / rt
        q = math.sqrt(sp["k"] * sp["m"]) / (c_lo + b)
        tq = 2.0 * sp["m"] / (c_lo + b)
        print(f"  {rl:10.1f}   {rt:11.4f}   {b:12.4e}  {q:7.1f}   "
              f"{100*(1-math.exp(-sp['period']/tq)):13.4f}%   {tq*math.log(10/9):11.2f}")
    print("  (R_load = 0 is the SHORT circuit: 17x more Lenz damping than 10 ohm)")

    print()
    print("=== how long must the record be to SEE the Lenz effect? ===")
    print("  contrast = amplitude(coil) vs amplitude(empty), both from the same t=0")
    print("  t[s]    periods   N=25 coil     N=50 coil    N=100 coil      empty")
    for tn in (0.9, 5.0, 10.0, 20.0, 60.0):
        cells = []
        for cc in (c_lo + dl[25] ** 2 / (r_coil[25] + r_load),
                   c_lo + dl[50] ** 2 / (r_coil[50] + r_load),
                   c_lo + b100, c_lo):
            cells.append(100 * math.exp(-tn / (2.0 * sp["m"] / cc)))
        print(f"  {tn:5.1f}   {tn/sp['period']:8.1f}   {cells[0]:9.3f}%  "
              f"{cells[1]:11.3f}%  {cells[2]:12.3f}%  {cells[3]:9.3f}%")
    print()
    print("  So in the CURRENT 0.9 s window the coil and empty curves are")
    print("  indistinguishable (99.95% vs 99.99%): the experiment as configured")
    print("  cannot show Lenz braking AT ALL.  It shows up after ~10-20 s.")

    print()
    print("=== THE MEASUREMENT CHAIN's own circuit: R_load ~ 0 (sensors only) ===")
    print("  A voltage sensor sits in parallel and is high-impedance (1 Mohm), so it")
    print("  carries nothing; the loop resistance is then just the coil plus whatever")
    print("  the current sensor's shunt/burden adds.  Take R_load = 0 first.")
    print("  NOTE: on a SHORT circuit b_em = (dLambda/dz)^2/R_wire with R_wire ~ N,")
    print("  and dLambda/dz ~ N, so b_em ~ N -- LINEAR in turns, not N^2 as it is")
    print("  when a fixed 10 ohm load dominates.  And Cu (better conductor) now damps")
    print("  MORE than Al, by exactly the conductivity ratio sigma_Cu/sigma_Al:")
    print("  case      R_wire[ohm]  b_em[N.s/m]   Q_em    per-period loss"
          "   10% loss[s]   50% loss[s]   peak i[mA]")
    eps_pk = {25: 27.7388e-3, 50: 55.4408e-3, 100: 110.6103e-3}
    wire = {"cu": {25: 0.1583357, 50: 0.3166714, 100: 0.6333429},
            "al": {25: 0.2562245, 50: 0.5124490, 100: 1.0248980}}
    for mat in ("cu", "al"):
        for n in (25, 50, 100):
            b = dl[n] ** 2 / wire[mat][n]
            cc = c_lo + b
            tq = 2.0 * sp["m"] / cc
            ipk = eps_pk[n] / wire[mat][n]
            print(f"  N={n:<3} {mat}  {wire[mat][n]:10.7f}  {b:11.4e}  "
                  f"{math.sqrt(sp['k']*sp['m'])/cc:7.1f}  "
                  f"{100*(1-math.exp(-sp['period']/tq)):13.4f}%  "
                  f"{tq*math.log(10/9):11.2f}  "
                  f"{tq*math.log(2):11.2f}   {1000*ipk:10.3f}")
    print(f"  empty      --          --              --         0 (no circuit)"
          f"          --          --          --")
    print()
    print("  peak current is N-INDEPENDENT here (eps ~ N and R_wire ~ N cancel):")
    print("  Cu ~175 mA and Al ~108 mA whatever the turns -- 17x / 10x the current")
    print("  the 10 ohm-load model produces, and no longer rising with N.")
    print()
    print("=== coil vs EMPTY contrast on the short circuit (amplitude remaining) ===")
    print("  t[s]   N=25 Cu    N=50 Cu    N=100 Cu     empty(air only)")
    for tn in (1.0, 2.0, 5.0, 10.0):
        cells = []
        for n in (25, 50, 100):
            cc = c_lo + dl[n] ** 2 / wire["cu"][n]
            cells.append(100 * math.exp(-tn / (2.0 * sp["m"] / cc)))
        print(f"  {tn:5.1f}   {cells[0]:8.2f}%  {cells[1]:9.2f}%  {cells[2]:10.2f}%"
              f"   {100*math.exp(-tn/(2.0*sp['m']/c_lo)):13.3f}%")
    print()
    print("  After 2 s the empty case has lost 0.03% while N=100 Cu has lost 17%;")
    print("  after 5 s: 0.07% against 38%.  That is the measurable Lenz signature.")

    print()
    print("=== what the 900-step window captures (Lenz correction vs t_end) ===")
    print("  The Lenz correction over a window t_end depends ONLY on b_em and t_end:")
    print("      envelope ratio = exp(-b_em * t_end / (2 m))")
    print("  case        b_em[N.s/m]   t_end=0.9 s    t_end=60 s")
    for n in (25, 50, 100):
        b = dl[n] ** 2 / (r_coil[n] + r_load)
        e1 = math.exp(-b * 0.9 / (2 * sp["m"]))
        e2 = math.exp(-b * 60.0 / (2 * sp["m"]))
        print(f"  N={n:<4}      {b:11.4e}   {100*(e1-1):+9.4f}%   {100*(e2-1):+9.2f}%")
    print()
    print("  KEY: over the CURRENT 0.9 s window the one-way (prescribed) model is")
    print("  still an excellent approximation (<0.6% at N=100) -- but that is only")
    print("  because 0.9 s is 0.5% of the Lenz time constant 2m/b_em.  Over a")
    print("  realistic, long ring-down the SAME term becomes tens of percent, and")
    print("  since b_em ~ N^2 the six curves would then decay at visibly different")
    print("  rates.  The current sweep cannot see that.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

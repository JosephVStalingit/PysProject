#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_wire_resistance.py -- verify R_wire against the catalogue resistivities.

`make_sif.py::_r_wire` computes the coil's lumped resistance as

    R_wire = N * 2*pi*r_mean / (sigma_wire * pi*d^2/4)

and writes it straight into `Component 1 Resistance`, so r_component(1) comes
back EQUAL to it (mesh-independent, verified to machine precision in the
900-step sweep).  The only physical input is the wire conductivity, which must
be the reciprocal of the catalogue resistivity:

    rho_Cu = 0.017241 ohm.mm^2/m   ->  sigma_Cu = 5.80012776e7 S/m
    rho_Al = 0.0279   ohm.mm^2/m   ->  sigma_Al = 3.58422939e7 S/m

This script checks (a) that config.json carries those conductivities, (b) what
R_wire each curve gets, and (c) how much the answer moves if the conductivity is
wrong -- which matters because R_wire feeds the Lenz drag
b_em = (dLambda/dz)^2 / (R_load + R_wire).

Run:  python check_wire_resistance.py
"""
from __future__ import annotations

import io
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RHO_MM2_PER_M = {"cu": 0.017241, "al": 0.0279}     # ohm.mm^2/m at 20 C


def sigma_from_rho(rho_mm2_per_m: float) -> float:
    """S/m from ohm.mm^2/m."""
    return 1.0 / (rho_mm2_per_m * 1.0e-6)


def r_wire(cfg: dict, curve: dict, n_turns: int, sigma: float = None) -> float:
    """Same formula as make_sif._r_wire, with an optional sigma override."""
    coil = cfg["coil"]
    r_mean = 0.5 * (float(coil["r_outer_m"]) + float(coil["r_inner_m"]))
    l_turn = 2.0 * math.pi * r_mean
    d = float(curve["wire_diameter_m"])
    a_wire = math.pi * (0.5 * d) ** 2
    s = float(curve["wire_conductivity_S_per_m"]) if sigma is None else sigma
    return n_turns * l_turn / (s * a_wire)


def main():
    cfg = json.load(io.open(ROOT / "config.json", encoding="utf-8"))
    curves = {k: v for k, v in cfg["curves"].items() if isinstance(v, dict)}
    coil = cfg["coil"]
    r_mean = 0.5 * (float(coil["r_outer_m"]) + float(coil["r_inner_m"]))
    d = 0.0007

    print("=== wire geometry implied by config.json -> [coil] ===")
    print(f"  r_mean = (r_inner + r_outer)/2 = {r_mean*1000:.2f} mm"
          f"   -> one turn = {2*math.pi*r_mean*1000:.4f} mm")
    print(f"  wire diameter (per curve)      = {d*1000:.2f} mm"
          f"   -> A_wire = {math.pi*(0.5*d)**2:.6e} m^2")

    print()
    print("=== catalogue resistivity vs config conductivity ===")
    print("  material   rho[ohm.mm^2/m]   sigma should be[S/m]   config sigma[S/m]"
          "    config/spec")
    for mat, rho in RHO_MM2_PER_M.items():
        want = sigma_from_rho(rho)
        got = next(float(v["wire_conductivity_S_per_m"]) for k, v in curves.items()
                   if k.endswith("_" + mat + "_closed"))
        flag = "OK" if abs(got / want - 1) < 1e-6 else "MISMATCH"
        print(f"  {mat.upper():<9}  {rho:14.6f}   {want:19.4f}   {got:16.4f}"
              f"    {got/want:.6f}  {flag}")

    print()
    print("=== R_wire(N) -- what each curve gets, and what the WRONG sigma gave ===")
    print("  curve                  N   R_wire[ohm]   sigma used     R_wire with OLD"
          " sigma   drift")
    old = {"cu": 5.96e7, "al": 3.5e7}
    for name, cv in curves.items():
        n = cv.get("N_turns")
        if not n:
            continue
        mat = "cu" if name.endswith("_cu_closed") else "al"
        r_now = r_wire(cfg, cv, n)
        r_old = r_wire(cfg, cv, n, sigma=old[mat])
        print(f"  {name:<22} {n:3d}   {r_now:10.7f}   {cv['wire_conductivity_S_per_m']:11.4e}"
              f"   {r_old:15.7f}   {100*(r_now/r_old-1):+6.3f}%")

    print()
    print("=== the ONLY observable that moves: i_peak = eps/(R_load + R_wire) ===")
    print("  eps itself is independent of R, so eps/N -- and hence the eps ~ N")
    print("  collapse -- is untouched.  Only the current changes:")
    print("  curve                  R_load   R_tot(new)   R_tot(old)   i_peak drift")
    for name, cv in curves.items():
        n = cv.get("N_turns")
        if not n:
            continue
        mat = "cu" if name.endswith("_cu_closed") else "al"
        rl = float(cv["R_load_ohm"])
        r_new = r_wire(cfg, cv, n) + rl
        r_old = r_wire(cfg, cv, n, sigma=old[mat]) + rl
        print(f"  {name:<22} {rl:6.1f}   {r_new:10.4f}   {r_old:10.4f}"
              f"   {100*(r_old/r_new-1):+8.3f}%")
    print()
    print("=== R_load = series + shunt + leads  (config.json -> [sensor]) ===")
    sens = cfg.get("sensor", {})
    use = bool(sens.get("use_sensor_burden"))
    se, sh, ld = (sens.get("series_ohm"), sens.get("shunt_ohm"),
                  sens.get("leads_ohm"))
    print(f"  use_sensor_burden = {use}    series = {se}    shunt = {sh}"
          f"    leads = {ld}")
    if use and None not in (se, sh, ld):
        want = float(se) + float(sh) + float(ld)
        bad = [n for n, cv in curves.items()
               if cv.get("N_turns") and abs(float(cv["R_load_ohm"]) - want) > 1e-12]
        print(f"  -> every curve should carry R_load_ohm = {want:.6f}"
              f"   (+/- leads/solder, taken as {ld})")
        print("  -> " + ("CONSISTENT" if not bad else "MISMATCH in: " + ", ".join(bad)))
    else:
        print("  -> not active: each curve keeps its own R_load_ohm"
              f" ({sorted({float(c['R_load_ohm']) for c in curves.values() if c.get('N_turns')})})")

    print()
    print("=== burden sensitivity: what the shunt+leads value will give ===")
    print("  (N=100, dLambda/dz = 2.448276e-1 Wb at the velocity peak, eps_peak = 110.6103 mV;")
    print("   c_air = 1.3284e-4 N.s/m; L_coil ~ 0.5 mH at N=100, ~N^2)")
    cair = 1.3284e-4
    km = math.sqrt(220.0 * 0.5)
    Tm = 0.299539
    dldz = 2.448276e-1
    eps_pk = 110.6103e-3
    lc = 5.0e-4
    print("  mat  R_load  R_total   b_em[N.s/m]   Q_em   per-period"
          "   10% loss   peak i[mA]   tau[us]  dt=1ms/tau")
    for mat, rw in (("Cu", 0.6333429), ("Al", 1.0248980)):
        for rl in (0.0, 0.05, 0.1, 0.2, 0.5, 1.0, 10.0):
            rt = rw + rl
            b = dldz ** 2 / rt
            cc = cair + b
            tq = 2.0 * 0.5 / cc
            tau = lc / rt
            print(f"  {mat}  {rl:6.2f}  {rt:8.4f}   {b:11.4e}  {km/cc:6.1f}"
                  f"  {100*(1-math.exp(-Tm/tq)):10.4f}%  {tq*math.log(10/9):8.2f} s"
                  f"   {1000*eps_pk/rt:10.3f}   {1e6*tau:7.1f}   {1e-3/tau:8.3f}")
    print()
    print("  NOTE dt/tau: the EXISTING 900-step runs sit at dt/tau = 21 (R = 10.6 ohm)")
    print("  and reproduce the purely-resistive law i = eps/R to 5 digits, so a large")
    print("  dt/tau is tolerable here because the FORCING is slow (3.3 Hz).  On a")
    print("  short loop dt/tau DROPS to ~1, i.e. the circuit is better resolved, not")
    print("  worse -- no new stiffness is introduced.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

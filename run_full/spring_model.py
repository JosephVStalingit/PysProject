#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
spring_model.py -- single source of truth for the spring-mass-damper
experiment.

Every consumer (solenoid3d.py for the geometry, the SIF generator for the
prescribed motion, oscilloscope.py for the reference curves) imports
`load_spring()` from here so the numbers can never drift apart.

Physics
-------
A magnet of mass m hangs from a spring of stiffness k and natural length
L0; the spring's top is welded to a clamped anchor plate at z = anchor_z0.
Released from rest at z_release it obeys

    m z'' = -m g - k (L - L0) - c z' - F_lenz
    L(z)  = anchor_z0 - (z + H_mag/2)          spring length

With no Lenz force the solution is the familiar damped oscillator

    z(t) = z_eq + A e^(-gamma t) [ cos(wd t) + (gamma/wd) sin(wd t) ]
    z'(t)= -A (omega0^2/wd) e^(-gamma t) sin(wd t)

    omega0 = sqrt(k/m)      gamma = c/(2m)      wd = sqrt(omega0^2-gamma^2)
    z_eq   = anchor_z0 - H_mag/2 - L0 - m g/k   (static equilibrium)
    A      = z_release - z_eq

NOTE ON SIGN: the magnet hangs from the anchor, so the spring PULLS UP.
The anchor is therefore ABOVE the magnet and z_eq comes out below it.

Usage
-----
    from spring_model import load_spring
    sp = load_spring(cfg_dict)
    sp["z_eq_m"], sp["omega0"], sp["matc_expr"]...
"""
from __future__ import annotations
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CFG_PATH = ROOT / "config.json"


def _cfg(cfg=None):
    if cfg is not None:
        return cfg
    with open(CFG_PATH, encoding="utf-8") as f:
        return json.load(f)


def load_spring(cfg=None) -> dict:
    """Read config.json -> [spring] and derive everything else."""
    c = _cfg(cfg)
    s = c["spring"]
    mag = c["magnet"]
    # CAREFUL: config.json's `H_mag_m` is the HALF height (0.015), used by the
    # on-axis dipole formula; the magnet actually spans z0_m..z1_m (0.030).
    # Derive the true full height from the extent so the two cannot disagree.
    H = float(mag["z1_m"]) - float(mag["z0_m"])

    m = float(s["mass_kg"])
    k = float(s["stiffness_N_per_m"])
    c_d = float(s["damping_N_s_per_m"])
    g = float(c["physics"]["G"])

    anchor_z0 = float(s["anchor_z0_m"])
    anchor_z1 = float(s["anchor_z1_m"])
    z_release = float(s["z_release_m"])

    omega0 = math.sqrt(k / m)
    gamma = c_d / (2.0 * m)
    if omega0 <= gamma:
        raise SystemExit("[err] spring is over-damped: c/(2m) >= sqrt(k/m)")
    omega_d = math.sqrt(omega0 * omega0 - gamma * gamma)
    period = 2.0 * math.pi / omega0
    Q = omega0 / (2.0 * gamma)

    sag = m * g / k                       # static stretch under gravity
    # equilibrium: the spring must be stretched by `sag` to hold the magnet
    L_eq = anchor_z0 - (float(s["z_eq_m"]) + H / 2.0)
    L0 = L_eq - sag
    # recompute z_eq from L0 so the two definitions cannot disagree
    z_eq = anchor_z0 - H / 2.0 - L0 - sag
    A = z_release - z_eq

    spring_z0 = float(s["spring_z0_m"])
    spring_z1 = float(s["spring_z1_m"])

    out = dict(
        enabled=bool(s.get("enabled", True)),
        m=m, k=k, c=c_d, g=g, H=H,
        anchor_z0=anchor_z0, anchor_z1=anchor_z1,
        r_inner=float(s["spring_r_inner_m"]),
        r_outer=float(s["spring_r_outer_m"]),
        spring_z0=spring_z0, spring_z1=spring_z1,
        clamped=bool(s.get("clamped_boundary", True)),
        include_in_mesh=bool(s.get("include_in_mesh", False)),
        omega0=omega0, gamma=gamma, omega_d=omega_d,
        period=period, freq=1.0 / period, Q=Q,
        sag=sag, L_eq=L_eq, L0=L0,
        z_eq_m=z_eq, z_release_m=z_release, amplitude=A,
        z_min=z_eq - abs(A), z_max=z_eq + abs(A),
        L_min=anchor_z0 - (z_eq + abs(A) + H / 2.0),
        L_max=anchor_z0 - (z_eq - abs(A) + H / 2.0),
    )
    out["matc_expr"] = matc_expr(out)
    return out


def matc_expr(sp: dict, prefix: str = "") -> str:
    """MATC expression for the DISPLACEMENT from the initial mesh position.

    `tx` in Elmer's MATC is the current time.  The mesh is built with the
    magnet at z_release, so the displacement is z(t) - z_release.
    """
    zr = sp["z_release_m"]
    zq = sp["z_eq_m"]
    A = sp["amplitude"]
    ga = sp["gamma"]
    wd = sp["omega_d"]
    return (f"({zq - zr:.10g}) + ({A:.10g})*exp(-{ga:.10g}*tx)*"
            f"(cos({wd:.10g}*tx) + ({ga/wd:.10g})*sin({wd:.10g}*tx))")


def z_of_t(sp: dict, t):
    """Reference z(t) (magnet CENTRE) for plotting / verification."""
    return (sp["z_eq_m"] + sp["amplitude"]
            * math.exp(-sp["gamma"] * t)
            * (math.cos(sp["omega_d"] * t)
               + (sp["gamma"] / sp["omega_d"]) * math.sin(sp["omega_d"] * t)))


def v_of_t(sp: dict, t):
    """Reference z'(t)."""
    A, ga, wd, w0 = (sp["amplitude"], sp["gamma"],
                     sp["omega_d"], sp["omega0"])
    return -A * (w0 * w0 / wd) * math.exp(-ga * t) * math.sin(wd * t)


if __name__ == "__main__":
    sp = load_spring()
    print("=== spring-mass-damper from config.json ===")
    print(f"  m = {sp['m']} kg    k = {sp['k']} N/m    c = {sp['c']} N.s/m")
    print(f"  omega0 = {sp['omega0']:.4f} rad/s   T = {sp['period']:.4f} s"
          f"   f = {sp['freq']:.4f} Hz   Q = {sp['Q']:.1f}")
    print(f"  gamma  = {sp['gamma']:.4f} 1/s   omega_d = {sp['omega_d']:.4f}")
    print(f"  static sag  = {sp['sag']*1000:.2f} mm")
    print(f"  L_eq        = {sp['L_eq']*1000:.2f} mm"
          f"   L0 = {sp['L0']*1000:.2f} mm"
          f"   stretch = {sp['L_eq']/sp['L0']:.2f}x")
    print(f"  z_eq        = {sp['z_eq_m']*1000:.2f} mm")
    print(f"  amplitude   = {sp['amplitude']*1000:.2f} mm")
    print(f"  magnet centre sweeps {sp['z_min']:+.4f} .. {sp['z_max']:+.4f} m")
    print(f"  spring length       {sp['L_min']*1000:.1f} .. {sp['L_max']*1000:.1f} mm")
    print(f"  MATC displacement   \"{sp['matc_expr']}\"")
    print()
    print("  t(s)     z(t)      v(t)")
    for t in (0.0, 0.075, 0.15, 0.30, 0.45, 0.60):
        print(f"  {t:5.3f}  {z_of_t(sp, t):+9.6f}  {v_of_t(sp, t):+9.4f}")

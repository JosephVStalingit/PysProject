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

    m z'' = -m g + k (L - L0) - c z' - F_lenz
    L(z)  = anchor_z0 - (z + H_mag/2)          spring length

With no Lenz force the solution is the familiar damped oscillator

    z(t) = z_eq + A e^(-gamma t) [ cos(wd t) + (gamma/wd) sin(wd t) ]
    z'(t)= -A (omega0^2/wd) e^(-gamma t) sin(wd t)

    omega0 = sqrt(k/m)      gamma = c/(2m)      wd = sqrt(omega0^2-gamma^2)
    z_eq   = anchor_z0 - H_mag/2 - L0 - m g/k   (static equilibrium)
    A      = z_release - z_eq

NOTE ON SIGN: the magnet hangs from the anchor, so the spring PULLS UP (+z,
the anchor is at the top) while gravity pulls DOWN.  The `+k(L - L0)` above
is what makes the equilibrium restoring: substituting the config numbers
gives F(z) = -m g + k (L(z) - L0) = -220 (z - z_eq), i.e. the root sits at
z_eq = 0.024 m as designed.  (An earlier revision of this docstring wrote
`- k (L - L0)`, which is anti-restoring and puts the root at 0.0686 m --
wrong.  See the `_check_sign` block at the bottom of this file.)

The Lenz force is a pure velocity-proportional DRAG (see `b_em_from_linkage`)
so the ONLY place the coupled system differs from the analytic one above is
the effective damping:  c_eff = c + b_em.

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


def b_em_from_linkage(dlambda_dz: float, R_total: float) -> float:
    """Electromagnetic (Lenz) drag coefficient, F_lenz = -b_em * z'.

    The induced current dissipates P = eps^2 / R_total with eps = (dLambda/dz)
    * z', so the braking force is a pure velocity-proportional DRAG

        b_em = (dLambda/dz)^2 / R_total          [N.s/m]

    `dlambda_dz` is the FLUX LINKAGE gradient (N turns already included, so it
    scales with N); `R_total = R_load + r_coil`.  Because b_em goes as the
    square of the linkage gradient it grows like N^2, which is why the Lenz
    force matters most for the multi-turn coils.
    """
    if R_total <= 0.0:
        raise ValueError("R_total must be positive")
    return dlambda_dz * dlambda_dz / R_total


def coupled_z(sp: dict, b_em_of_z=None, t_end=None, dt=1.0e-5):
    """Integrate the COUPLED equation of motion (classical RK4).

        m z'' = -k (z - z_eq) - [ c + b_em(z) ] z'

    `b_em_of_z` maps z -> b_em [N.s/m]; pass None for the free oscillator, in
    which case the result must reproduce `z_of_t` / `v_of_t` (checked by
    `check_coupled`).  Returns (t, z, v) as plain lists so this module keeps
    its import-light, numpy-free character.
    """
    m, k, c = sp["m"], sp["k"], sp["c"]
    z_eq = sp["z_eq_m"]
    if t_end is None:
        t_end = 3.0 * sp["period"]
    n = int(round(t_end / dt))
    b = b_em_of_z or (lambda _z: 0.0)

    def acc(z, v):
        return (-k * (z - z_eq) - (c + b(z)) * v) / m

    t, z, v = 0.0, sp["z_release_m"], 0.0
    ts, zs, vs = [t], [z], [v]
    for _ in range(n):
        a1 = acc(z, v)
        z2, v2 = z + 0.5 * dt * v, v + 0.5 * dt * a1
        a2 = acc(z2, v2)
        z3, v3 = z + 0.5 * dt * v2, v + 0.5 * dt * a2
        a3 = acc(z3, v3)
        z4, v4 = z + dt * v3, v + dt * a3
        a4 = acc(z4, v4)
        z += dt / 6.0 * (v + 2.0 * v2 + 2.0 * v3 + v4)
        v += dt / 6.0 * (a1 + 2.0 * a2 + 2.0 * a3 + a4)
        t += dt
        ts.append(t)
        zs.append(z)
        vs.append(v)
    return ts, zs, vs


def matc_expr_gamma(sp: dict, gamma: float, prefix: str = "") -> str:
    """MATC displacement expression with an OVERRIDDEN decay rate.

    Adding the Lenz drag changes almost nothing except the decay rate, so a
    co-simulation pass keeps the analytic family and swaps

        gamma -> (c + b_em) / (2 m)

    omega_d is recomputed from the new gamma so the expression stays
    self-consistent (and z(0) = z_release, z'(0) = 0 are preserved for any
    gamma because the amplitude A is unchanged).
    """
    zr, zq, A = sp["z_release_m"], sp["z_eq_m"], sp["amplitude"]
    w0 = sp["omega0"]
    if gamma >= w0:
        raise ValueError("Over-damped: gamma >= omega0")
    wd = math.sqrt(w0 * w0 - gamma * gamma)
    return (f"({zq - zr:.10g}) + ({A:.10g})*exp(-{gamma:.10g}*tx)*"
            f"(cos({wd:.10g}*tx) + ({gamma / wd:.10g})*sin({wd:.10g}*tx))")


def analytic_z(sp: dict, t: float, gamma: float = None) -> float:
    """Analytic z(t), optionally with an overridden decay rate."""
    g = sp["gamma"] if gamma is None else gamma
    wd = math.sqrt(sp["omega0"] ** 2 - g * g)
    return (sp["z_eq_m"] + sp["amplitude"] * math.exp(-g * t)
            * (math.cos(wd * t) + (g / wd) * math.sin(wd * t)))


def fit_gamma(sp: dict, t, z, lo=None, hi=None, stride=1000, iters=80):
    """Least-squares decay rate of the analytic family best matching z(t).

    Golden-section search on the RMS residual (sampled every `stride` steps so
    the fit stays fast).  For b_em = 0 this must return `sp['gamma']`.
    """
    g0 = sp["gamma"]
    lo = 0.5 * g0 if lo is None else lo
    hi = 2.0 * g0 if hi is None else hi
    tt = t[::stride]
    zz = z[::stride]

    def err(g):
        return sum((zi - analytic_z(sp, ti, g)) ** 2
                   for ti, zi in zip(tt, zz)) / len(tt)

    invphi = (math.sqrt(5.0) - 1.0) / 2.0
    a, b = lo, hi
    c, d = b - invphi * (b - a), a + invphi * (b - a)
    fc, fd = err(c), err(d)
    for _ in range(iters):
        if b - a < 1.0e-15 * max(1.0, abs(a)):
            break
        if fc < fd:
            b, d, fd = d, c, fc
            c = b - invphi * (b - a)
            fc = err(c)
        else:
            a, c, fc = c, d, fd
            d = a + invphi * (b - a)
            fd = err(d)
    gm = 0.5 * (a + b)
    return gm, err(gm)


def check_sign(sp: dict) -> dict:
    """Guard the `+- k(L - L0)` sign.

    The magnet hangs from the TOP, so the spring pulls UP (+z) while gravity
    pulls DOWN: the equation of motion is

        m z'' = -m g + k (L - L0)

    and this must (a) have its root exactly at z_eq and (b) be RESTORING
    (slope < 0).  A `- k (L - L0)` sign slip would put the root at 0.0686 m
    with a POSITIVE slope, i.e. an unstable runaway -- worth a guard, because
    the sign is easy to get wrong when implementing the coupled ODE.
    """
    m, k, g = sp["m"], sp["k"], sp["g"]
    L0, az0, H = sp["L0"], sp["anchor_z0"], sp["H"]

    def force(z):
        return -m * g + k * ((az0 - (z + H / 2.0)) - L0)

    root = (az0 - H / 2.0) - L0 - m * g / k
    slope = (force(root + 1.0e-7) - force(root - 1.0e-7)) / 2.0e-7
    return dict(root=root, slope=slope,
                force_at_zeq=force(sp["z_eq_m"]),
                restoring=slope < 0.0,
                root_matches_zeq=abs(root - sp["z_eq_m"]) < 1.0e-12)


def check_coupled(sp: dict, dt=1.0e-5):
    """With b_em = 0 the RK4 integrator must reproduce the analytic solution."""
    t, z, v = coupled_z(sp, None, t_end=sp["period"], dt=dt)
    ez = ev = 0.0
    for i in range(0, len(t), max(1, len(t) // 2000)):
        ez = max(ez, abs(z[i] - z_of_t(sp, t[i])))
        ev = max(ev, abs(v[i] - v_of_t(sp, t[i])))
    return ez, ev


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

    print()
    print("=== sign guard (m z'' = -m g + k(L - L0)) ===")
    ck = check_sign(sp)
    print(f"  force root      = {ck['root']*1000:+.6f} mm"
          f"   (z_eq = {sp['z_eq_m']*1000:+.6f} mm)"
          f"   match = {ck['root_matches_zeq']}")
    print(f"  dF/dz           = {ck['slope']:+.3f} N/m   (k = +{sp['k']:.1f})"
          f"   restoring = {ck['restoring']}")
    print(f"  F(z_eq)         = {ck['force_at_zeq']:+.3e} N")

    print()
    print("=== RK4 integrator vs analytic (b_em = 0, one period) ===")
    ez, ev = check_coupled(sp)
    print(f"  max |z_RK4 - z_an| = {ez:.3e} m     (amplitude {sp['amplitude']:.4f} m)")
    print(f"  max |v_RK4 - v_an| = {ev:.3e} m/s")
    tt, zz, _vv = coupled_z(sp, None, t_end=sp["period"])
    gm, res = fit_gamma(sp, tt, zz)
    print(f"  fitted gamma       = {gm:.10f}   (expected {sp['gamma']:.10f})"
          f"   residual = {res:.3e}")

    print()
    print("=== coupled MATC (pass 2 template, b_em = 0 for now) ===")
    print(f"  \"{matc_expr_gamma(sp, sp['gamma'])}\"")

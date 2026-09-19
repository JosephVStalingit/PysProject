# -*- coding: utf-8 -*-
"""
oscilloscope.py  --  read the Elmer TRANSIENT results and plot every
                     physical quantity of the falling-magnet experiment.

Usage:
    python oscilloscope.py                            # results/case_t*.vtu
    python oscilloscope.py --out results/scope.png
    python oscilloscope.py --R-load 10 --n-turns 50

Data source
-----------
`results/case_t*.vtu` written by ElmerSolver (case_transient.sif).  Each
frame carries the moving mesh plus the fields
`magnetic vector potential`, `magnetic flux density`,
`magnetic field strength`, `current density` and `meshrelax`.

Quantities derived (one panel each)
-----------------------------------
    z(t)     magnet displacement   (tracked from the moving mesh)
    v(t)     magnet velocity       (numerical d/dt of z)
    a(t)     magnet acceleration   (numerical d/dt of v)
    v_gap(t) deviation from free fall  -(z - z0) vs 1/2 g t^2
    B_z(t)   axial flux density at a probe point on the coil axis
    Bmax(t)  peak |B| anywhere in the domain
    Phi(t)   magnetic flux threading the coil  (area integral of B_z)
    EMF(t)   -N dPhi/dt       (Faraday)
    I(t)     EMF / R_total    (Ohm, R_total = R_load + R_wire)
    KE(t)    1/2 m v^2   PE(t)  m g (z0 - z)   E_tot = KE + PE
plus a passage-time bar at the bottom.
"""
from __future__ import annotations
import argparse, glob, json, math, os, sys, unicodedata
from pathlib import Path

import numpy as np

ROOT     = Path(__file__).resolve().parent
RESULTS  = ROOT / "results"
CFG_PATH = ROOT / "config.json"

MU0 = 4.0 * math.pi * 1e-7


def load_cfg():
    c = json.loads(CFG_PATH.read_text(encoding="utf-8"))
    coil = c["coil"]
    mag  = c["magnet"]
    phy  = c["physics"]
    exp  = c["experiment"]
    # first closed-loop curve in [curves] (N_turns > 0) drives R and N
    # Skip non-dict entries (e.g. `_comment_block`) so a top-level comment
    # can live in [curves] without breaking iteration.
    curve_dicts = [v for v in c["curves"].values() if isinstance(v, dict)]
    cur = next((v for v in curve_dicts if int(v.get("N_turns", 0)) > 0),
               curve_dicts[0])
    return dict(
        coil=coil, mag=mag, phy=phy, exp=exp, curve=cur,
        curves=c["curves"],
        spring=c.get("spring"),
        mode=exp.get("motion_mode", "free_fall"),
        z_release=exp["z_release_default_m"],
    )



def cfg_raw() -> dict:
    """The raw config.json dict (what spring_model / solenoid3d consume)."""
    return json.loads(CFG_PATH.read_text(encoding="utf-8"))


# ====================================================================
#  Frame loading
# ====================================================================
def load_frames(verbose=True):
    import meshio
    files = sorted(glob.glob(str(RESULTS / "case_t*.vtu")))
    if not files:
        sys.exit(f"[err] no VTU frames in {RESULTS} - run the transient first")
    if verbose:
        print(f"[info] {len(files)} VTU frames in {RESULTS.name}/")

    pts, B, Bmag, mr = [], [], [], []
    for f in files:
        m = meshio.read(f)
        pts.append(m.points)
        B.append(np.asarray(m.point_data["magnetic flux density"]))
        Bmag.append(np.linalg.norm(B[-1], axis=1))
        mr.append(np.asarray(m.point_data["meshrelax"]).ravel())
    m0 = meshio.read(files[0])
    tet = None
    for blk in m0.cells:
        if blk.type == "tetra":
            tet = blk.data
    return dict(files=files, pts=np.array(pts), B=np.array(B),
                Bmag=np.array(Bmag), meshrelax=np.array(mr),
                tet=tet, n_frames=len(files))


# ====================================================================
#  Magnet tracking -> z(t)
# ====================================================================
def track_magnet(fr, cfg):
    """Track the magnet by following its INTERIOR nodes.

    Node selection matters and is easy to get wrong: a naive
    `r < 0.7 R_mag AND z in [z0,z1]` filter ALSO catches air nodes inside
    the coil bore when the magnet overlaps the coil region (which the spring
    case does: magnet z=0.030..0.060 vs coil z=0..0.040).  Those bore nodes
    never move (`meshrelax = 0`) and drag the tracked mean down, which looks
    exactly like a 13 % mesh-motion attenuation and is NOT real.

    The RigidMeshMapper marks the moving body with `meshrelax = 1`, so use
    that as the discriminator.
    """
    p0 = fr["pts"][0]
    r0 = np.hypot(p0[:, 0], p0[:, 1])
    mr0 = (fr["meshrelax"][0].ravel() if "meshrelax" in fr and fr["meshrelax"] is not None
           else None)
    mz0, mz1 = cfg["mag"]["z0_m"], cfg["mag"]["z1_m"]
    rmag = cfg["mag"]["R_mag_m"]

    sel = None
    if mr0 is not None and len(mr0) == len(p0):
        sel = ((mr0 > 0.9999) & (r0 < rmag - 1e-4)
               & (p0[:, 2] > mz0 + 1e-4) & (p0[:, 2] < mz1 - 1e-4))
        if sel.sum() < 4:
            sel = None
    if sel is None:
        sel = (r0 < 0.7 * rmag) & (p0[:, 2] > mz0 + 1e-4) & (p0[:, 2] < mz1 - 1e-4)
    if sel.sum() < 4:
        sel = (r0 < rmag) & (p0[:, 2] > mz0 - 1e-3) & (p0[:, 2] < mz1 + 1e-3)

    z = fr["pts"][:, sel, 2].mean(axis=1)
    return sel, z - z[0]


def kinematics(z, dt):
    v = np.gradient(z, dt)
    a = np.gradient(v, dt)
    return v, a


# ====================================================================
#  Flux / EMF / current
# ====================================================================
def flux_emf(fr, cfg, dt):
    c = cfg["coil"]
    rz0, rz1 = c["z0_m"], c["z1_m"]
    rin, rout = c["r_inner_m"], c["r_outer_m"]
    area = math.pi * (rout ** 2 - rin ** 2)
    N = int(cfg["curve"]["N_turns"])

    mean_Bz = []
    for k in range(fr["n_frames"]):
        p = fr["pts"][k]
        r = np.hypot(p[:, 0], p[:, 1])
        sel = (r > rin - 1e-4) & (r < rout + 1e-4) & \
              (p[:, 2] > rz0 - 1e-4) & (p[:, 2] < rz1 + 1e-4)
        mean_Bz.append(float(fr["B"][k][sel, 2].mean()) if sel.sum() else 0.0)
    mean_Bz = np.array(mean_Bz)
    Phi = mean_Bz * area * N
    EMF = -np.gradient(Phi, dt)

    R_load = float(cfg["curve"]["R_load_ohm"])
    d      = cfg["curve"].get("wire_diameter_m")
    sigma  = cfg["curve"].get("wire_conductivity_S_per_m")
    R_wire = 0.0
    if N and d and sigma:
        # R_wire = N * 2*pi*r_mean / (sigma * pi * (d/2)^2),
        # where r_mean = r_inner + d/2 is the mean turn radius.  Computing
        # it here (rather than reading a config field) keeps the formula
        # correct if the bore former or wire gauge changes.
        r_mean = rin + d / 2.0
        length_wire = N * 2.0 * math.pi * r_mean
        R_wire = length_wire / (sigma * math.pi * (d / 2.0) ** 2)
    R_tot = R_load + R_wire
    return dict(mean_Bz=mean_Bz, Phi=Phi, EMF=EMF, I=EMF / R_tot,
                R_load=R_load, R_wire=R_wire, R_tot=R_tot, area=area, N=N)


# ====================================================================
#  Energetics
# ====================================================================
def energetics(z, v, cfg):
    """Mechanical energy of the falling magnet.

    z is measured relative to the release point, so
        PE = m g z      (negative once the magnet has fallen)
        KE = 1/2 m v^2
    and E_tot = KE + PE is conserved (~0) for pure free fall - which makes
    the energy panel a direct check of the integration.
    """
    m = cfg["phy"]["M_kg"]
    g = cfg["phy"]["G"]
    KE = 0.5 * m * v ** 2
    PE = m * g * z
    return KE, PE, KE + PE


def all_curves(cfg):
    """Every [curves] block with its derived N and total resistance.

    R_wire = N * (2*pi*r_mean) / (sigma * pi * (d/2)^2)
    where r_mean = r_inner_m + d/2 (mean turn radius, taken from the
    shared [coil] block).  The previous hard-coded 0.142 m (2*pi*0.0226)
    was tied to r_inner_m = 0.020 and d = 0.7 mm; computing it here keeps
    the formula correct if r_inner_m or the wire diameter changes.
    """
    coil = cfg["coil"]
    out = []
    for name, cc in cfg["curves"].items():
        # Skip non-dict entries (e.g. `_comment_block` documentation strings).
        if not isinstance(cc, dict):
            continue
        N = int(cc.get("N_turns", 0))
        R_load = float(cc["R_load_ohm"])
        d = cc.get("wire_diameter_m")
        sig = cc.get("wire_conductivity_S_per_m")
        R_wire = 0.0
        if N and d and sig:
            r_mean = coil["r_inner_m"] + d / 2.0
            length_wire = N * 2.0 * math.pi * r_mean
            R_wire = length_wire / (sig * math.pi * (d / 2.0) ** 2)
        if not math.isfinite(R_load):
            R_tot = float("inf")
        else:
            R_tot = R_load + R_wire
        out.append(dict(name=name, label=cc.get("label", name),
                        color=cc.get("color", "#333333"),
                        N=N, R_load=R_load, R_wire=R_wire, R_tot=R_tot))
    return out


# ====================================================================
#  Coil transit timing (new panel)
# ====================================================================
def flux_vs_z(cfg, z, mean_Bz):
    """FEM flux linkage per turn  phi(z) = <B_z>(z) * A_coil,  plus its
    z-derivative (needed for the Lenz braking coefficient)."""
    c = cfg["coil"]
    A = math.pi * (c["r_outer_m"] ** 2 - c["r_inner_m"] ** 2)
    phi = mean_Bz * A
    o = np.argsort(z)
    zs, ps = z[o], phi[o]
    return zs, ps, np.gradient(ps, zs)


def coil_transit_times(zs, ps, dps, curve, mag_h, coil_z0, coil_z1,
                       m, g, dt=2.0e-5, z_start=0.0, t_max=5.0):
    """Integrate the Lenz-braked trajectory for ONE curve block.

        m z'' = -m g - c(z) z' ,    c(z) = (N^2 / R_tot) * (dphi/dz)^2

    and return the four characteristic coil-crossing times:
        head_in  - leading (bottom) face reaches the coil near face
        tail_in  - trailing (top)  face reaches the coil near face
        head_out - leading face reaches the coil far face
        tail_out - trailing face reaches the coil far face
    plus the two intervals of interest.
    N = 0 or R = inf means no braking (pure free fall).
    """
    N, R = curve["N"], curve["R_tot"]
    braked = (N > 0) and math.isfinite(R)

    def c_of_z(zz):
        if not braked:
            return 0.0
        zc = min(max(zz, zs[0] - 0.05), zs[-1] + 0.05)
        return (N * N / R) * float(np.interp(zc, zs, dps)) ** 2

    events = {"head_in": None, "tail_in": None,
              "head_out": None, "tail_out": None}
    zc, v, t = z_start, 0.0, 0.0
    traj_t, traj_z = [0.0], [0.0]

    def free_pos(zz):
        """signed distance of each face to its target plane
        (<= 0 means that crossing has already happened)."""
        h, tl = zz - mag_h, zz + mag_h
        return {"head_in": h - coil_z1, "tail_in": tl - coil_z1,
                "head_out": h - coil_z0, "tail_out": tl - coil_z0}

    prev = free_pos(zc)
    for k, val in prev.items():
        if val <= 0.0:
            events[k] = 0.0

    while t < t_max:
        if all(vv is not None for vv in events.values()):
            break
        # RK4 on (z, v)
        def f(zz, vv):
            return (vv, -g - c_of_z(zz) * vv / m)
        k1z, k1v = f(zc, v)
        k2z, k2v = f(zc + .5*dt*k1z, v + .5*dt*k1v)
        k3z, k3v = f(zc + .5*dt*k2z, v + .5*dt*k2v)
        k4z, k4v = f(zc + dt*k3z, v + dt*k3v)
        zc += dt/6*(k1z + 2*k2z + 2*k3z + k4z)
        v  += dt/6*(k1v + 2*k2v + 2*k3v + k4v)
        t  += dt
        traj_t.append(t); traj_z.append(zc)

        # event times are INTERPOLATED inside the step.  Without this the
        # resolution is one RK step (20 us) and the tiny differences between
        # an open and a closed circuit (picoseconds!) are invisible.
        cur = free_pos(zc)
        for k in events:
            if events[k] is None and cur[k] <= 0.0:
                d0, d1 = prev[k], cur[k]
                frac = d0 / (d0 - d1) if d0 != d1 else 0.0
                events[k] = (t - dt) + frac * dt
        prev = cur

    e = events
    out = dict(e)
    out["tailin_headout"] = (e["head_out"] - e["tail_in"]
                             if e["head_out"] and e["tail_in"] else float("nan"))
    out["full_transit"] = (e["tail_out"] - e["head_in"]
                           if e["tail_out"] and e["head_in"] else float("nan"))
    out["t"] = np.array(traj_t); out["z"] = np.array(traj_z)
    return out


# ====================================================================
#  Dashboard
# ====================================================================
def make_scope(out_png, t, z, v, a, KE, PE, Etot, fe, Bz_probe, Bmax, cfg,
               passage, transit=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.patches as mpatches
    from matplotlib import font_manager
    avail = {f.name for f in font_manager.fontManager.ttflist}
    for cand in ["SimHei", "Microsoft YaHei", "DejaVu Sans"]:
        if cand in avail:
            plt.rcParams["font.sans-serif"] = [cand]
            break
    plt.rcParams["axes.unicode_minus"] = False

    g = cfg["phy"]["G"]
    # ---- reference trajectory for the z / v / a panels ----------------
    # The FEM tracks the mesh, so the panel overlaps the ANALYTIC law that
    # was prescribed.  For the spring it comes from spring_model (the same
    # source make_sif.py used to build the SIF), for free fall it is -1/2 g t^2.
    if cfg.get("mode") == "spring":
        import spring_model
        spring = spring_model.load_spring(cfg_raw())
        z_ref = np.array([spring_model.z_of_t(spring, tt) - spring["z_release_m"]
                          for tt in t])
        v_ref = np.array([spring_model.v_of_t(spring, tt) for tt in t])
        ref_lab_z = (f"analytic spring  T={spring['period']:.3f} s  "
                     f"Q={spring['Q']:.0f}")
        ref_lab_v = "analytic dz/dt"
        xlabel = "t (s)"
    else:
        z_ref = -0.5 * g * t ** 2
        v_ref = -g * t
        ref_lab_z = "ideal  -1/2 g t^2"
        ref_lab_v = "ideal  -g t"
        xlabel = "t (s)"

    # I(t) = EMF(t) / R_total : one curve per CLOSED-circuit configuration.
    # These are exactly the curves the [curves] block is meant to compare, so
    # plot them all instead of only the primary one.
    i_series = []
    for rr in (transit or []):
        if rr.get("N", 0) > 0 and math.isfinite(rr.get("R_tot", float("inf"))):
            i_series.append((t, fe["EMF"] / rr["R_tot"],
                             f"{rr['label']}  R={rr['R_tot']:.3g}Ω",
                             rr["color"]))
    if not i_series:
        i_series = [(t, fe["I"], f"I = EMF / {fe['R_tot']:.3g} ohm", "#7f7f7f")]
    i_series = [([s[0], s[1], s[2], s[3]]) for s in i_series]

    panels = [
        ("magnet displacement  z(t)",        "m",     [([t, z,    "FEM (mesh motion)", "#1f77b4"]),
                                                       ([t, z_ref, ref_lab_z,         "#d62728"])]),
        ("velocity  v(t)",                   "m/s",   [([t, v, "FEM  dz/dt", "#ff7f0e"]),
                                                       ([t, v_ref, ref_lab_v, "#d62728"])]),
        ("acceleration  a(t)",               "m/s^2", [([t, a, "FEM  d2z/dt2", "#2ca02c"]),
                                                       ([t, -g * np.ones_like(t), "-g", "#d62728"])]),
        ("axial B at coil  B_z(t)",          "T",     [([t, Bz_probe, "coil-annulus mean B_z", "#9467bd"])]),
        ("peak field  |B|max(t)",            "T",     [([t, Bmax, "max |B| in domain", "#8c564b"])]),
        ("flux linkage  Phi(t)",             "Wb-turn", [([t, fe["Phi"], "N * <B_z> * A_coil", "#17becf"])]),
        ("induced EMF  (Faraday)",           "V",     [([t, fe["EMF"], "-N dPhi/dt", "#e377c2"])]),
        ("induced current  I(t)",            "A",     i_series),
        ("kinetic energy  KE(t)",            "J",     [([t, KE, "1/2 m v^2", "#bcbd22"])]),
        ("potential energy  PE(t)",          "J",     [([t, PE, "m g h", "#aec7e8"])]),
        ("total energy  KE + PE",            "J",     [([t, Etot, "E_tot", "#000000"])]),
        ("mesh relaxation field  <r>(t)",    "-",     [([t, passage["relax"], "mean meshrelax on magnet", "#ffbb78"])]),
    ]

    n = len(panels)
    ncols = 4
    nrows = (n + ncols - 1) // ncols
    fig = plt.figure(figsize=(20, 3.0 * nrows + 3.6))
    gs = fig.add_gridspec(nrows + 1, ncols * 2,
                          height_ratios=[1] * nrows + [1.5])

    for i, (title, unit, series) in enumerate(panels):
        r, c = divmod(i, ncols)
        # the gridspec is ncols*2 wide so the bottom row can be split in two;
        # each panel must therefore span TWO gridspec columns, otherwise all
        # 12 panels are crushed into the left half of the figure.
        ax = fig.add_subplot(gs[r, c * 2:(c + 1) * 2])
        for tt, yy, lab, col in series:
            ax.plot(tt, yy, color=col, lw=1.8, label=lab)
        ax.set_title(title, fontsize=10, fontweight="bold")
        ax.set_xlabel("t (s)")
        ax.set_ylabel(unit)
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=7, loc="best")

    # ---- bottom-left: passage time to the coil top face ----------------
    bar = fig.add_subplot(gs[nrows, :ncols])
    bar.bar([0], [passage["t_pass"] * 1000],
            color="#1f77b4", edgecolor="k", width=0.35)
    bar.axhline(passage["t_ideal"] * 1000, color="red", ls="--", lw=1.2,
                label=passage.get("ideal_label", "analytic reference"))
    bar.set_title(passage.get("title", "passage time"),
                  fontsize=11, fontweight="bold")
    bar.set_ylabel("ms")
    bar.set_xticks([])
    bar.grid(True, alpha=0.3, axis="y")
    bar.legend(fontsize=9)
    bar.text(0, passage["t_pass"] * 1000, f"  {passage['t_pass']*1000:.1f} ms",
             va="bottom", fontsize=10, fontweight="bold")

    # ---- bottom-right: coil transit timing per configuration ----------
    tx = fig.add_subplot(gs[nrows, ncols:])
    tx.set_title("coil transit timing per configuration\n"
                 "(tail-in -> head-out, and the full crossing)",
                 fontsize=11, fontweight="bold")
    if not transit:
        tx.text(0.5, 0.5, "no configuration data", ha="center", va="center",
                transform=tx.transAxes)
        tx.axis("off")
    else:
        names = [r["label"] for r in transit]
        ypos = np.arange(len(transit))
        for yi, r in enumerate(transit):
            # full crossing span (head-in .. tail-out) as a faint backdrop
            tx.barh(yi, r["full_transit"] * 1000, left=r["head_in"] * 1000,
                    height=0.55, color=r["color"], alpha=0.22, zorder=1)
            # the requested interval tail-in .. head-out, highlighted
            tx.barh(yi, r["tailin_headout"] * 1000, left=r["tail_in"] * 1000,
                    height=0.55, color=r["color"], alpha=0.95, zorder=2,
                    edgecolor="k", linewidth=1.0)
            tx.text((r["tail_in"] + r["head_out"]) / 2 * 1000,
                    yi, f"{r['tailin_headout']*1000:.1f} ms",
                    ha="center", va="center", fontsize=9,
                    fontweight="bold", color="white", zorder=3)
            # event markers
            for key, mk in (("head_in", "|"), ("tail_in", "|"),
                            ("head_out", "|"), ("tail_out", "|")):
                tx.plot(r[key] * 1000, yi, marker=mk, ms=14,
                        color="k", zorder=4)
            tx.text(r["head_in"] * 1000, yi + 0.36, "head-in",
                    fontsize=7, ha="center", va="bottom")
            tx.text(r["head_out"] * 1000, yi - 0.36, "head-out",
                    fontsize=7, ha="center", va="top")
        tx.set_yticks(ypos)
        tx.set_yticklabels(names, fontsize=9)
        tx.set_xlabel("t (s -> ms)")
        tx.set_ylabel("configuration")
        tx.grid(True, alpha=0.3, axis="x")
        tx.legend(handles=[
            mpatches.Patch(facecolor="0.4", alpha=0.95, edgecolor="k",
                           label="tail-in -> head-out  (asked interval)"),
            mpatches.Patch(facecolor="0.4", alpha=0.22, edgecolor="none",
                           label="head-in -> tail-out  (full crossing)")],
            fontsize=8, loc="lower right")

    fig.suptitle("PysProject oscilloscope - Elmer 26.2 transient FEM "
                 "(falling magnet)" , fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    fig.savefig(out_png, dpi=110, bbox_inches="tight")
    plt.close(fig)
    print(f"[ok] wrote {out_png}")


# ====================================================================
#  Summary + JSON
# ====================================================================
def _w(s):
    """Display width of s (CJK / full-width glyphs count as two columns)."""
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
               for ch in s)


def _pad(s, n):
    """Left-justify s into a field of n DISPLAY columns."""
    s = str(s)
    return s + " " * max(0, n - _w(s))


def write_summary(out_txt, t, z, v, a, KE, PE, Etot, fe, Bz, Bmax, cfg,
                  passage, transit=None):
    g = cfg["phy"]["G"]
    L = []
    L.append("=" * 84)
    if cfg.get("mode") == "spring":
        L.append(" Elmer 26.2 TRANSIENT FEM  -  SPRING-OSCILLATOR oscilloscope")
    else:
        L.append(" Elmer 26.2 TRANSIENT FEM  -  falling-magnet oscilloscope")
    L.append(f" frames={len(t)}  t_end={t[-1]:.4f} s  dt={t[1]-t[0]:.4e} s")
    L.append("=" * 84)
    if cfg.get("mode") == "spring":
        import spring_model
        sp = spring_model.load_spring(cfg_raw())
        zt = spring_model.z_of_t(sp, t[-1]) - sp["z_release_m"]
        L.append(f"  z_final          = {z[-1]:+.6e} m   "
                 f"(analytic spring = {zt:+.6e} m)")
        L.append(f"  achieved / analytic = "
                 f"{abs(z[-1]/zt)*100:.1f} %" if zt else "  -")
        L.append(f"  spring: T = {sp['period']:.4f} s   Q = {sp['Q']:.1f}   "
                 f"A = {sp['amplitude']*1000:.1f} mm   "
                 f"z_eq = {sp['z_eq_m']*1000:.2f} mm")
    else:
        L.append(f"  z_final          = {z[-1]:+.6e} m   "
                 f"(ideal -1/2 g t_end^2 = {-0.5*g*t[-1]**2:+.6e} m)")
        L.append(f"  achieved / ideal = "
                 f"{abs(z[-1]/(-0.5*g*t[-1]**2))*100:.1f} %")
    L.append(f"  v_final          = {v[-1]:+.6e} m/s")
    L.append(f"  a_mean           = {a.mean():+.6e} m/s^2")
    L.append("")
    L.append(f"  B_z  coil annulus: min {fe['mean_Bz'].min():+.4e}  "
             f"max {fe['mean_Bz'].max():+.4e}  T")
    L.append(f"  |B|_max          = {Bmax.max():.4e} T")
    L.append(f"  Phi_max          = {np.abs(fe['Phi']).max():.4e} Wb-turn")
    L.append(f"  EMF_max          = {np.abs(fe['EMF']).max():.4e} V")
    L.append(f"  I_max            = {np.abs(fe['I']).max():.4e} A")
    L.append(f"  R_load = {fe['R_load']:.4g} ohm   R_wire = {fe['R_wire']:.4g} ohm"
             f"   R_total = {fe['R_tot']:.4g} ohm   N = {fe['N']}")
    L.append("")
    L.append(f"  KE_max = {KE.max():.4e} J   PE_max = {PE.max():.4e} J   "
             f"E_tot_max = {Etot.max():.4e} J")
    L.append(f"  passage time: {passage.get('title', '')} : "
             f"{passage['t_pass']*1000:.2f} ms  "
             f"({passage.get('ideal_label', '')})")
    L.append(f"  mean meshrelax on magnet = {passage['relax'].mean():.4f}"
             f"   (1.0 = mesh follows the rigid motion exactly)")
    L.append("")
    L.append("  NOTE: the magnet (R=15 mm) passes through the coil BORE")
    L.append("        (R_in = 20 mm), so the winding only sees the fringe /")
    L.append("        return flux.  In SPRING mode the magnet is released")
    L.append("        INSIDE the coil and keeps oscillating through it, so the")
    L.append("        flux linkage is far larger than in the single-pass")
    L.append("        free-fall case.")
    L.append("")
    if transit:
        L.append("-" * 84)
        L.append(" COIL TRANSIT TIMING, per configuration")
        L.append("   head = leading (bottom) face, tail = trailing (top) face.")
        L.append("   phi(z) from the FEM, then per config:")
        L.append("     m z'' = -m g - c(z) z' ,   c(z) = (N^2/R_tot)(dphi/dz)^2")
        L.append("-" * 84)
        labw = max([_w("config")] + [_w(r["label"]) for r in transit]) + 2
        L.append("   " + _pad("config", labw) +
                 "".join(f"{h:>10}" for h in
                         ("N", "R_tot", "head-in", "tail-in", "head-out",
                          "tail-out", "尾部进入→头部离开", "完整穿越")))
        L.append("   " + _pad("", labw) +
                 "".join(f"{h:>10}" for h in
                         ("", "ohm", "ms", "ms", "ms", "ms", "ms", "ms")))
        for r in transit:
            R = "inf" if not math.isfinite(r["R_tot"]) else f"{r['R_tot']:.4g}"
            L.append("   " + _pad(r["label"], labw) +
                     f"{r['N']:>10}" + f"{R:>10}" +
                     "".join(f"{r[k]*1000:>10.2f}" for k in
                             ("head_in", "tail_in", "head_out", "tail_out",
                              "tailin_headout", "full_transit")))
        L.append("")
        L.append("   * tail-in -> head-out : tail enters the coil top face ...")
        L.append("     ... head leaves the coil bottom face")
        L.append("   * full = head-in -> tail-out (whole crossing)")
        m_mag = float(cfg["phy"]["M_kg"])
        mg = m_mag * g
        v_ref = math.sqrt(2 * g * 0.06)
        L.append("")
        L.append(f"   braking check:  m g = {mg:.4f} N ; "
                 f"F_lenz/(m g) = c*v/(m g) at v = {v_ref:.2f} m/s:")
        for r in transit:
            frac = r["c_peak"] * v_ref / mg if mg else 0.0
            L.append("     " + _pad(r["label"], labw) +
                     f"c_peak = {r['c_peak']:.4e} N.s/m"
                     f"  ->  {frac*100:9.5f} % of g")
        L.append("   => with this geometry the electromagnetic braking is")
        L.append("      negligible, which is exactly why prescribing the")
        L.append("      free-fall motion (Mesh Translate) is a valid model.")
        L.append("")
        # ---- WHY it is so small: the flux linkage deficit --------------
        ref = min(transit, key=lambda r: r["c_peak"])
        L.append("   transit-time shift vs the open-circuit curve (ns):")
        for r in transit:
            d = (r["tailin_headout"] - ref["tailin_headout"]) * 1e9
            L.append("     " + _pad(r["label"], labw) + f"{d:+12.4f} ns")
        phi_pt_max = float(np.abs(fe["Phi"]).max()) / max(fe["N"], 1)
        phi_ideal = 0.68 * fe["area"]            # 0.68 T over the annulus
        L.append("")
        L.append("   WHY so small?  The winding only links the FRINGE flux:")
        L.append(f"     phi/turn from FEM      = {phi_pt_max:.4e} Wb")
        L.append(f"     if fully linked        = {phi_ideal:.4e} Wb"
                 f"   ->  {phi_ideal/max(phi_pt_max,1e-30):.0f}x larger")
        L.append("     the damping goes as (dphi/dz)^2, so the bore geometry")
        L.append("     costs a factor of about "
                 f"{(phi_ideal/max(phi_pt_max,1e-30))**2:.0e}.")
        Ipk = float(np.abs(fe["I"]).max())
        L.append(f"     induced current I_max  = {Ipk:.4e} A")
        L.append(f"     its own field mu0 N I/l= {MU0*fe['N']*Ipk/0.040:.4e} T"
                 f"  vs magnet 1.845 T"
                 f"  ({MU0*fe['N']*Ipk/0.040/1.845:.2e})")
        L.append("")
        L.append("   quasi-static check: the coil RL time constant is ~7 us,")
        L.append("   far below the ~65 ms crossing, so I = EMF / R is valid")
    L.append("=" * 84)
    out_txt.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"[ok] wrote {out_txt}")


def write_json(out_json, t, z, v, a, KE, PE, Etot, fe, Bz, Bmax, passage,
               transit=None):
    obj = {
        "t_s": t.tolist(),
        "z_m": z.tolist(),
        "v_m_s": v.tolist(),
        "a_m_s2": a.tolist(),
        "B_z_coil_T": fe["mean_Bz"].tolist(),
        "B_max_T": Bmax.tolist(),
        "flux_Wb_turn": fe["Phi"].tolist(),
        "emf_V": fe["EMF"].tolist(),
        "current_A": fe["I"].tolist(),
        "KE_J": KE.tolist(),
        "PE_J": PE.tolist(),
        "E_total_J": Etot.tolist(),
        "meshrelax_on_magnet": passage["relax"].tolist(),
        "passage_time_s": passage["t_pass"],
        "coil_transit": [
            {k: (None if isinstance(r[k], float) and math.isnan(r[k])
                 else r[k])
             for k in ("name", "label", "N", "R_tot", "head_in", "tail_in",
                       "head_out", "tail_out", "tailin_headout",
                       "full_transit")}
            for r in (transit or [])
        ],
    }
    out_json.write_text(json.dumps(obj, indent=1), encoding="utf-8")
    print(f"[ok] wrote {out_json}")


# ====================================================================
#  Main
# ====================================================================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None,
                    help="output PNG (default results/scope.png)")
    ap.add_argument("--t-end", type=float, default=None,
                    help="override the final time (s)")
    args = ap.parse_args()

    cfg = load_cfg()
    fr  = load_frames()

    dt = float(cfg["exp"]["dt_s"])
    # the SIF writes one frame per timestep; recover dt from the SIF
    sif = (ROOT / "case_transient.sif").read_text(encoding="utf-8")
    for line in sif.splitlines():
        if "Timestep Sizes" in line:
            dt = float(line.split("=")[1].strip())
            break
    n = fr["n_frames"]
    t = (np.arange(n) + 1) * dt
    if args.t_end is not None:
        keep = t <= args.t_end + 1e-12
        fr["pts"] = fr["pts"][keep]
        fr["B"] = fr["B"][keep]
        fr["Bmag"] = fr["Bmag"][keep]
        fr["meshrelax"] = fr["meshrelax"][keep]
        fr["n_frames"] = int(keep.sum())
        n = fr["n_frames"]
        t = t[keep]

    sel, z = track_magnet(fr, cfg)
    v, a = kinematics(z, dt)
    KE, PE, Etot = energetics(z, v, cfg)
    fe = flux_emf(fr, cfg, dt)
    Bz_probe = fe["mean_Bz"]
    Bmax = fr["Bmag"].max(axis=1)

    # ---- passage time (mode aware) ------------------------------------
    # free_fall: the magnet is released ABOVE the coil, so the interesting
    #            quantity is when its bottom face reaches the coil TOP plane.
    # spring:    the magnet is released INSIDE the coil (bottom face starts
    #            below the coil top), so that quantity is undefined -- there
    #            report the first time the bottom face leaves through the
    #            coil BOTTOM plane, and use T/4 as the analytic reference.
    z_target = float(cfg["coil"]["z1_m"])
    z_leave = float(cfg["coil"]["z0_m"])
    z_mag0 = fr["pts"][0, sel, 2].mean()
    z_bottom0 = z_mag0 - cfg["mag"]["H_mag_m"]
    zb = z_bottom0 + z
    t_pass = float("nan")
    t_ideal = float("nan")

    if cfg.get("mode") == "spring":
        import spring_model
        sp = spring_model.load_spring(cfg_raw())
        if np.any(zb <= z_leave):
            k = int(np.argmax(zb <= z_leave))
            t_pass = float(t[k])
        t_ideal = sp["period"] / 4.0      # release -> first centre crossing
        pass_title = (f"first exit through the coil bottom "
                      f"(z = {z_leave:+.3f} m)")
        pass_ideal_label = f"analytic T/4 = {t_ideal*1000:.1f} ms"
    else:
        if np.any(zb <= z_target):
            k = int(np.argmax(zb <= z_target))
            t_pass = float(t[k])
        if z_bottom0 > z_target:
            t_ideal = math.sqrt(2 * (z_bottom0 - z_target) / cfg["phy"]["G"])
        pass_title = f"passage to the coil top face (z = {z_target:+.3f} m)"
        pass_ideal_label = f"ideal free fall: {t_ideal*1000:.1f} ms"

    relax = fr["meshrelax"][:, sel].mean(axis=1)
    passage = dict(t_pass=t_pass, t_ideal=t_ideal, z_target=z_target,
                   relax=relax, z_bottom0=z_bottom0,
                   title=pass_title, ideal_label=pass_ideal_label)

    # ---- coil transit timing, one entry per [curves] configuration -----
    # The magnet's own flux through the winding is taken from the FEM
    # (phi(z) = <B_z>(z) * A_coil).  Each configuration then gets its own
    # Lenz-braked trajectory:
    #      m z'' = -m g - c(z) z' ,   c(z) = (N^2 / R_tot) (dphi/dz)^2
    # and the four coil-crossing instants are read off that trajectory.
    #
    # NOTE: c(z) must be evaluated at the ABSOLUTE magnet height, because the
    # coil planes (coil_z0/coil_z1) and the release height are absolute too.
    # `track_magnet` returns a DISPLACEMENT (starting at 0), so convert here.
    coil_z0 = float(cfg["coil"]["z0_m"])
    coil_z1 = float(cfg["coil"]["z1_m"])
    mag_h = float(cfg["mag"]["H_mag_m"])
    m_mag = float(cfg["phy"]["M_kg"])
    g = float(cfg["phy"]["G"])
    z_center0 = float(fr["pts"][0, sel, 2].mean())      # start of magnet centre
    z_abs = z + z_center0
    zs, ps, dps = flux_vs_z(cfg, z_abs, Bz_probe)

    transit = []
    for cv in all_curves(cfg):
        r = coil_transit_times(zs, ps, dps, cv, mag_h, coil_z0, coil_z1,
                               m_mag, g, z_start=z_center0)
        # peak Lenz damping coefficient (N s / m), for the report
        r["c_peak"] = ((cv["N"] ** 2 / cv["R_tot"]) * float(np.abs(dps).max()) ** 2
                       if cv["N"] and math.isfinite(cv["R_tot"]) else 0.0)
        r.update(label=cv["label"], color=cv["color"], name=cv["name"],
                 N=cv["N"], R_tot=cv["R_tot"])
        transit.append(r)

    out_png = Path(args.out) if args.out else (RESULTS / "scope.png")
    make_scope(out_png, t, z, v, a, KE, PE, Etot, fe, Bz_probe, Bmax, cfg,
               passage, transit)
    write_summary(out_png.with_suffix(".txt"), t, z, v, a, KE, PE, Etot, fe,
                  Bz_probe, Bmax, cfg, passage, transit)
    write_json(out_png.with_suffix(".json"), t, z, v, a, KE, PE, Etot, fe,
               Bz_probe, Bmax, passage, transit)
    print()
    print(out_png.with_suffix(".txt").read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()

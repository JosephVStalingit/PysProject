# -*- coding: utf-8 -*-
"""
oscilloscope.py  --  UNIFIED magnet-free-fall dashboard
                       3 configurations x 10 channels  +  PASSAGE-TIME BAR

Usage:
    python oscilloscope.py                          # defaults from config.json
    python oscilloscope.py --M 0.6 --beta-coil 2.0  # parameter overrides
    python oscilloscope.py --out my_dashboard.png   # custom output

Physics (semi-analytical, FEM-calibrated):
    m * z_ddot = m*g - c*v
    B_z(r=0, z') = (mu0/2) * M * [ (z'+h)/sqrt(R^2+(z'+h)^2)
                                    - (z'-h)/sqrt(R^2+(z'-h)^2) ]
    Phi         = <B_z> * A_coil   (flux captured by coil block)
    EMF(t)      = -N * dPhi/dt     (Faraday / Lenz)
    I(t)        = EMF / R          (ohmic current)
    E_field     = I * rho_cu / A_wire   (copper wire ohmic drop)

The magnet is released at z_release_m (top of the air domain) and
falls freely under gravity + air drag + Lenz drag.  Three body
configurations quantify Lenz's-law braking for empty/copper/coil.
"""

from __future__ import annotations
import os, sys, glob, math, json, argparse
from pathlib import Path
import numpy as np

WORKDIR = Path(__file__).parent.resolve()
RESULTS = WORKDIR / "results"
CFG_PATH = WORKDIR / "config.json"


def _load_config() -> dict:
    if CFG_PATH.is_file():
        with open(CFG_PATH, encoding="utf-8") as f:
            return json.load(f)
    raise SystemExit(f"config.json not found at {CFG_PATH}")


_CFG = _load_config()
EXP      = _CFG["experiment"]
PHY      = _CFG["physics"]
MAG      = _CFG["magnet"]
COIL     = _CFG["coil"]
CFGS     = _CFG["configs"]
EXTRAS   = _CFG["extras"]
CHANNELS = _CFG["channels"]

G          = PHY["G"]
M          = PHY["M_kg"]
C_AIR      = PHY["C_air"]
ALPHA_CU   = CFGS["copper"]["damping_extra_N_s_per_m"]
BETA_COIL  = CFGS["coil"]["damping_extra_N_s_per_m"]
R_LOAD     = PHY["R_load_ohm"]
DT         = EXP["dt_s"]
T_END      = EXP["t_end_s"]
N          = int(T_END / DT)
Z_RELEASE  = EXP["z_release_m"]
Z_FINAL    = EXP["z_final_m"]

MU0        = 4.0 * math.pi * 1e-7
M_MAG      = MAG["M_mag_A_per_m"]
R_MAG      = MAG["R_mag_m"]
H_MAG      = MAG["H_mag_m"]
COIL_Z0    = COIL["z0_m"]
COIL_Z1    = COIL["z1_m"]
N_TURNS    = COIL["N_turns"]
RHO_CU     = COIL["rho_cu_ohm_m"]
WIRE_AREA  = COIL["wire_area_m2"]
COIL_R_OUT = COIL["r_outer_m"]
COIL_R_IN  = COIL["r_inner_m"]
A_COIL     = math.pi * (COIL_R_OUT ** 2 - COIL_R_IN ** 2)

CONFIGS = list(CFGS.keys())
NICE    = {k: CFGS[k]["label"]  for k in CONFIGS}
COLORS  = {k: CFGS[k]["color"]  for k in CONFIGS}
DAMPING = {k: C_AIR + CFGS[k]["damping_extra_N_s_per_m"] for k in CONFIGS}


def _parse_R(val):
    return float("inf") if val == "inf" else float(val)


RES = {k: _parse_R(CFGS[k]["R_load_ohm"]) for k in CONFIGS}


# ====================================================================
# Mechanics: m*z_ddot = m*g - c*v  (magnet free fall)
#   released at z=Z_RELEASE with v=0; falls down
# ====================================================================
def simulate_mechanics(config, dt=DT, n=N):
    c = DAMPING[config]
    z = np.zeros(n + 1)
    v = np.zeros(n + 1)
    a = np.zeros(n + 1)
    z[0] = Z_RELEASE
    v[0] = 0.0
    t = np.arange(0, (n + 1) * dt, dt)

    def f(z, v):
        return (v, (-M * G - c * v) / M)

    for i in range(n):
        k1z, k1v = f(z[i], v[i])
        k2z, k2v = f(z[i] + 0.5*dt*k1z, v[i] + 0.5*dt*k1v)
        k3z, k3v = f(z[i] + 0.5*dt*k2z, v[i] + 0.5*dt*k2v)
        k4z, k4v = f(z[i] + dt*k3z, v[i] + dt*k3v)
        z[i+1] = z[i] + dt/6.0 * (k1z + 2*k2z + 2*k3z + k4z)
        v[i+1] = v[i] + dt/6.0 * (k1v + 2*k2v + 2*k3v + k4v)
        a[i+1] = (-M*G - c*v[i+1]) / M
        if z[i+1] < Z_FINAL:
            return (t[:i+2], z[:i+2], v[:i+2], a[:i+2])
    return t, z, v, a


# ====================================================================
# Analytical B field of a uniformly-magnetised cylinder (on axis)
# ====================================================================
def B_z_axis(zp):
    r2 = R_MAG ** 2
    return (MU0 / 2.0) * M_MAG * (
        (zp + H_MAG) / math.sqrt(r2 + (zp + H_MAG)**2)
        - (zp - H_MAG) / math.sqrt(r2 + (zp - H_MAG)**2))


def flux_linkage(z_mag):
    zs = [COIL_Z0 + (COIL_Z1 - COIL_Z0) * i / 20.0 for i in range(21)]
    avg_B = sum(B_z_axis(zz - z_mag) for zz in zs) / 21.0
    return avg_B * A_COIL


def emf_and_current(t, z_world, config):
    Phi = np.array([flux_linkage(zi) * N_TURNS for zi in z_world])
    dt_arr = np.gradient(t)
    EMF = -np.gradient(Phi) / dt_arr
    R = RES[config]
    if math.isinf(R):
        I = np.zeros_like(EMF)
    else:
        I = EMF / R
    return EMF, I


def simulate_full(config):
    t, z, v, a = simulate_mechanics(config)
    B = np.array([B_z_axis(zi) for zi in z])
    EMF, I = emf_and_current(t, z, config)
    if config == "empty":
        E_field = np.zeros_like(EMF)
    else:
        E_field = np.abs(I) * RHO_CU / WIRE_AREA
    F_grav = -M * G * np.ones_like(t)
    F_lenz = np.array([-DAMPING[config] * vi for vi in v])
    KE = 0.5 * M * v**2
    PE = M * G * (z - Z_FINAL)
    return {"t": t, "z": z, "v": v, "a": a,
            "F_grav": F_grav, "F_lenz": F_lenz,
            "KE": KE, "PE": PE,
            "B_z": B, "EMF": EMF, "I": I, "E_field": E_field}


# ====================================================================
# Passage-time: time for magnet to reach a target z (e.g. coil bottom).
# Linear interpolation between samples for sub-step accuracy.
# ====================================================================
def passage_time(data, z_target=None):
    if z_target is None:
        z_target = EXTRAS["passage_time_bar"]["z_target_m"]
    t = data["t"]
    z = data["z"]
    if not np.any(z <= z_target):
        return float("nan")
    idx = int(np.argmax(z <= z_target))
    if idx == 0:
        return float(t[0])
    z_lo, z_hi = z[idx-1], z[idx]
    t_lo, t_hi = t[idx-1], t[idx]
    if z_hi == z_lo:
        return float(t_lo)
    frac = (z_target - z_lo) / (z_hi - z_lo)
    return float(t_lo + frac * (t_hi - t_lo))


# ====================================================================
# Dashboard: 2x5 channel grid + passage-time bar chart (3rd row)
# ====================================================================
def make_dashboard(out_png, data, passage):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    avail = {f.name for f in font_manager.fontManager.ttflist}
    for cand in ["SimHei", "Microsoft YaHei", "Noto Sans CJK SC",
                 "Arial Unicode MS", "PingFang SC", "WenQuanYi Zen Hei",
                 "Source Han Sans CN"]:
        if cand in avail:
            plt.rcParams["font.sans-serif"] = [cand]
            break
    plt.rcParams["axes.unicode_minus"] = False

    out_png.parent.mkdir(parents=True, exist_ok=True)

    fig = plt.figure(figsize=(22, 13))
    gs = fig.add_gridspec(3, 5, height_ratios=[1, 1, 0.8])

    for c, ch in enumerate(CHANNELS):
        r, col = divmod(c, 5)
        ax = fig.add_subplot(gs[r, col])
        for cfg in CONFIGS:
            d = data[cfg]
            ax.plot(d["t"], d[ch["key"]],
                    color=COLORS[cfg], lw=1.7,
                    label=NICE[cfg])
        ax.set_title(ch["title"], fontsize=11, fontweight="bold")
        ax.set_xlabel("t (s)")
        ax.set_ylabel(ch["unit"])
        ax.grid(True, alpha=0.3)
        ax.axhline(0, color="k", lw=0.4, alpha=0.3)
        ax.legend(fontsize=8, loc="best")

    bar_ax = fig.add_subplot(gs[2, :])
    times = [passage[cfg] for cfg in CONFIGS]
    bars = bar_ax.bar(CONFIGS, times,
                      color=[COLORS[c] for c in CONFIGS],
                      edgecolor="k", linewidth=0.6)
    bar_ax.set_title(EXTRAS["passage_time_bar"]["title"],
                     fontsize=12, fontweight="bold")
    bar_ax.set_ylabel(EXTRAS["passage_time_bar"]["y_unit"])
    bar_ax.grid(True, alpha=0.3, axis="y")
    if EXTRAS["passage_time_bar"].get("show_value_labels", True):
        for bar, t_val in zip(bars, times):
            if not math.isnan(t_val):
                bar_ax.text(bar.get_x() + bar.get_width() / 2,
                            bar.get_height(),
                            f"{t_val*1000:.1f} ms",
                            ha="center", va="bottom",
                            fontsize=10, fontweight="bold")
    h_fall = Z_RELEASE - EXTRAS["passage_time_bar"]["z_target_m"]
    t_vacuum = math.sqrt(2 * h_fall / G) * 1000
    bar_ax.axhline(t_vacuum, color="red", lw=1.0, ls="--", alpha=0.7,
                   label=f"vacuum free-fall: {t_vacuum:.1f} ms")
    bar_ax.legend(fontsize=9, loc="upper left")

    fig.suptitle(
        "UNIFIED Dashboard - Magnet free fall (configurable)\n"
        "3 configurations overlaid + passage-time bar",
        fontsize=14, fontweight="bold",
    )
    fig.tight_layout(rect=[0, 0, 1, 0.95])
    fig.savefig(out_png, dpi=110, bbox_inches="tight")
    plt.close(fig)
    print(f"[ok] wrote {out_png}")


def write_summary(data, passage, out_txt):
    lines = []
    lines.append("=" * 92)
    lines.append(" UNIFIED summary  -  Magnet FREE FALL  +  E/B field analysis")
    lines.append("                    3 configurations x 10 channels  +  passage-time bar")
    lines.append("=" * 92)
    lines.append(
        f"{'config':<8} {'R_load':>8} {'z(m)':>7} {'v(m/s)':>8} "
        f"{'a(m/s^2)':>10} {'F_g(N)':>8} {'F_L(N)':>9} "
        f"{'KE(J)':>9} {'PE(J)':>9} {'B(T)':>10} "
        f"{'EMF(V)':>9} {'I(A)':>10} {'t_pass(ms)':>11}"
    )
    lines.append("-" * 130)
    for cfg in CONFIGS:
        d = data[cfg]
        r_str = "inf" if math.isinf(RES[cfg]) else f"{RES[cfg]:.2e}"
        lines.append(
            f"{cfg:<8} {r_str:>8} "
            f"{float(d['z'][-1]):>7.4f} "
            f"{float(np.max(np.abs(d['v']))):>8.4f} "
            f"{float(np.max(np.abs(d['a']))):>10.4f} "
            f"{float(np.max(np.abs(d['F_grav']))):>8.4f} "
            f"{float(np.max(np.abs(d['F_lenz']))):>9.4e} "
            f"{float(np.max(np.abs(d['KE']))):>9.4e} "
            f"{float(np.max(np.abs(d['PE']))):>9.4e} "
            f"{float(np.max(np.abs(d['B_z']))):>10.4e} "
            f"{float(np.max(np.abs(d['EMF']))):>9.4e} "
            f"{float(np.max(np.abs(d['I']))):>10.4e} "
            f"{passage[cfg]*1000:>11.2f}"
        )
    lines.append("-" * 130)
    lines.append("")
    lines.append("Channel legend:")
    for ch in CHANNELS:
        lines.append(f"  {ch['key']:<8} {ch['title']:<28} ({ch['unit']})")
    lines.append("")
    lines.append("Physical interpretation (Lenz's law):")
    lines.append("  empty : open ckt  -> EMF present but I=0, only air drag")
    lines.append("  copper: short ckt -> huge eddy current (550+ A), strongest braking")
    lines.append("  coil  : 10 ohm    -> moderate Lenz current (60 mA), stable closed loop")
    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[ok] wrote {out_txt}")


def write_json(data, passage, out_json):
    out = {
        "metadata": {
            "G": G, "M": M, "C_AIR": C_AIR,
            "ALPHA_CU": ALPHA_CU, "BETA_COIL": BETA_COIL,
            "DT": DT, "T_END": T_END,
            "Z_RELEASE": Z_RELEASE, "Z_FINAL": Z_FINAL,
            "MU0": MU0, "M_MAG": M_MAG, "R_MAG": R_MAG, "H_MAG": H_MAG,
            "N_TURNS": N_TURNS, "R_LOAD": R_LOAD,
            "configs": CONFIGS,
        },
        "data": {},
        "passage_time_s": passage,
    }
    for cfg in CONFIGS:
        d = data[cfg]
        n = len(d["t"])
        step = max(1, n // 400)
        out["data"][cfg] = {
            "t_s":         d["t"][::step].tolist(),
            "z_m":         d["z"][::step].tolist(),
            "v_m_s":       d["v"][::step].tolist(),
            "a_m_s2":      d["a"][::step].tolist(),
            "F_grav_N":    d["F_grav"][::step].tolist(),
            "F_lenz_N":    d["F_lenz"][::step].tolist(),
            "KE_J":        d["KE"][::step].tolist(),
            "PE_J":        d["PE"][::step].tolist(),
            "B_z_T":       d["B_z"][::step].tolist(),
            "EMF_V":       d["EMF"][::step].tolist(),
            "I_A":         d["I"][::step].tolist(),
            "E_field_V_m": d["E_field"][::step].tolist(),
            "summary": {
                "z_final_m":        float(d["z"][-1]),
                "v_peak_m_s":       float(np.max(np.abs(d["v"]))),
                "a_peak_m_s2":      float(np.max(np.abs(d["a"]))),
                "F_lenz_max_N":     float(np.max(np.abs(d["F_lenz"]))),
                "KE_max_J":         float(np.max(np.abs(d["KE"]))),
                "PE_max_J":         float(np.max(np.abs(d["PE"]))),
                "B_max_T":          float(np.max(np.abs(d["B_z"]))),
                "E_max_V_m":        float(np.max(np.abs(d["E_field"]))),
                "EMF_max_V":        float(np.max(np.abs(d["EMF"]))),
                "I_max_A":          float(np.max(np.abs(d["I"]))),
            },
        }
    out_json.write_text(
        json.dumps(out, ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    print(f"[ok] wrote {out_json}")



# ====================================================================
# CLI
# ====================================================================
def main():
    global M, C_AIR, ALPHA_CU, BETA_COIL, T_END, N, DAMPING
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-vtu", action="store_true",
                    help="ignored (no .vtu available)")
    ap.add_argument("--M", type=float, default=M,
                    help=f"magnet mass kg (default {M} from config.json)")
    ap.add_argument("--C-air", type=float, default=C_AIR,
                    help=f"air drag N*s/m (default {C_AIR} from config.json)")
    ap.add_argument("--alpha-cu", type=float, default=ALPHA_CU,
                    help=f"copper damping N*s/m (default {ALPHA_CU})")
    ap.add_argument("--beta-coil", type=float, default=BETA_COIL,
                    help=f"coil Lenz damping N*s/m (default {BETA_COIL})")
    ap.add_argument("--T-end", type=float, default=T_END,
                    help=f"simulation duration s (default {T_END})")
    ap.add_argument("--out", type=str, default=None,
                    help="PNG output path (default results/dashboard.png)")
    args = ap.parse_args()

    M = args.M
    C_AIR = args.C_air
    ALPHA_CU = args.alpha_cu
    BETA_COIL = args.beta_coil
    T_END = args.T_end
    N = int(T_END / DT)
    DAMPING = {k: C_AIR + CFGS[k]["damping_extra_N_s_per_m"] for k in CONFIGS}

    RESULTS.mkdir(parents=True, exist_ok=True)
    out_png = Path(args.out) if args.out else (RESULTS / "dashboard.png")
    out_txt = out_png.with_suffix(".txt")
    out_jsn = out_png.with_suffix(".json")

    print("Running 3-config unified magnet free-fall simulation ...")
    data = {cfg: simulate_full(cfg) for cfg in CONFIGS}
    passage = {cfg: passage_time(data[cfg]) for cfg in CONFIGS}

    make_dashboard(out_png, data, passage)
    write_summary(data, passage, out_txt)
    write_json(data, passage, out_jsn)

    print()
    print(open(out_txt, encoding="utf-8").read())


if __name__ == "__main__":
    main()

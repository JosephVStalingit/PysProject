#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hpc/make_case.py -- generate one study case (config + mesh + SIF) for the
coil-length / mesh-resolution sweep that is meant to run on the HPC.

Why a separate harness
----------------------
`config.json` -> [coil] is the single source of truth for the coil geometry,
so a "case" is just a patched copy of config.json plus a mesh built from it.
The magnet release height and the air-domain extent are DERIVED from the coil
length, otherwise a long coil would stick out of the air box.

Usage:
    python hpc/make_case.py --length 0.160 --level fine
    python hpc/make_case.py --length 0.040 --level coarse --positions 48
"""
from __future__ import annotations
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

# characteristic lengths (m) per mesh level
LEVELS = {
    "coarse": dict(lc_min_m=0.0030, lc_magnet_m=0.0040,
                   lc_coil_m=0.0080, lc_others_m=0.0220),
    "fine":   dict(lc_min_m=0.0015, lc_magnet_m=0.0020,
                   lc_coil_m=0.0035, lc_others_m=0.0120),
    "finer":  dict(lc_min_m=0.0010, lc_magnet_m=0.0014,
                   lc_coil_m=0.0025, lc_others_m=0.0090),
}

# geometry constants that are NOT swept
MAG_R = 0.015          # magnet radius
MAG_H = 0.030          # magnet height
COIL_RIN = 0.020       # default bore radius (5 mm clearance around the magnet)
COIL_ROUT = 0.025
R_AIR = 0.080
GAP_ABOVE_COIL = 0.020   # magnet bottom starts this far above the coil top
GAP_BELOW_COIL = 0.020   # magnet top ends this far below the coil bottom
DZ = 0.002               # magnet travel per output frame


def build_case(length, level, positions=None, outdir=None, v=1.0, dt=2.0e-3,
               rin=COIL_RIN):
    L = float(length)
    rin = float(rin)
    gap = rin - MAG_R
    if gap <= 0.0005:
        raise SystemExit(f"[err] bore radius {rin*1000:.2f} mm leaves only "
                         f"{gap*1000:.2f} mm around the {MAG_R*1000:.0f} mm "
                         f"magnet -- the mesh cannot resolve that")
    tag = f"L{int(round(L*1000)):03d}_ri{int(round(rin*1000)):03d}_{level}"
    case = Path(outdir) if outdir else (ROOT / "hpc" / "cases" / tag)
    if case.exists():
        shutil.rmtree(case)
    case.mkdir(parents=True)

    mag_z0 = L + GAP_ABOVE_COIL
    mag_z1 = mag_z0 + MAG_H
    air_z1 = L + GAP_ABOVE_COIL + MAG_H + 0.040
    air_z0 = -COIL_ROUT - 0.020

    # magnet centre: from just above the coil to just below it
    z_start = mag_z0 + MAG_H / 2 + 0.020
    z_end = -MAG_H / 2 - GAP_BELOW_COIL
    travel = z_start - z_end
    n_pos = positions or int(round(travel / DZ)) + 1
    dz = travel / (n_pos - 1)
    # the SIF advances the magnet LINEARLY by exactly v*dt per frame, so the
    # timestep must be pinned to the intended sampling -- otherwise the frames
    # land between the positions the post-processing assumes.
    dt = dz / v

    cfg = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    cfg["coil"]["z0_m"] = 0.0
    cfg["coil"]["z1_m"] = L
    cfg["coil"]["r_inner_m"] = rin
    cfg["coil"]["r_outer_m"] = COIL_ROUT
    cfg["magnet"]["z0_m"] = mag_z0
    cfg["magnet"]["z1_m"] = mag_z1
    cfg["geometry"]["R_air_m"] = R_AIR
    cfg["geometry"]["air_z0_m"] = air_z0
    cfg["geometry"]["air_z1_m"] = air_z1
    lv = dict(LEVELS[level])
    # GAP REFINEMENT (capped): when the bore is only a few millimetres larger
    # than the magnet the thin air gap carries the flux that matters, so it
    # should be meshed finer.
    #
    # CAREFUL: gmsh sizes are applied to POINTS, so asking for gap/3 also
    # refines the ENTIRE magnet and coil volumes.  A 1 mm gap at gap/3
    # (0.33 mm) produced 4.76M tets / 753k nodes -- unusable.  The cap below
    # keeps ~2 elements across a 3 mm gap at an affordable cost.
    if gap < 0.006:
        lc_gap = max(gap / 2.0, 0.0015)
        lv["lc_magnet_m"] = min(lv["lc_magnet_m"], lc_gap)
        lv["lc_coil_m"] = min(lv["lc_coil_m"], lc_gap)
        lv["lc_min_m"] = min(lv["lc_min_m"], lc_gap)
        print(f"       [gap] bore wall is {gap*1000:.2f} mm away -> "
              f"lc capped to {lc_gap*1000:.2f} mm (~{gap/lc_gap:.1f} elements "
              f"across the gap)")
    cfg["mesh"].update(lv)
    meta = dict(length=L, level=level, n_positions=n_pos, dz=dz,
                z_start=z_start, z_end=z_end, travel=travel,
                coil_z0=0.0, coil_z1=L, mag_z0=mag_z0, mag_z1=mag_z1,
                coil_r_inner=rin, coil_r_outer=COIL_ROUT,
                mag_radius=MAG_R, gap=gap, mesh=lv)
    cfg["_study"] = meta
    (case / "config.json").write_text(
        json.dumps(cfg, indent=4, ensure_ascii=False), encoding="utf-8")

    print(f"[case] {case}")
    print(f"       coil L      = {L*1000:.0f} mm   bore r_in = {rin*1000:.1f} mm "
          f"(gap {gap*1000:.2f} mm)")
    print(f"       mesh level  = {level}  {lv}")
    print(f"       mag centre  = {z_start*1000:.1f} -> {z_end*1000:.1f} mm "
          f"({travel*1000:.0f} mm travel)")
    print(f"       frames      = {n_pos}  (dz = {dz*1000:.3f} mm)")

    # ---- mesh (gmsh must run inside the case dir: it reads ./config.json)
    py = sys.executable
    r = subprocess.run([py, str(ROOT / "solenoid3d.py"),
                        "-o", "model3d.msh", "--config", "stranded-coil"],
                       cwd=str(case), capture_output=True, text=True)
    if r.returncode != 0 or not (case / "model3d.msh").exists():
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        sys.exit(f"[err] gmsh failed for {tag}")

    n_nodes = n_elems = -1
    with open(case / "model3d.msh", encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s == "$Nodes":
                n_nodes = int(f.readline())
            elif s == "$Elements":
                n_elems = int(f.readline())
                break
    print(f"       model3d.msh = {(case/'model3d.msh').stat().st_size/1e6:.1f} MB"
          f"   ({n_nodes} nodes, {n_elems} elements)")
    (case / "study.json").write_text(json.dumps(meta, indent=2),
                                     encoding="utf-8")
    make_sif(case, meta, v=v, dt=dt)
    return case, meta


# ---------------------------------------------------------------------------
#  SIF generation
# ---------------------------------------------------------------------------
# The EM problem is effectively MAGNETOSTATIC: every body has
# `Electric Conductivity ~ 0` (coil 0.0, air/magnet 1e-12), so the transient
# A-formulation degenerates to a sequence of static solves.  Two consequences
# we exploit on the HPC:
#
#   1. the TIME LAW does not have to be free fall -- driving the magnet
#      LINEARLY (z = z0 - v t) gives a uniform z-sampling, which is what we
#      actually want for dPhi/dz;
#   2. each step is INDEPENDENT, so the timeline can be split across jobs.
#      A job covering window j just offsets the motion law by T_j.
def make_sif(case, meta, v=1.0, t_offset=0.0, nsteps=None, dt=2.0e-3):
    src = (ROOT / "case_transient.sif").read_text(encoding="utf-8")
    nsteps = nsteps or meta["n_positions"]

    def sub(pattern, repl, s):
        import re
        new, n = re.subn(pattern, repl, s, count=1)
        if n != 1:
            raise SystemExit(f"[err] SIF patch failed for /{pattern}/")
        return new

    s = src
    s = sub(r'Mesh DB "[^"]*" "mesh"', 'Mesh DB "." "mesh"', s)
    s = sub(r'Results Directory "[^"]*"', 'Results Directory "results"', s)
    s = sub(r"Timestep Sizes\s*=\s*[0-9.eE+-]+", f"Timestep Sizes = {dt:.6e}", s)
    s = sub(r"Timestep Intervals\s*=\s*\d+", f"Timestep Intervals = {nsteps}", s)
    # linear motion: z_abs(t) = z_start - v*(t + t_offset), expressed as the
    # displacement from the ORIGINAL mesh position.
    s = sub(r'Real MATC "[^"]*"',
            f'Real MATC "-{v:.8g}*(tx+{t_offset:.8g})"', s)
    (case / "case.sif").write_text(s, encoding="utf-8")
    print(f"       case.sif: linear v={v} m/s  toff={t_offset:.4f} s  "
          f"dt={dt}  steps={nsteps}")
    return case / "case.sif"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--length", type=float, required=True,
                    help="coil length in m (coil spans z = 0 .. length)")
    ap.add_argument("--level", choices=sorted(LEVELS), default="coarse")
    ap.add_argument("--positions", type=int, default=None,
                    help="number of frames (default: travel / 2 mm)")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--v", type=float, default=1.0,
                    help="linear magnet speed in m/s (default 1.0)")
    ap.add_argument("--dt", type=float, default=2.0e-3,
                    help="timestep in s; dz = v*dt (default 2e-3 -> 2 mm)")
    ap.add_argument("--rin", type=float, default=COIL_RIN,
                    help=f"bore (winding inner) radius in m, default "
                         f"{COIL_RIN}.  Use e.g. 0.017 to put the magnet "
                         f"ESSENTIALLY INSIDE the winding -- that is the only "
                         f"lever that can make Lenz braking significant.")
    a = ap.parse_args()
    build_case(a.length, a.level, a.positions, a.outdir, v=a.v, dt=a.dt,
               rin=a.rin)


if __name__ == "__main__":
    main()

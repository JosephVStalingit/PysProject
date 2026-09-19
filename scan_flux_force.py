#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scan_flux_force.py -- STATIC scan for the motional flux linkage gradient.

WHY STATIC
----------
Extracting dLambda_mot/dz from the 900-step circuit.csv is ruled out (see
fit_flux_linkage.py / README 11.7).  A static solve has no motion, no circuit
transient, no integration and no spikes, and the linkage follows from a
thermodynamic identity:

    W(z, i) = W_pm(z) + i*Lambda_mot(z) + (1/2) L(z) i^2

Running each magnet position at +V and -V and differencing the field energy
cancels BOTH the permanent-magnet self energy and the (1/2)L i^2 term:

    Lambda_mot(z) = [ W(+i) - W(-i) ] / (2 i)

and dLambda_mot/dz follows from a finite difference in z.  Both quantities are
already in the SaveScalars output (circuit.csv cols 6 and 10), so no new SIF
keys are needed.

HOW THE CURRENT IS SET
----------------------
circuits.definitions shows the loop is [testsource] -- [coil] -- [load] and the
source value is written in Body Force 3 ("Circuit"):  `testsource = Real 0.0`.
Setting it to +/-1 V gives a DETERMINISTIC current i = V/R_total (R_total is
read back from the same file) with no MATC direction gymnastics.

WHAT THIS SCRIPT DOES
---------------------
 1. builds a scratch case dir (case.sif + circuits.definitions + model3d.msh),
 2. converts the gmsh mesh once with ElmerGrid -autoclean,
 3. patches the SIF: Steady State, 1 timestep, a CONSTANT Mesh Translate 3 and
    the source voltage,
 4. runs ElmerSolver (local Windows build) and parses the last circuit.csv row.

Run:  python scan_flux_force.py --case N100_L040_cu_closed --z 0.024 --volt 1.0
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_CASES = os.path.join(ROOT, "hpc", "cases")
SCRATCH = os.path.join(ROOT, "_static")
ELMER = os.path.join(ROOT, "elmer262", "bin", "ElmerSolver.exe")
GRID = os.path.join(ROOT, "elmer262", "elmergrid", "src", "ElmerGrid.exe")
Z_RELEASE = 0.045


def prepare(case, path="coilsolver"):
    """Scratch dir: regenerate the SIF from the CURRENT config + build mesh/.

    IMPORTANT: do not copy hpc/cases/<case>/case.sif -- those were written
    before the [sensor] change and still carry R_load = 10 ohm.  Generating
    from config.json keeps the static scan consistent with the model.

    `path` selects the coil formulation: "coilsolver" (upstream CoilSolver, the
    current production path) or "wsolve" (our old scalar-W path).  Comparing the
    two on the SAME static case is how the R_eff anomaly gets localised.
    """
    dst = os.path.join(SCRATCH, case + ("__" + path if path != "coilsolver" else ""))
    src = os.path.join(SRC_CASES, case)
    os.makedirs(dst, exist_ok=True)
    shutil.copy2(os.path.join(src, "model3d.msh"),
                 os.path.join(dst, "model3d.msh"))
    sif = os.path.join(dst, "case.sif")
    print("  regenerating case.sif from config.json (--path %s) ..." % path)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "make_sif.py"),
                        "--curve", case, "--path", path, "--out", sif],
                       cwd=ROOT, capture_output=True)
    if not os.path.exists(sif):
        raise SystemExit("[err] make_sif.py did not write the SIF:\n"
                         + (r.stdout or b"").decode("utf-8", "replace")[-2000:])
    mesh = os.path.join(dst, "mesh")
    if not os.path.exists(os.path.join(mesh, "mesh.header")):
        print("  converting mesh with ElmerGrid -autoclean ...")
        r = subprocess.run([GRID, "14", "2", "model3d.msh", "-out", "mesh",
                            "-autoclean"], cwd=dst, capture_output=True)
        tail = (r.stdout or b"").decode("utf-8", "replace").strip().splitlines()
        print("    " + (tail[-1] if tail else "no output"))
    return dst


def patch(dst, z, volt, steps=10):
    """A few timesteps, constant magnet offset, source voltage.

    NOTE (two traps found the hard way):
      * keep `Simulation Type = Transient`.  Steady State looks natural but
        BREAKS the circuit: make_sif.py gives the circuit solvers
        `Exec Solver = Before timestep`, and a steady state run has no
        timesteps, so CircuitsAndDynamics never executes (i = 0.000).
      * `steps` must be > 1.  With `Nonlinear/Steady State Max Iterations = 1`
        the circuit<->field coupling gets a single pass, so the reported
        i_component(1) is still the pre-solve value 0.  The 900-step run
        self-corrects step by step; here a handful of steps with a CONSTANT
        Mesh Translate is equivalent to a static solve (nothing moves).
    """
    p = os.path.join(dst, "case.sif")
    s = open(p, encoding="utf-8", errors="replace").read()
    n = {}
    s, n["steps"] = re.subn(r"Timestep Intervals\s*=\s*\d+",
                            "Timestep Intervals     = %d" % steps, s, count=1)
    s, n["mt"] = re.subn(
        r'Mesh Translate 3\s*=\s*Variable Time\s*\n\s*Real MATC "[^"]*"',
        "Mesh Translate 3 = Real %.10e" % (z - Z_RELEASE), s, count=1)
    s, n["src"] = re.subn(r"testsource\s*=\s*Real\s*[0-9.eE+-]+",
                          "testsource = Real %.6e" % volt, s, count=1)
    if any(v != 1 for v in n.values()):
        raise SystemExit("[err] SIF patch failed: %r" % n)
    open(p, "w", encoding="utf-8").write(s)
    return n


def run(dst, timeout=2400):
    e = dict(os.environ)
    e["PATH"] = os.path.join(ROOT, "elmer262", "bin") + os.pathsep + e.get("PATH", "")
    e["LD_LIBRARY_PATH"] = (os.path.join(ROOT, "elmer262", "lib") + os.pathsep
                            + os.path.join(ROOT, "elmer262", "share",
                                           "elmersolver", "lib"))
    print("  running ElmerSolver (timeout %d s) ..." % timeout)
    try:
        r = subprocess.run([ELMER, "case.sif"], cwd=dst, capture_output=True,
                           timeout=timeout, env=e)
    except subprocess.TimeoutExpired:
        print("  !! TIMEOUT")
        return None
    log = (r.stdout or b"").decode("utf-8", "replace") \
        + (r.stderr or b"").decode("utf-8", "replace")
    open(os.path.join(dst, "solve.log"), "w", encoding="utf-8").write(log)
    if "The end" not in log:
        print("  !! ElmerSolver did not finish; last lines:")
        for ln in log.strip().splitlines()[-14:]:
            print("     " + ln)
        return None
    return log


def _isnum(x):
    try:
        float(x)
        return True
    except ValueError:
        return False


def last_row(dst):
    p = os.path.join(dst, "results", "circuit.csv")
    if not os.path.exists(p):
        return None
    rows = [ln.split() for ln in open(p, encoding="utf-8").read().splitlines()
            if ln.strip() and _isnum(ln.split()[0])]
    return [float(x) for x in rows[-1]] if rows else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", default="N100_L040_cu_closed")
    ap.add_argument("--path", default="coilsolver",
                    choices=("coilsolver", "wsolve"))
    ap.add_argument("--z", type=float, default=0.024,
                    help="magnet centre position [m], absolute")
    ap.add_argument("--volt", type=float, default=1.0)
    ap.add_argument("--no-run", action="store_true")
    a = ap.parse_args()

    print("=== static scan: case=%s  path=%s  z=%.5f m  V=%.3f V ==="
          % (a.case, a.path, a.z, a.volt))
    dst = prepare(a.case, a.path)
    patch(dst, a.z, a.volt)
    print("  SIF patched: steady state, 1 step, Mesh Translate 3 = %.6e,"
          " testsource = %.3f V" % (a.z - Z_RELEASE, a.volt))
    if a.no_run:
        return 0
    log = run(dst)
    if log is None:
        return 1
    row = last_row(dst)
    print("  ElmerSolver finished")
    if row is None:
        print("  !! no circuit.csv row parsed -- check results/")
        return 1
    rtot = row[13] + row[15]
    print("  time=%.3e  i_coil=%.6e A  r_coil=%.6e  r_load=%.6e"
          % (row[6], row[9], row[13], row[15]))
    print("  R_total = %.6f ohm -> i = V/R_total = %.6e A  (Elmer reports %.6e)"
          % (rtot, a.volt / rtot, row[9]))
    print("  field energy (col 6) = %.8e" % row[5])
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
hpc/stage_lambda_scan.py -- LOCAL, NO-FEM staging of the static Lambda_mot(z) scan.

WHAT IT EMITS (text only; nothing is solved on this machine)
-----------------------------------------------------------
  hpc/lambda_scan/manifest.tsv          tag, case, z, volt   (29 rows)
  hpc/lambda_scan/<tag>/case.sif        patched with the SAME regexes the local
  hpc/lambda_scan/<tag>/circuits.definitions   scan_flux_force.patch() uses
  hpc/cases/<case>/case.sif             refreshed from config.json (sensor load)

The patch is done on the HOST with scan_flux_force.patch(), i.e. bit-identical
to what a local static scan would have run -- the cluster never needs Python
(its /usr/bin/python is 2.7 and the python3 shim inside batch jobs is broken).

THE 29 POINTS
-------------
  13 z positions x (+1.0 V, -1.0 V)  -> Lambda_mot(z) = [W(+i)-W(-i)]/(i+ - i-)
                                        and the measured loop resistance V/i
   3 extras at z = 0.024 m:  V = 0.0  -> W_pm(z_eq) (checks the decomposition)
                             V = 0.5  -> the (1/2)L i^2 curvature, i.e. L(z_eq)
                             V = 2.0  -> linearity check of the i-dependence

WHY THIS IS RESISTANCE-FREE: W = W_pm + i*Lambda_mot + (1/2)L i^2; the +-V
difference kills the first and third terms exactly, so the ~9.045x circuit
resistance anomaly (README 11.8) cannot enter the linkage measurement.

Run:  python hpc/stage_lambda_scan.py
Then: powershell -File hpc/push_lambda_scan.ps1     (upload + sbatch, 3 arrays)
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import scan_flux_force as sf  # noqa: E402

CASE = "N100_L040_cu_closed"
CONDUCTOR_CASES = ["N25_L040_cu_closed", "N50_L040_cu_closed", "N100_L040_cu_closed",
                   "N25_L040_al_closed", "N50_L040_al_closed", "N100_L040_al_closed"]
ZS = [0.006, 0.010, 0.014, 0.016, 0.018, 0.020, 0.022, 0.024,
      0.028, 0.032, 0.036, 0.040, 0.044]
VOLTS = [1.0, -1.0]
EXTRA = [(0.024, 0.0), (0.024, 0.5), (0.024, 2.0)]
# Diagnostics at z = 0.024 with 20 timesteps instead of 4.  WHY: the reported
# i_component(1) is IDENTICAL for +1 V and -1 V (bit-for-bit, see README 11.9),
# so the CoilSolver path fixes the coil current DIRECTION by the winding
# geometry and only the magnitude follows |V|.  That kills the +-V energy
# cancellation and means the linkage must be extracted from the *magnitude*
# dependence: W(i) = W_pm + i*Lambda_mot + (1/2)L i^2 with i = |V|/R_eff.
# 20 steps are there to show that the 4-step values are (or are not) converged.
DIAG = [(0.024, 1.0, 20), (0.024, -1.0, 20), (0.024, 0.0, 20)]
# SAME DISCOVERY, second consequence -- the 4-step points are NOT converged:
# at z = 0.024 every voltage 0/0.5/1/2 V gave the SAME i and the SAME W, so the
# first steps are dominated by a build-up transient (W jumps 1.8e4 -> 1.02e10
# between steps 1 and 2).  These five points decide whether the source-driven
# DC response appears once the transient has died:
#   d1-d3 : z = 0.045 m -> Mesh Translate 3 = 0, i.e. NO mesh jump at all, and
#           V = 0/1/2.  A clean DC loop must give i = V/(0.6333+0.5012) exactly.
#   d4-d5 : z = 0.024 m with 20 steps, V = 1 and 0 -> does the spurious 0.0946 A
#           decay, or does the loop settle at V/R?
DIAG2 = [(0.045, 0.0, 20, "d1_njump_v0"),
         (0.045, 1.0, 20, "d2_njump_v1"),
         (0.045, 2.0, 20, "d3_njump_v2"),
         (0.024, 1.0, 20, "d4_z024_v1_n20"),
         (0.024, 0.0, 20, "d5_z024_v0_n20")]
# THE FIX UNDER TEST.  d1-d5 came back with the SAME current for V = 0, 1 and 2 V
# (and a nonzero current at V = 0), because `Body Force 3` -- the block that
# carries `testsource` -- is defined in the SIF but NOT referenced by any Body:
# Elmer applies a body force only when a Body lists it.  Attaching it to Body 1
# (the coil block = the circuit's master body) must turn the DC loop on:
#     i = V / (0.6333429 + 0.5012) = V / 1.1345
# If it does, then the "9.045x circuit resistance anomaly" (README 11.8) was an
# artefact of an inert source, NOT a CoilSolver normalisation -- and every
# source-driven static number in the project has to be re-derived.
DIAG3 = [(0.045, 0.0, 20, "e1_bf_v0"),
         (0.045, 1.0, 20, "e2_bf_v1"),
         (0.045, 2.0, 20, "e3_bf_v2"),
         (0.024, 1.0, 20, "e4_bf_z024_v1")]
# MULTI-VOLTAGE FAMILY at z = 0.024 m  (the equilibrium crossing).  With the
# body-force fix in place these give the W(I) curve at the magnet centre; a
# quadratic fit yields Lambda_mot(0.024) [linear term] AND L(0.024) [curvature]
# in col-6 energy units.  6 voltages spanning ~25 dB.
DIAG_MV = [(0.024, v, 20, "mv%04dv%+06.2f" % (int(v * 1000), v))
           for v in (0.0, 0.25, 0.5, 0.75, 1.0, 2.0)]
# SINGLE-VOLTAGE V = 1 V across the full z range (the +/-V trick is dead in
# CoilSolver because both polarities give the same |i|, so the diagnostic
# cancels instead of differencing).  Lambda_mot(z) = dW/dI is recovered from
# the family above; here we measure the magnitude |i|(z) and W(z; V=1).
DIAG_SV = [(z, 1.0, 20, "sv_z%05.1fv1" % (z * 1000)) for z in ZS]
# FINAL FORM of the fix.  Combines BOTH corrections:
#   (1) `testsource` -> Body Force 1 (was in the dangling Body Force 3)
#   (2) CircuitsAndDynamics solver -> Variable = X + No Matrix = Logical True
#                       (so resistance terms reach the solved system)
# Naming starts at "f*" so it is easy to grep the FINAL data.
DIAG_F = [(0.045, 0.0, 20, "f1_njump_v0"),
          (0.045, 0.5, 20, "f2_njump_v05"),
          (0.045, 1.0, 20, "f3_njump_v1"),
          (0.045, 2.0, 20, "f4_njump_v2"),
          (0.024, 1.0, 20, "f5_z024_v1")]


def assign_source_bf(d, also_no_matrix=True):
    """Move `testsource` from the dangling Body Force 3 into the Body Force 1
    block (CoilCurrent) that Body 1 already references.  Elmer rejects two
    `Body Force =` entries on a Body and a `Body Force(N)` array is not parsed,
    so the only fix is to consolidate the source's load-bearing keys onto the
    body-force block the Body already uses.

    Why Body 1 (CoilCurrent) and not Body 2 (OscillatingMagnet): the circuit
    source drives the stranded coil component, whose Master Body is 1.
    CalcFields reads `testsource` only when the matching body-force is on the
    coil's master body.

    `also_no_matrix` -- also add `Variable = X` and `No Matrix = Logical True`
    to the CircuitsAndDynamics solver block.  Without these two keys the
    circuit's resistance terms are silently dropped from the assembled system
    while `r_component(1)` keeps its accumulated value (notes.md 26-27, 27.2).
    The upstream reference `circuits_transient_stranded_wvector/sif/6480.sif`
    carries both; this SIF was generated without them, hence the loop
    effectively sees only `R_load` and the 9.045x scaling.
    """
    p = os.path.join(d, "case.sif")
    s = open(p, encoding="utf-8", errors="replace").read()

    # 1. Lift the three circuit keys out of Body Force 3.
    #    The block is `Body Force 3 ... End\n`, but `End` may also appear at
    #    the end of OTHER blocks later in the file -- match NON-greedy and
    #    anchor on the trailing newline so we stop at the first End\ n after
    #    Body Force 3, which IS that block's terminator.
    m = re.search(
        r"Body Force 3\b(.*?)^End\s*$",
        s, flags=re.S | re.M,
    )
    if not m:
        raise SystemExit("[err] Body Force 3 block not found in %s" % p)
    block = m.group(1)
    keys = {}
    for key in ("testsource", "Circuit Current Variable Id", "Stranded Coil N_j"):
        mm = re.search(rf"^\s*{re.escape(key)}\s*=\s*(.*?)\s*$", block, flags=re.M)
        if mm:
            keys[key] = mm.group(1).strip()
    if "testsource" not in keys:
        raise SystemExit("[err] Body Force 3 had no testsource")
    # 2. Drop Body Force 3 entirely (replace the whole "Body Force 3 ... End\n" match).
    s = re.sub(r"Body Force 3\b.*?^End\s*\n", "", s, count=1, flags=re.S | re.M)
    # 3. Insert each key into Body Force 1, before its trailing `End` line.
    m = re.search(r"(Body Force 1\b.*?)^End\s*$", s, flags=re.S | re.M)
    if not m:
        raise SystemExit("[err] Body Force 1 block not found in %s" % p)
    additions = ""
    for k, v in keys.items():
        if f"{k} =" in m.group(0):
            continue
        additions += f"  {k} = {v}\n"
    if additions:
        end_idx = s.rfind("\nEnd", 0, m.end()) + 1   # the 'E' of 'End'
        s = s[:end_idx] + additions + s[end_idx:]

    # 4. Patch the CircuitsAndDynamics solver (the assembler): add
    #    `Variable = X` and `No Matrix = Logical True` to ensure the
    #    circuit matrix (with the resistance terms) actually reaches the
    #    solved system instead of being silently dropped.
    if also_no_matrix:
        proc = 'Procedure = "CircuitsAndDynamics" "CircuitsAndDynamics"'
        m = re.search(
            r'(?P<head>^\s*Equation = "Circuits"\s*\n\s*' +
            re.escape(proc) + r'\s*\n)',
            s, flags=re.M,
        )
        if m and "No Matrix" not in s:
            inject = "  Variable = X\n  No Matrix = Logical True\n"
            s = s[:m.start("head")] + m.group("head") + inject + s[m.end("head"):]

    open(p, "w", encoding="utf-8").write(s)
    return list(keys)
STAGE = os.path.join(ROOT, "hpc", "lambda_scan")
CASES = os.path.join(ROOT, "hpc", "cases")


def fresh_sif(case, out):
    """Regenerate case.sif from the CURRENT config.json (make_sif.py, no FEM)."""
    r = subprocess.run([sys.executable, os.path.join(ROOT, "make_sif.py"),
                        "--curve", case, "--path", "coilsolver", "--out", out],
                       cwd=ROOT, capture_output=True)
    if not os.path.exists(out):
        raise SystemExit("[err] make_sif.py failed for %s:\n%s"
                         % (case, (r.stdout or b"").decode("utf-8", "replace")[-1500:]))


def main():
    # 1. refresh every conductor case SIF from config.json (they were generated
    #    before the [sensor] change and still carried R_load = 10 ohm).
    print("=== refreshing hpc/cases/*/case.sif from config.json ===")
    for c in CONDUCTOR_CASES + ["empty"]:
        d = os.path.join(CASES, c)
        if not os.path.isdir(d):
            print("   [skip] %-22s (no such case dir)" % c)
            continue
        try:
            fresh_sif(c, os.path.join(d, "case.sif"))
            print("   %-22s -> hpc/cases/%s/case.sif" % (c, c))
        except SystemExit as e:
            print("   [FAIL] %-22s %s" % (c, str(e)[:120]))


    # 2. base SIF for the scan case
    if os.path.exists(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)
    base = os.path.join(STAGE, "_base.sif")
    fresh_sif(CASE, base)

    _cases = os.path.join(STAGE, "_cases")
    for c in CONDUCTOR_CASES:
        d = os.path.join(_cases, c)
        if os.path.isdir(os.path.join(CASES, c)):
            os.makedirs(d, exist_ok=True)
            shutil.copy2(os.path.join(CASES, c, "case.sif"),
                         os.path.join(d, "case.sif"))
    print("   mirrored %d refreshed SIFs -> hpc/lambda_scan/_cases/"
          % len(os.listdir(_cases)) if os.path.isdir(_cases) else "   (none)")

    # 3. one patched copy per point
    pts = ([(z, v, 4, None) for z in ZS for v in VOLTS]
           + [(z, v, 4, None) for z, v in EXTRA]
           + [(z, v, n, None) for z, v, n in DIAG]
           + [(z, v, n, t) for z, v, n, t in DIAG2]
           + [(z, v, n, t) for z, v, n, t in DIAG3]
           + [(z, v, n, t) for z, v, n, t in DIAG_MV]
           + [(z, v, n, t) for z, v, n, t in DIAG_SV]
           + [(z, v, n, t) for z, v, n, t in DIAG_F])
    rows = []
    for z, v, n, t in pts:
        tag = t or ("z%05.1f_v%+06.2f" % (z * 1000.0, v))
        if n != 4 and not t:
            tag += "_n%d" % n
        d = os.path.join(STAGE, tag)
        os.makedirs(d)
        shutil.copy2(base, os.path.join(d, "case.sif"))
        shutil.copy2(os.path.join(CASES, CASE, "circuits.definitions"),
                     os.path.join(d, "circuits.definitions"))
        sf.patch(d, z, v, steps=n)          # LOCAL regex patch, no solve
        if t and (t.startswith("e") or t.startswith("mv") or t.startswith("sv")):
            assign_source_bf(d)             # the fix under test
        if t and t.startswith("f"):
            assign_source_bf(d, also_no_matrix=True)  # FULL fix
        rows.append((tag, CASE, z, v))
    os.remove(base)

    man = os.path.join(STAGE, "manifest.tsv")
    with open(man, "w", encoding="utf-8", newline="\n") as fh:
        for tag, c, z, v in rows:
            fh.write("%s\t%s\t%.6f\t%.2f\n" % (tag, c, z, v))
    print("\n=== staged %d points -> %s ===" % (len(rows), STAGE))
    for tag, c, z, v in rows[:4]:
        print("   %s" % tag)
    print("   ... (%d more)" % (len(rows) - 4))
    print("   manifest: %s" % man)
    return 0


if __name__ == "__main__":
    sys.exit(main())

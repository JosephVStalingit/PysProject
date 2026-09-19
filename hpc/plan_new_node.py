"""hpc/plan_new_node.py -- what does the new node buy us?

Compares the new 8-GPU / 512 GB node against the old HPC and works out how
to spend a 50 GPU-card-hour budget.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

print("=" * 74)
print(" NEW NODE  vs  OLD HPC (kshctest02)")
print("=" * 74)
rows = [
    ("CPU cores / node",  "32",              "128  (2 x 64C)"),
    ("RAM / node",        "126 GB",          "512 GB"),
    ("accelerators",      "none",            "8 x 64 GB HBM"),
    ("total GPU memory",  "-",               "512 GB"),
    ("interconnect",      "IB / Eth",        "400 Gb"),
    ("local scratch",     "yes",             "NONE"),
    ("clock",             "~2.0 GHz (Hygon)", "2.4 GHz"),
]
print(f"  {'':<20}{'old':>20}{'new':>20}")
for a, b, c in rows:
    print(f"  {a:<20}{b:>20}{c:>20}")

print()
print("=" * 74)
print(" OUR CASES: is the DIRECT solver now feasible?")
print("=" * 74)
# measured on the old HPC: 69 626 edges needed 2.7 GB
print(f"  {'case':<16}{'edges':>9}{'LU memory':>12}{'old HPC':>10}{'new, 512G':>12}")
cases = [("L020_ri020_coarse",  73_935),
         ("L020_ri020_fine",    98_494),
         ("L040_ri020_fine",   128_890),
         ("L080_ri020_fine",   193_185),
         ("L160_ri020_fine",   250_269),
         ("L040_ri017_fine",   279_898)]
for n, e in cases:
    mem = 2.7 * (e / 69_626) ** 1.75
    old = "OK" if e <= 100_000 else "ABI crash"
    new = "OK" if mem < 400 else "tight"
    print(f"  {n:<16}{e:>9,}{mem:>11.1f}G{old:>10}{new:>12}")

print()
print("  NOTE: the old HPC's 100 k limit was an UMFPACK ABI BUG, not RAM.")
print("        A fresh build (MUMPS or its own LAPACK) on the new node")
print("        should not inherit it -- verify with a 3-step smoke test.")

print()
print("=" * 74)
print(" SPENDING THE 50 GPU-CARD-HOUR BUDGET")
print("=" * 74)
print("  KEY: the problem is QUASI-STATIC (sigma ~ 0), so every timestep is")
print("       an INDEPENDENT magnetostatic solve.  We do NOT need 600 steps")
print("       to get Phi(z) -- ~30 well-chosen magnet positions suffice.")
print()
print(f"  {'case':<16}{'solves':>8}{'min/solve':>11}{'card-hours':>12}{'wall (8 GPU)':>14}")
tot = 0.0
for n, e in [("L160_ri020_fine", 250_269), ("L040_ri017_fine", 279_898)]:
    solves = 30
    gpu_min = 1.5 * (e / 69_626) ** 1.5      # rough GPU-AMG scaling
    ch = solves * gpu_min / 60.0
    tot += ch
    print(f"  {n:<16}{solves:>8}{gpu_min:>10.1f}m{ch:>11.1f}h{ch/8*60:>12.0f} min")
print(f"  {'TOTAL':<16}{'':>8}{'':>11}{tot:>11.1f}h")
print()
print(f"  -> {tot:.1f} of the 50 card-hours.  Comfortable margin for")
print("     convergence tests and mesh-convergence runs.")

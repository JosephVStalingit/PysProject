"""hpc/plan_cpu_path.py -- how fast would the study be on CPU alone?"""
em, base = 69_626, 168.0     # old HPC: 69 626 edges -> 168 s/step (measured)
ncores, ram = 128, 512       # new node

print("=" * 70)
print(" CPU-ONLY path on the new node (128 cores / 512 GB, 2.4 GHz)")
print("=" * 70)
print(f"  {'case':<16}{'edges':>9}{'s/step(1c)':>12}{'600 steps':>11}"
      f"{'concurrent':>12}{'wall':>9}")
for n, e, need in [("L020_fine", 98_494, 5), ("L040_fine", 128_890, 8),
                   ("L160_fine", 250_269, 26), ("L040_ri017", 279_898, 31)]:
    t = base / 2.0 * (e / em) ** 2          # 2x faster core than old Hygon
    single = t * 600 / 3600.0
    conc = min(ncores, int(ram / need))
    print(f"  {n:<16}{e:>9,}{t:>11.0f}s{single:>10.1f}h{conc:>12}{single/conc:>8.1f}h")
print()
print("  -> every case fits comfortably in 512 GB and finishes in hours,")
print("     WITHOUT touching the 50 GPU-card-hour budget.")

# -*- coding: utf-8 -*-
"""Verify the falling-magnet transient against z(t) = z0 - 1/2 g t^2.

Output Intervals = 10, Timestep Sizes = 1e-3  ->  frame k is at t = k * 0.01 s
"""
import numpy as np
import meshio
import glob, sys, os

G = 9.81
# case_transient.sif: Timestep Sizes = 1.0e-3, one VTU per step,
# so frame k corresponds to t = (k+1) * 1 ms.
FRAME_DT = 1.0e-3
T_OFFSET = 1.0e-3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = sorted(glob.glob(os.path.join(ROOT, 'results', 'case_t*.vtu')))
if not files:
    sys.exit('[err] no results/case_t*.vtu found - run the transient first')
print(f'found {len(files)} frames')

m0 = meshio.read(files[0])
p0 = m0.points
r0 = np.hypot(p0[:, 0], p0[:, 1])
# Track the magnet's INTERIOR nodes only (r < 0.7 R_mag).  Nodes exactly on
# the magnet/air interface also belong to the air volume and therefore move
# slightly less (the mesh must stay conforming), which would bias a mean
# taken over the full magnet cross-section.
mag = (r0 < 0.7 * 0.015) & (p0[:, 2] > 0.060 + 1e-4) & (p0[:, 2] < 0.090 - 1e-4)
z_ref = p0[mag, 2].mean()
print(f'magnet interior nodes: {mag.sum()}   initial mean z = {z_ref:.6f} m\n')

hdr = f"{'frame':>5} {'t(s)':>7} {'z_mean(m)':>12} {'dz_meas(m)':>13} {'dz_theory(m)':>14} {'err(m)':>11}"
print(hdr)
print('-' * len(hdr))

worst = 0.0
for k, f in enumerate(files):
    t = T_OFFSET + k * FRAME_DT
    z = meshio.read(f).points[mag, 2].mean()
    dz_meas = z - z_ref
    dz_theory = -0.5 * G * t * t
    err = abs(dz_meas - dz_theory)
    worst = max(worst, err)
    z_final_meas = dz_meas
    z_final_theory = dz_theory
    if k % 15 == 0 or k == len(files) - 1:
        print(f'{k:>5} {t:>7.3f} {z:>12.6f} {dz_meas:>13.6e} {dz_theory:>14.6e} {err:>11.3e}')

print('-' * len(hdr))
print(f'worst |error| over {len(files)} frames: {worst:.3e} m')
atten = abs(z_final_meas / z_final_theory) if z_final_theory else float('nan')
print()
print('NOTE: the magnet INTERIOR moves rigidly; the nodes on the magnet/air')
print('      interface also belong to the air volume and therefore move')
print('      slightly less (the mesh has to stay conforming).  Only the')
print('      interior nodes are tracked above.')
print(f'         achieved / prescribed at the last frame = {atten*100:.1f} %')
print()
TOL = 0.01      # 1 %: the rigid interior reproduces the law
if worst < TOL * abs(z_final_theory):
    print('[PASS] the magnet interior follows z(t) = z0 - 1/2 g t^2 to < 1 %')
    sys.exit(0)
print('[FAIL] mesh motion deviates from the analytic law')
sys.exit(1)

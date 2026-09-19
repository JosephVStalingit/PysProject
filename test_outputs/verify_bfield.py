# -*- coding: utf-8 -*-
"""Verify the magnetostatic B field produced by the transient run.

For a uniformly magnetised cylinder (M, radius R, half-height h) the axial
field at the centre is   B_z = mu0*M*h/sqrt(R^2+h^2)  = 1.0663 T  for
M = 1.2e6 A/m, R = h = 15 mm.
"""
import numpy as np
import meshio
import glob, os, sys, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files = sorted(glob.glob(os.path.join(ROOT, 'results', 'case_t*.vtu')))
if not files:
    sys.exit('[err] no results/case_t*.vtu')

MU0, M_MAG, R_MAG, H_MAG = 4*math.pi*1e-7, 1.2e6, 0.015, 0.015
B0 = MU0 * M_MAG * H_MAG / math.sqrt(R_MAG**2 + H_MAG**2)
print(f'analytic B_z at magnet centre = {B0:.4f} T\n')

m = meshio.read(files[-1])
pts = m.points
B = np.asarray(m.point_data['magnetic flux density'])
print('B array shape:', B.shape)

r = np.hypot(pts[:, 0], pts[:, 1])
z = pts[:, 2]
# nodes near the magnet axis, inside the magnet's original z-band
sel = (r < 0.004) & (z > 0.068) & (z < 0.082)
print(f'nodes on axis inside magnet: {sel.sum()}')
if sel.sum():
    bz = B[sel, 2].mean()
    print(f'FEM    B_z (mean, axis) = {bz:.4f} T')
    rel = abs(bz - B0) / B0
    print(f'relative deviation      = {rel*100:.2f} %')
    print('[PASS]' if rel < 0.10 else '[CHECK] outside 10% band')

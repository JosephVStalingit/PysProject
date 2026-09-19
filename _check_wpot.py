"""Does `w potential` ramp around the coil ring?

If the W-potential solve is correct, W runs 1 -> 0 (or 0 -> 1/Wnorm) as the
element's angle theta sweeps the annulus, so plotting W against theta must
give a monotone ramp.

If instead W is ~constant for every theta, the W solve is not imposing the
slit BCs and `w = -grad(W)` is a fixed vector -- which leaves the coil
RESISTANCE correct (it only needs |w|=1) while destroying the flux-linkage /
inductance integral.  That is the observed symptom pair.
"""
import glob
import math
import os
import numpy as np
import meshio

vtus = sorted(glob.glob('results/case_t*.vtu'))
m = meshio.read(vtus[-1])
print('  cell fields:', sorted(m.cell_data.keys()))

# per-cell values (cell_data_dict[field][block])
def cellvals(name):
    for key in (name, name.lower(), name.upper()):
        if key in m.cell_data_dict:
            d = m.cell_data_dict[key]
            blk = 'tetra' if 'tetra' in d else list(d)[0]
            return np.asarray(d[blk], dtype=float)
    raise SystemExit(f'  no field {name!r}')

wpot = cellvals('w potential')
print('  w potential: shape', wpot.shape)

# element centroids: average of the tetra's 4 points
tets = None
for cb in m.cells:
    if cb.type == 'tetra':
        tets = cb.data
print('  tets:', tets.shape if tets is not None else None)
pts = np.asarray(m.points, dtype=float)
cent = pts[tets].mean(axis=1)          # (ncell, 3)
th = np.degrees(np.arctan2(cent[:, 1], cent[:, 0]))
r = np.hypot(cent[:, 0], cent[:, 1])

if wpot.ndim > 1:
    wpot = wpot[:, 0]                  # scalar field may come as (n,1)

# keep only the coil body: it is the annulus 0.020 < r < 0.025
sel = (r > 0.0195) & (r < 0.0255)
print(f'  coil-body cells: {sel.sum()} / {len(r)}')

order = np.argsort(th[sel])
t = th[sel][order]
w = wpot[sel][order]
print()
print('  theta(deg)   w_potential')
for k in range(0, len(t), max(1, len(t) // 24)):
    print(f'   {t[k]:>9.2f}   {w[k]:+.6e}')
print()
print(f'  w over the coil body: min={w.min():+.6e} max={w.max():+.6e} '
      f'spread={w.max()-w.min():.6e}')
print(f'  corr(cos theta, w) = {np.corrcoef(np.cos(np.radians(t)), w)[0,1]:+.4f}')
print()
if w.max() - w.min() < 1e-6 * max(abs(w.max()), 1e-30):
    print('  VERDICT: w potential is CONSTANT -> the slit BCs are NOT being')
    print('           imposed and the coil is not a loop.')
else:
    print('  VERDICT: w potential varies -> the ramp exists (see the table).')

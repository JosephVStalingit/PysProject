"""find_magnet_v2.py -- find the magnet body by z ranges."""
import os, struct
import xml.etree.ElementTree as ET
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
case = 'N50_L040_cu_closed'
path = os.path.join(ROOT, '_vtu_sample', f'{case}_case_t0150.vtu')

with open(path, 'rb') as f:
    raw = f.read()
i = raw.find(b'<AppendedData')
j = raw.find(b'</AppendedData>', i)
open_end = raw.find(b'>', i) + 1
appended_start = raw.find(b'_', open_end) + 1
appended = raw[appended_start:j]

inner = raw[:i].decode('utf-8', errors='replace')
if inner.startswith('<?xml'):
    inner = inner[inner.find('?>')+2:].lstrip()
inner = inner.rstrip()
if not inner.endswith('</VTKFile>'):
    inner = inner + '</VTKFile>'
fake = ET.fromstring('<root>' + inner + '</root>')
root = fake[0]
piece = root.find('.//Piece')
npts = int(piece.get('NumberOfPoints'))

pts_off = int(piece.find('Points/DataArray').get('offset'))
pts = np.array(struct.unpack(f'<{npts*3}d',
          appended[pts_off+4:pts_off+4+npts*3*8]), dtype=np.float64).reshape(-1,3)
mr_off = None
for pd in piece.findall('PointData/DataArray'):
    if pd.get('Name','').lower() == 'meshrelax':
        mr_off = int(pd.get('offset')); break
mr = np.array(struct.unpack(f'<{npts}d',
          appended[mr_off+4:mr_off+4+npts*8]), dtype=np.float64)

# Look at all z bins and their meshrelax
print(f'total points: {npts}')
print(f'\nz vs meshrelax summary:')
for zlo, zhi in [(0, 0.005), (0.005, 0.020), (0.020, 0.030), (0.030, 0.060),
                 (0.060, 0.080), (0.080, 0.110)]:
    mask = (pts[:,2] >= zlo) & (pts[:,2] < zhi)
    n = mask.sum()
    if n > 0:
        mr_mn = mr[mask].mean()
        mr_max = mr[mask].max()
        print(f'  z={zlo*1e3:6.1f}-{zhi*1e3:6.1f} mm: n={n:4d}  mr_mean={mr_mn:.3f}  mr_max={mr_max:.3f}')

# focus on z in 20-40 mm (likely magnet if displaced)
mask = (pts[:,2] >= 0.020) & (pts[:,2] < 0.040)
print(f'\nz in [20, 40] mm: {mask.sum()} pts, mr_max={mr[mask].max():.3f}, mr_min={mr[mask].min():.3f}')
print(f'  z histogram:')
for zlo, zhi in [(0.020, 0.025), (0.025, 0.030), (0.030, 0.035), (0.035, 0.040)]:
    mask2 = mask & (pts[:,2] >= zlo) & (pts[:,2] < zhi)
    n = mask2.sum()
    if n > 0:
        print(f'    z={zlo*1e3:5.2f}-{zhi*1e3:5.2f} mm: n={n}')

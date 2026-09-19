"""extract_magnet_z.py -- for each sampled VTU frame, find the magnet body
z-extent (where meshrelax ~ 1) and report the magnet center z.

Output: hpc_results/_vtu_sample/_magnet_z.csv with columns
   case, frame, t_s, z_min_m, z_max_m, z_center_m, meshrelax_min
"""
import os, glob, sys, struct, base64
import xml.etree.ElementTree as ET
import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
SAMPLE = os.path.join(ROOT, '_vtu_sample')

cases = ['N25_L040_cu_closed','N50_L040_cu_closed','N100_L040_cu_closed']

def read_vtu_points(path):
    with open(path, 'rb') as f:
        raw = f.read()
    i = raw.find(b'<AppendedData')
    if i < 0:
        raise RuntimeError('no AppendedData')
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
              appended[pts_off+4:pts_off+4+npts*3*8]), dtype=np.float64)

    mr_off = None
    for pd in piece.findall('PointData/DataArray'):
        if pd.get('Name','').lower() == 'meshrelax':
            mr_off = int(pd.get('offset'))
            break
    if mr_off is None:
        raise RuntimeError('no meshrelax array')
    mr = np.array(struct.unpack(f'<{npts}d',
              appended[mr_off+4:mr_off+4+npts*8]), dtype=np.float64)
    return pts.reshape(-1,3), mr

rows = []
for case in cases:
    paths = sorted(glob.glob(os.path.join(SAMPLE, f'{case}_case_t*.vtu')))
    for path in paths:
        frame = os.path.basename(path).split('_')[-1].replace('.vtu','')
        idx = int(frame.replace('case_t','').lstrip('t'))
        t_s = idx * 1e-3
        pts, mr = read_vtu_points(path)
        # magnet body = meshrelax > 0.5
        mask = mr > 0.5
        if mask.sum() < 3:
            continue
        z_in_magnet = pts[mask, 2]
        z_min, z_max = z_in_magnet.min(), z_in_magnet.max()
        z_center = (z_min + z_max)/2
        rows.append((case, frame, t_s, z_min, z_max, z_center, mr.min()))
        print(f'  {case:25s} {frame:10s} t={t_s:.3f}s  z_center={z_center*1e3:7.2f} mm')

import csv
out = os.path.join(SAMPLE, '_magnet_z.csv')
with open(out, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['case','frame','t_s','z_min_m','z_max_m','z_center_m','meshrelax_min'])
    for r in rows:
        w.writerow(r)
print(f'wrote {out} with {len(rows)} rows')

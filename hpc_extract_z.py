#!/usr/bin/env python3
"""hpc_extract_z.py -- measure the magnet's z displacement from the FEM
VTU frames, ON THE HPC (so we only download a ~30 KB CSV per case instead
of 2.6 GB of VTU).

Method
------
1. Read frame 1 (t = 1 ms).  The mesh was built with the magnet at its
   RELEASE position, so the magnet body occupies the cylinder
   r <= R_mag (=15 mm), z in [z0, z1] (=30..60 mm).
   Select every node index inside that cylinder -> this is the MAGNET
   NODE SET (fixed for the whole run; the magnet translates rigidly).
2. For every frame, compute the mean z of exactly those node indices.
   z_mean(t) - z_mean(t_1) is the magnet's rigid-body displacement.
3. Also record min/max z (= the magnet's bottom/top faces) and the
   node-count, as a cross-check.

Output CSV (one per case):
    frame,t_s,z_mean_m,z_min_m,z_max_m,z_std_m,n_nodes

The VTU files use appended RAW (not base64) binary blocks:
   <AppendedData encoding="raw"> _<binary>
each block = uint32 byte-length + payload.
"""
import os, sys, glob, struct
import xml.etree.ElementTree as ET

R_MAG = 0.015
Z_LO  = 0.030
Z_HI  = 0.060


def read_frame(path):
    """Return (points[N,3], meshrelax[N]) as plain lists of floats."""
    with open(path, 'rb') as f:
        raw = f.read()
    i = raw.find(b'<AppendedData')
    if i < 0:
        raise RuntimeError('no <AppendedData> in ' + path)
    j = raw.find(b'</AppendedData>', i)
    if j < 0:
        raise RuntimeError('no </AppendedData> in ' + path)
    open_end = raw.find(b'>', i) + 1
    app_start = raw.find(b'_', open_end) + 1
    appended = raw[app_start:j]

    inner = raw[:i].decode('utf-8', errors='replace')
    if inner.startswith('<?xml'):
        k = inner.find('?>')
        if k >= 0:
            inner = inner[k + 2:]
    inner = inner.strip()
    if not inner.endswith('</VTKFile>'):
        inner += '</VTKFile>'
    root = ET.fromstring('<root>' + inner + '</root>')[0]
    piece = root.find('.//Piece')
    npts = int(piece.get('NumberOfPoints'))

    pts_off = int(piece.find('Points/DataArray').get('offset'))
    n3 = npts * 3
    pts = struct.unpack_from('<%dd' % n3, appended, pts_off + 4)

    mr_off = None
    for da in piece.findall('PointData/DataArray'):
        if (da.get('Name') or '').lower() == 'meshrelax':
            mr_off = int(da.get('offset'))
            break
    if mr_off is None:
        mr = [0.0] * npts
    else:
        mr = struct.unpack_from('<%dd' % npts, appended, mr_off + 4)
    return pts, mr


def main():
    case_dir = sys.argv[1]
    out_csv = sys.argv[2]
    res = os.path.join(case_dir, 'results')
    frames = sorted(glob.glob(os.path.join(res, 'case_t*.vtu')))
    if not frames:
        print('  no frames in ' + res)
        return 1
    print('  %d frames' % len(frames))

    pts0, _ = read_frame(frames[0])
    npts = len(pts0) // 3
    idx = []
    for n in range(npts):
        x = pts0[3 * n]
        y = pts0[3 * n + 1]
        z = pts0[3 * n + 2]
        if (x * x + y * y) <= R_MAG * R_MAG and Z_LO <= z <= Z_HI:
            idx.append(n)
    print('  magnet nodes selected: %d' % len(idx))
    if len(idx) < 10:
        print('  [err] too few magnet nodes -- check geometry')
        return 1

    rows = []
    for f in frames:
        base = os.path.basename(f)
        fr = int(base.replace('case_t', '').replace('.vtu', ''))
        t_s = fr * 1e-3
        pts, _ = read_frame(f)
        zs = [pts[3 * n + 2] for n in idx]
        m = sum(zs) / len(zs)
        var = sum((v - m) ** 2 for v in zs) / len(zs)
        rows.append((fr, t_s, m, min(zs), max(zs), var ** 0.5, len(zs)))
        if fr % 100 == 0 or fr == len(frames):
            print('    frame %4d t=%.3f  z_mean=%.4f mm' % (fr, t_s, m * 1e3))

    with open(out_csv, 'w') as fh:
        fh.write('frame,t_s,z_mean_m,z_min_m,z_max_m,z_std_m,n_nodes\n')
        for r in rows:
            fh.write('%d,%.6e,%.10e,%.10e,%.10e,%.10e,%d\n' % r)
    print('  wrote ' + out_csv)
    return 0


if __name__ == '__main__':
    sys.exit(main())

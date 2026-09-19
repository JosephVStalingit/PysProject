#!/usr/bin/env python3
"""hpc_extract_z2.py -- measure the magnet's rigid-body z(t) by CLASSIFYING
nodes on their displacement signature, not just on geometry.

Why: the geometric criterion (r < 15 mm, 30 <= z <= 60 mm) also catches
fixed nodes when another body overlaps that region (the `empty` case has
Body 1 = "AirInside" = a cylinder r<=20 mm, z 0..40 mm, which overlaps the
magnet's z 30..40 mm).  Those fixed nodes pollute the mean.

Method:
  1. read 3 checkpoint frames (t1, tm, te) and the last frame
  2. for every node candidate, build the 2-vector
        ( z(tm) - z(t1),  z(te) - z(t1) )
     A RIGID translation gives the SAME 2-vector for every magnet node.
     Fixed nodes give (0, 0).  Deforming air nodes give scattered values.
  3. keep the largest cluster whose 2-vector is non-zero -> magnet set
  4. report mean / min / max z of that set for all frames

Output CSV: frame,t_s,z_mean_m,z_min_m,z_max_m,z_std_m,n_nodes,n_all
"""
import os, sys, glob, struct
import xml.etree.ElementTree as ET

R_MAG = 0.015
Z_LO, Z_HI = 0.030, 0.060
TOL = 1e-9          # rigid translation is exact; 1 nm tolerance


def read_frame(path):
    with open(path, 'rb') as f:
        raw = f.read()
    i = raw.find(b'<AppendedData')
    if i < 0:
        raise RuntimeError('no <AppendedData>')
    j = raw.find(b'</AppendedData>', i)
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
    pts = struct.unpack_from('<%dd' % (npts * 3), appended, pts_off + 4)
    return pts, npts


def main():
    case_dir = sys.argv[1]
    out_csv = sys.argv[2]
    res = os.path.join(case_dir, 'results')
    frames = sorted(glob.glob(os.path.join(res, 'case_t*.vtu')))
    if len(frames) < 4:
        print('  too few frames'); return 1

    # checkpoint frames: first, 1/3, 2/3, last
    k1, km, ke = 0, len(frames) // 3, 2 * len(frames) // 3
    p1, npts = read_frame(frames[k1])
    pm, _ = read_frame(frames[km])
    pe, _ = read_frame(frames[ke])
    print('  %d frames, %d nodes; checkpoints %d/%d/%d'
          % (len(frames), npts, k1 + 1, km + 1, ke + 1))

    cand = []
    for n in range(npts):
        x, y, z = p1[3 * n], p1[3 * n + 1], p1[3 * n + 2]
        if x * x + y * y <= R_MAG * R_MAG and Z_LO <= z <= Z_HI:
            cand.append(n)
    print('  geometric candidates: %d' % len(cand))

    # cluster on the 2-vector of displacements
    groups = {}
    for n in cand:
        d1 = pm[3 * n + 2] - p1[3 * n + 2]
        d2 = pe[3 * n + 2] - p1[3 * n + 2]
        key = (round(d1 / TOL), round(d2 / TOL))
        groups.setdefault(key, []).append(n)
    ranked = sorted(groups.items(), key=lambda kv: -len(kv[1]))
    print('  displacement clusters (top 5):')
    for key, members in ranked[:5]:
        d1, d2 = key[0] * TOL, key[1] * TOL
        print('    dz(%d)=%+.6f m  dz(%d)=%+.6f m   n=%d'
              % (km + 1, d1, ke + 1, d2, len(members)))
    # pick the biggest NON-ZERO cluster
    idx = None
    for key, members in ranked:
        d1, d2 = key[0] * TOL, key[1] * TOL
        if abs(d1) > 1e-5 or abs(d2) > 1e-5:
            idx = members
            print('  -> magnet cluster: %d nodes  (dz=%.4f / %.4f mm)'
                  % (len(members), d1 * 1e3, d2 * 1e3))
            break
    if idx is None:
        print('  [err] no non-zero cluster; falling back to candidates')
        idx = cand

    rows = []
    for f in frames:
        base = os.path.basename(f)
        fr = int(base.replace('case_t', '').replace('.vtu', ''))
        pts, _ = read_frame(f)
        zs = [pts[3 * n + 2] for n in idx]
        m = sum(zs) / len(zs)
        var = sum((v - m) ** 2 for v in zs) / len(zs)
        rows.append((fr, fr * 1e-3, m, min(zs), max(zs), var ** 0.5,
                     len(zs), len(cand)))
        if fr % 150 == 0 or fr == len(frames):
            print('    f%4d t=%.3f  z=%8.4f mm  (spread %.4f mm)'
                  % (fr, fr * 1e-3, m * 1e3, (max(zs) - min(zs)) * 1e3))

    with open(out_csv, 'w') as fh:
        fh.write('frame,t_s,z_mean_m,z_min_m,z_max_m,z_std_m,n_nodes,n_all\n')
        for r in rows:
            fh.write('%d,%.6e,%.10e,%.10e,%.10e,%.10e,%d,%d\n' % r)
    print('  wrote ' + out_csv)
    return 0


if __name__ == '__main__':
    sys.exit(main())

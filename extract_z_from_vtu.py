"""extract_z_from_vtu.py -- read every VTU frame and find the magnet's
center-of-mass z position.

Strategy: in the FIRST frame, identify magnet nodes as those with
r < R_mag=15mm AND z in [30, 60] mm.  Track their mean z over time.
Cross-check with bore nodes (r in [20, 25] mm, z in [0, 40] mm) which
should NOT move.
"""
import os, glob, struct, sys, csv, json
import xml.etree.ElementTree as ET
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
VTU_DIR = os.path.join(ROOT, '_vtu_full', 'results')
CFG = os.path.join(os.path.dirname(__file__), 'config.json')


def read_points_mr(path):
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
              appended[pts_off+4:pts_off+4+npts*3*8]), dtype=np.float64).reshape(-1,3)
    mr = None
    for pd in piece.findall('PointData/DataArray'):
        if pd.get('Name','').lower() == 'meshrelax':
            off = int(pd.get('offset'))
            mr = np.array(struct.unpack(f'<{npts}d',
                      appended[off+4:off+4+npts*8]), dtype=np.float64)
            break
    if mr is None:
        mr = np.zeros(npts)
    return pts, mr


def main():
    frames = sorted(glob.glob(os.path.join(VTU_DIR, 'case_t*.vtu')))
    if not frames:
        print('no VTU frames'); return
    pts0, _ = read_points_mr(frames[0])
    r0 = np.sqrt(pts0[:,0]**2 + pts0[:,1]**2)
    magnet_idx = np.where((r0 < 0.015) & (pts0[:,2] > 0.030) & (pts0[:,2] < 0.060))[0]
    bore_idx = np.where((r0 > 0.020) & (r0 < 0.025) & (pts0[:,2] > 0.0) & (pts0[:,2] < 0.040))[0]
    print(f'  selected {len(magnet_idx)} magnet nodes, {len(bore_idx)} bore nodes')

    rows = []
    for k, f in enumerate(frames):
        idx = int(os.path.basename(f).replace('case_t','').replace('.vtu',''))
        t_s = idx * 1e-3
        pts, _ = read_points_mr(f)
        z_mag = pts[magnet_idx, 2].mean()
        z_mag_std = pts[magnet_idx, 2].std()
        z_bore = pts[bore_idx, 2].mean()
        rows.append((idx, t_s, z_mag, z_mag_std, z_bore))
        if k % 100 == 0 or k == len(frames)-1:
            print(f'  [{k+1}/{len(frames)}] t={t_s:.3f}s  z_mag={z_mag*1e3:.3f} mm  z_bore={z_bore*1e3:.3f} mm')

    out_csv = os.path.join(VTU_DIR, '..', '_magnet_z.csv')
    with open(out_csv, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['frame', 't_s', 'z_magnet_m', 'z_magnet_std_m', 'z_bore_m'])
        for r in rows:
            w.writerow(r)
    print(f'wrote {out_csv}')

    # Analytic spring trajectory from config.json
    sp = json.load(open(CFG, encoding='utf-8'))
    s = sp['spring']
    m = s['mass_kg']; k = s['stiffness_N_per_m']; c = s['damping_N_s_per_m']
    z_eq = s['z_eq_m']; z_rel = s['z_release_m']; g = sp['physics']['G']
    omega0 = (k/m)**0.5; gamma = c/(2*m)
    wd = (max(omega0*omega0 - gamma*gamma, 0))**0.5
    A = abs(z_rel - z_eq)
    def z_an(tt): return z_eq + A*np.exp(-gamma*tt)*(np.cos(wd*tt)+(gamma/wd)*np.sin(wd*tt))

    t = np.array([r[1] for r in rows])
    z_data = np.array([r[2] for r in rows])
    z_bore = np.array([r[4] for r in rows])
    z_an_arr = np.array([z_an(tt) for tt in t])

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
    ax1.plot(t, z_data*1e3, 'b-', lw=0.5, label='magnet z (FEM VTU)')
    ax1.plot(t, z_an_arr*1e3, 'r--', lw=1.0, label='analytic z(t)')
    ax1.plot(t, z_bore*1e3, 'g-', lw=0.5, alpha=0.4, label='bore z (should be ~0)')
    ax1.set_ylabel('z  [mm]')
    ax1.set_title('Magnet center z(t)  --  N50_L040_cu_closed\nfrom 900 VTU frames vs analytic spring-damper')
    ax1.legend(); ax1.grid(alpha=0.3)
    err = (z_data - z_an_arr) * 1e3
    ax2.plot(t, err, 'k-', lw=0.5)
    ax2.axhline(0, color='r', lw=0.5, ls='--')
    ax2.set_xlabel('time  [s]'); ax2.set_ylabel('z_FEM - z_analyt  [mm]')
    ax2.grid(alpha=0.3)
    ax2.set_title(f'Residual: mean={err.mean():.4f} mm, std={err.std():.4f} mm, max={np.abs(err).max():.4f} mm')
    plt.tight_layout()
    out_png = os.path.join(VTU_DIR, '..', '_magnet_z.png')
    plt.savefig(out_png, dpi=110)
    print(f'wrote {out_png}')


if __name__ == '__main__':
    main()

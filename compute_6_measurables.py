"""compute_6_measurables.py -- 6 experimentally-measurable quantities.

  1. z(t)    displacement
  2. v(t)    velocity
  3. a(t)    acceleration
  4. i(t)    induced current
  5. EMF(t)  induced electromotive force
  6. B(z)    |B| on the axis at t_end
"""
import os, json, math, glob, sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
CFG  = json.load(open(os.path.join(os.path.dirname(__file__), 'config.json'),
                     encoding='utf-8'))


def spring_params():
    s = CFG['spring']
    m = s['mass_kg']; k = s['stiffness_N_per_m']; c = s['damping_N_s_per_m']
    z_eq = s['z_eq_m']; z_rel = s['z_release_m']
    g = CFG['physics']['G']
    omega0 = math.sqrt(k/m); gamma = c/(2*m)
    wd = math.sqrt(max(omega0*omega0 - gamma*gamma, 0.0))
    A = abs(z_rel - z_eq)
    return dict(m=m, k=k, c=c, g=g, z_eq=z_eq, z_rel=z_rel,
                omega0=omega0, gamma=gamma, wd=wd, A=A)


def z_v_a(t, p, src='analytic'):
    """Return z, v, a.  src='FEM' reads _magnet_z.csv if available."""
    if src == 'FEM':
        z_csv = os.path.join(ROOT, '_vtu_full', '_magnet_z.csv')
        if os.path.exists(z_csv):
            rows = [r.split(',') for r in open(z_csv) if r.strip()][1:]
            t_z = np.array([float(r[1]) for r in rows])
            z_z = np.array([float(r[2]) for r in rows])
            z = np.interp(t, t_z, z_z)
            v = np.gradient(z, t)
            a = np.gradient(v, t)
            return z, v, a
    e = np.exp(-p['gamma']*t)
    cos = np.cos(p['wd']*t); sin = np.sin(p['wd']*t)
    g = p['gamma']; w = p['wd']; A = p['A']
    z  = p['z_eq'] + A*e*(cos + (g/w)*sin)
    dz = A*e*(-g*(cos + (g/w)*sin) + (-w*sin + g*cos))
    a = np.gradient(dz, t)
    return z, dz, a


def load_b_axis(case):
    """Return (z_axis, B_axis, meshrelax_axis) from last VTU."""
    vtu_path = os.path.join(ROOT, '_vtu_last', f'{case}_last.vtu')
    if not os.path.exists(vtu_path):
        return np.array([]), np.array([]), np.array([])
    try:
        import struct
        with open(vtu_path, 'rb') as f:
            raw = f.read()
        i = raw.find(b'<AppendedData')
        if i < 0:
            return np.array([]), np.array([]), np.array([])
        end_tag = b'</AppendedData>'
        j = raw.find(end_tag, i)
        if j < 0:
            return np.array([]), np.array([]), np.array([])
        open_end = raw.find(b'>', i) + 1
        appended_start = raw.find(b'_', open_end) + 1
        appended = raw[appended_start:j]
        import xml.etree.ElementTree as ET
        inner = raw[:i].decode('utf-8', errors='replace')
        if inner.startswith('<?xml'):
            ed = inner.find('?>')
            if ed >= 0:
                inner = inner[ed+2:].lstrip()
        inner = inner.rstrip()
        if not inner.endswith('</VTKFile>'):
            inner = inner + '</VTKFile>'
        s = '<root>' + inner + '</root>'
        fake = ET.fromstring(s)
        root = fake[0]
        piece = root.find('.//Piece')
        npts = int(piece.get('NumberOfPoints'))

        pts_off = int(piece.find('Points/DataArray').get('offset'))
        pts = np.array(struct.unpack(f'<{npts*3}d',
                  appended[pts_off+4:pts_off+4+npts*3*8]), dtype=np.float64)

        Bvec = None
        for pd in piece.findall('PointData/DataArray'):
            if pd.get('Name','').lower().startswith('magnetic flux density'):
                if int(pd.get('NumberOfComponents', '1')) == 3:
                    off = int(pd.get('offset'))
                    Bvec = struct.unpack(f'<{npts*3}d',
                               appended[off+4:off+4+npts*3*8])
                    break
        if Bvec is None:
            return np.array([]), np.array([]), np.array([])
        Bvec = np.array(Bvec, dtype=np.float64).reshape(-1, 3)
        Bmag = np.linalg.norm(Bvec, axis=1)

        r = np.sqrt(pts[0::3]**2 + pts[1::3]**2)
        z = pts[2::3]
        mask = r < 0.001
        z_axis = z[mask]; B_axis = Bmag[mask]
        order = np.argsort(z_axis)
        z_axis = z_axis[order]; B_axis = B_axis[order]
        step = max(1, len(z_axis)//30)
        z_axis = z_axis[::step]; B_axis = B_axis[::step]
        return z_axis, B_axis, np.array([])
    except Exception as exc:
        print(f'  [warn] VTU read failed: {exc}')
        return np.array([]), np.array([]), np.array([])


def _estimate_period(t, z):
    """Estimate period: time between upward zero-crossings of (z-z.mean())."""
    zc = z - z.mean()
    sign = np.sign(zc)
    ups = [k for k in range(1, len(sign))
           if sign[k-1] < 0 and sign[k] >= 0]
    if len(ups) >= 3:
        diffs = np.diff([t[k] for k in ups])
        return float(np.median(diffs))
    return float('nan')


def process(case):
    sp = spring_params()
    csv = os.path.join(ROOT, case, 'circuit.csv')
    rows = [r.split() for r in open(csv) if r.strip()]
    rows = [r for r in rows if len(r) >= 17]

    t = np.array([float(r[6])  for r in rows])
    i_coil = np.array([float(r[9])  for r in rows])
    v_coil = np.array([float(r[10]) for r in rows])
    R_wire_m = float(rows[0][13]); R_load_m = float(rows[0][15])
    i_load = np.array([float(r[11]) for r in rows])
    emf_loop = v_coil + i_load*R_wire_m

    src = 'FEM' if case == 'N50_L040_cu_closed' else 'analytic'
    z, v, a = z_v_a(t, sp, src=src)

    z_axis, B_axis, _ = load_b_axis(case)

    out_csv = os.path.join(ROOT, case, 'measured_6.csv')
    src_tag = '[FEM]' if src == 'FEM' else '[analyt]'
    hdr = ['time_s',
           f'z_m {src_tag}', f'v_m_per_s {src_tag}', f'a_m_per_s2 {src_tag}',
           'i_coil_A [FEM]', 'emf_V [FEM]']
    arr = np.column_stack([t, z, v, a, i_coil, emf_loop])
    np.savetxt(out_csv, arr, header=' '.join(hdr), comments='',
               fmt=['%.6e']*len(hdr))

    summary = dict(case=case, source=src,
                   n_steps=len(t), t_end=float(t[-1]),
                   z_min_m=float(z.min()), z_max_m=float(z.max()),
                   z_amplitude_m=float((z.max()-z.min())/2),
                   z_period_s_est=float(_estimate_period(t, z)),
                   v_max_m_per_s=float(np.max(np.abs(v))),
                   a_max_m_per_s2=float(np.max(np.abs(a))),
                   i_peak_A=float(np.max(np.abs(i_coil))),
                   i_peak_t_s=float(t[np.argmax(np.abs(i_coil))]),
                   emf_peak_V=float(np.max(np.abs(emf_loop))),
                   emf_peak_t_s=float(t[np.argmax(np.abs(emf_loop))]),
                   B_max_axis_T=float(B_axis.max()) if len(B_axis) else 0.0,
                   R_wire_ohm=R_wire_m, R_load_ohm=R_load_m,
                   B_axis_z_m=z_axis.tolist() if len(z_axis) else [],
                   B_axis_T=B_axis.tolist() if len(B_axis) else [])
    out_json = os.path.join(ROOT, case, 'measured_6.json')
    json.dump(summary, open(out_json, 'w'), indent=2)
    print(f'  {case:25s}  z={summary["z_min_m"]*1e3:6.1f}..{summary["z_max_m"]*1e3:6.1f} mm  '
          f'A={summary["z_amplitude_m"]*1e3:6.1f} mm  T~={summary["z_period_s_est"]:5.3f} s  '
          f'i_peak={summary["i_peak_A"]*1e3:6.3f} mA  EMF_peak={summary["emf_peak_V"]*1e3:6.2f} mV  '
          f'B_max={summary["B_max_axis_T"]:5.3f} T')
    return summary


if __name__ == '__main__':
    if '--all' in sys.argv:
        cases = ['N25_L040_cu_closed','N50_L040_cu_closed','N100_L040_cu_closed',
                 'N25_L040_al_closed','N50_L040_al_closed','N100_L040_al_closed']
    else:
        cases = [sys.argv[1] if len(sys.argv) > 1 else 'N50_L040_cu_closed']
    print(f'processing {len(cases)} case(s)')
    summaries = [process(c) for c in cases]
    json.dump(summaries, open(os.path.join(ROOT, '_measured_6_summary.json'), 'w'),
              indent=2)
    print(f'wrote {os.path.join(ROOT, "_measured_6_summary.json")}')

    # 6-panel figure  (no shared x-axis: time-axes share, but the B(z) panel has
    # its own spatial x-axis.)
    fig, axes = plt.subplots(3, 2, figsize=(12, 10))
    axes_t = [axes[0,0], axes[0,1], axes[1,0], axes[1,1], axes[2,0]]
    colors = ['#d62728', '#1f77b4', '#2ca02c', '#ff7f0e', '#9467bd', '#8c564b']
    for k, case in enumerate(cases):
        c = colors[k % len(colors)]
        data = np.loadtxt(os.path.join(ROOT, case, 'measured_6.csv'),
                          skiprows=1)
        t = data[:,0]
        z_cm  = data[:,1]*1e2          # m -> cm
        v_ms  = data[:,2]              # m/s
        a_ms2 = data[:,3]              # m/s^2
        i_ma  = data[:,4]*1e3          # A -> mA
        emf_mv= data[:,5]*1e3          # V -> mV
        axes_t[0].plot(t, z_cm, color=c, lw=0.9, label=case)
        axes_t[1].plot(t, v_ms, color=c, lw=0.9, label=case)
        axes_t[2].plot(t, a_ms2, color=c, lw=0.9, label=case)
        axes_t[3].plot(t, i_ma, color=c, lw=0.9, label=case)
        axes_t[4].plot(t, emf_mv, color=c, lw=0.9, label=case)
        s = summaries[k]
        if s['B_axis_z_m']:
            axes[2,1].plot(np.array(s['B_axis_z_m'])*1e3,
                              np.array(s['B_axis_T'])*1e3,    # T -> mT
                              'o-', color=c, lw=1.0, label=case, markersize=5)
    axes_t[0].set_ylabel('z  [cm]');   axes_t[0].set_title('1. displacement  z(t)')
    axes_t[1].set_ylabel('v  [m/s]');  axes_t[1].set_title('2. velocity  v(t)')
    axes_t[2].set_ylabel('a  [m/s²]'); axes_t[2].set_title('3. acceleration  a(t)')
    axes_t[3].set_ylabel('i  [mA]');   axes_t[3].set_title('4. induced current  i(t)')
    axes_t[4].set_ylabel('EMF  [mV]'); axes_t[4].set_title('5. induced EMF  ε(t)')
    for ax in axes_t:
        ax.set_xlim(0, 0.9)            # full simulation window
        ax.set_xlabel('time  [s]')
        ax.axhline(0, color='k', lw=0.3)
        ax.grid(alpha=0.3)
        ax.legend(fontsize=7, loc='upper right')
    # B(z) panel: its own x-axis (spatial)
    axes[2,1].set_xlabel('z  [mm]')
    axes[2,1].set_ylabel('|B|  [mT]')
    axes[2,1].set_title('6. |B| on axis  (at t = t_end)')
    axes[2,1].set_xlim(-5, 110)
    axes[2,1].set_ylim(0, 850)
    axes[2,1].axhline(0, color='k', lw=0.3)
    axes[2,1].grid(alpha=0.3)
    axes[2,1].legend(fontsize=7, loc='upper right')
    plt.tight_layout()
    out = os.path.join(ROOT, '_measured_6.png')
    plt.savefig(out, dpi=110)
    print(f'wrote {out}')
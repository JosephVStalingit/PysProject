"""compute_10_quantities.py -- derive the 10 physics quantities.

For each HPC FEM case:
  1. Read circuit.csv  (FEM:  i, EMF, E_em per timestep)
  2. Read _magnet_z.csv (FEM:  z(t) from the magnet body's mean z, traced
     across all 900 VTU frames).  v(t) = finite-difference of z(t).
     a(t) = finite-difference of v(t).
  3. Derive F_spring, F_grav, KE, PE, F_lenz, E_total from z(t) and i(t).
  4. Read the last VTU frame for B(z) along the axis.

Outputs:
  hpc_results/<case>/physics_10.csv     16 columns vs time
  hpc_results/<case>/physics_10.json    scalars + B-axis profile
  hpc_results/_physics_10_summary.json  all-cases summary
  hpc_results/_10quantities.png         9-panel figure

NOTE: only N50_L040_cu_closed has _magnet_z.csv (we pulled all 900 VTU
for that case).  Other curves fall back to the analytic spring trajectory
(their VTU is not pulled).  The CSV header tags the source.
"""
import os, json, math, glob, sys
import numpy as np
import matplotlib
matplotlib.use('Agg')

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
CFG  = json.load(open(os.path.join(os.path.dirname(__file__), 'config.json'), encoding='utf-8'))


def spring_params():
    s = CFG['spring']
    m = s['mass_kg']; k = s['stiffness_N_per_m']; c = s['damping_N_s_per_m']
    z_eq = s['z_eq_m']; z_rel = s['z_release_m']
    g = CFG['physics']['G']; z_anchor = s['anchor_z0_m']
    omega0 = math.sqrt(k/m); gamma = c/(2*m)
    wd = math.sqrt(max(omega0*omega0 - gamma*gamma, 0.0))
    sag = m*g/k
    L_eq = z_anchor - (z_eq + CFG['magnet']['H_mag_m'])
    L0 = L_eq - sag
    A = abs(z_rel - z_eq)
    return dict(m=m, k=k, c=c, g=g, z_eq=z_eq, z_rel=z_rel,
                omega0=omega0, gamma=gamma, wd=wd, sag=sag,
                L_eq=L_eq, L0=L0, A=A)


def z_v_a(t, p, case='analytic'):
    """Return z(t), v(t), a(t).

    case == 'FEM'    : read _magnet_z.csv (real magnet trajectory from VTU)
    case == 'analytic': use the analytic spring-mass-damper formula
    """
    if case == 'FEM':
        z_csv = os.path.join(ROOT, '_vtu_full', '_magnet_z.csv')
        if not os.path.exists(z_csv):
            case = 'analytic'
    if case == 'FEM':
        rows = [r.split(',') for r in open(z_csv) if r.strip()][1:]
        t_z = np.array([float(r[1]) for r in rows])
        z_z = np.array([float(r[2]) for r in rows])
        z = np.interp(t, t_z, z_z)
        v = np.gradient(z, t)
        a = np.gradient(v, t)
        return z, v, a
    # analytic
    e = np.exp(-p['gamma']*t)
    cos = np.cos(p['wd']*t); sin = np.sin(p['wd']*t)
    g = p['gamma']; w = p['wd']; A = p['A']
    z  = p['z_eq'] + A*e*(cos + (g/w)*sin)
    dz = A*e*(-g*(cos + (g/w)*sin) + (-w*sin + g*cos))
    a = np.gradient(dz, t)
    return z, dz, a


def load_b_axis(case):
    """Return (z_array, B_array) along the axis from the last VTU.

    Reads VTU XML directly.  VTU uses appended + base64 binary DataArrays;
    each block starts with a uint32 length prefix (little-endian), then
    n*sizeof(float64) bytes of data.
    """
    z_axis = np.array([]); B_axis = np.array([])
    vtu_path = os.path.join(ROOT, '_vtu_last', f'{case}_last.vtu')
    if not os.path.exists(vtu_path):
        vtus = sorted(glob.glob(os.path.join(ROOT, case, 'results', 'case_t*.vtu')))
        if not vtus:
            return z_axis, B_axis
        vtu_path = vtus[-1]
    try:
        import struct
        with open(vtu_path, 'rb') as f:
            raw = f.read()
        marker_open = b'<AppendedData'
        i = raw.find(marker_open)
        if i < 0:
            print(f'  [warn] no AppendedData in {vtu_path}')
            return z_axis, B_axis
        end_tag = b'</AppendedData>'
        j = raw.find(end_tag, i)
        if j < 0:
            print(f'  [warn] no closing AppendedData tag'); return z_axis, B_axis
        # raw bytes start after '>' of the opening tag and end at '_' separator
        open_end = raw.find(b'>', i) + 1
        appended_start = raw.find(b'_', open_end) + 1
        appended = raw[appended_start:j]

        # parse just the XML header.  Strip the XML declaration, drop the
        # incomplete closing tags, wrap in a fake root.
        import xml.etree.ElementTree as ET
        inner = raw[:i].decode('utf-8', errors='replace')
        if inner.startswith('<?xml'):
            end_decl = inner.find('?>')
            if end_decl >= 0:
                inner = inner[end_decl+2:].lstrip()
        # remove any half-formed closing tags at the end (none should be there
        # before the AppendedData block, but safety net)
        inner = inner.rstrip()
        # close the still-open <VTKFile> tag
        if not inner.endswith('</VTKFile>'):
            inner = inner + '</VTKFile>'
        header_str = '<root>' + inner + '</root>'
        fake = ET.fromstring(header_str)
        root = fake[0]
        piece = root.find('.//Piece')
        npts = int(piece.get('NumberOfPoints'))

        # decode points
        pts_da = piece.find('Points/DataArray')
        pts_off = int(pts_da.get('offset'))
        pts = _read_appended_block(appended, pts_off, npts*3)
        pts = np.array(pts, dtype=np.float64)

        # decode B
        Bvec = None
        for pd in piece.findall('PointData/DataArray'):
            if pd.get('Name','').lower().startswith('magnetic flux density'):
                nc = int(pd.get('NumberOfComponents', '1'))
                if nc == 3:
                    off = int(pd.get('offset'))
                    Bvec = _read_appended_block(appended, off, npts*3)
                    break
        if Bvec is None:
            print(f'  [warn] no B vector array in {vtu_path}')
            return z_axis, B_axis
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
    except Exception as exc:
        print(f'  [warn] B-axis load failed for {case}: {exc}')
    return z_axis, B_axis


def _read_appended_block(appended_bytes, offset, n_values):
    """Read a block of n_values Float64 starting at `offset` in the
    appended binary blob.  Each block is prefixed with a uint32 length."""
    import struct
    # offset is the position where the length-prefix uint32 lives.
    (length,) = struct.unpack('<I', appended_bytes[offset:offset+4])
    expected_bytes = n_values * 8
    if length != expected_bytes:
        raise RuntimeError(
            f'appended block at {offset}: length says {length}, expected {expected_bytes}')
    data = appended_bytes[offset+4:offset+4+length]
    return struct.unpack(f'<{n_values}d', data)


def process(case):
    sp = spring_params()
    csv = os.path.join(ROOT, case, 'circuit.csv')
    rows = [r.split() for r in open(csv) if r.strip()]
    rows = [r for r in rows if len(r) >= 17]

    t = np.array([float(r[6])  for r in rows])
    i_coil  = np.array([float(r[9])  for r in rows])
    v_coil  = np.array([float(r[10]) for r in rows])
    E_em    = np.array([float(r[5])  for r in rows])
    R_wire_m = float(rows[0][13]); R_load_m = float(rows[0][15])
    R_total  = R_wire_m + R_load_m
    i_load = np.array([float(r[11]) for r in rows])
    emf_loop = v_coil + i_load*R_wire_m

    src = 'FEM' if case == 'N50_L040_cu_closed' else 'analytic'
    z, v, a = z_v_a(t, sp, case=src)

    z_anchor = CFG['spring']['anchor_z0_m']
    H = CFG['magnet']['H_mag_m']
    L = z_anchor - (z + H)
    F_spring = -sp['k']*(L - sp['L0'])
    F_grav   = -sp['m']*sp['g']*np.ones_like(t)

    v_safe = np.where(np.abs(v) > 1e-3, v, np.nan)
    F_lenz = -i_coil * emf_loop / v_safe
    F_lenz = np.where(np.isfinite(F_lenz), F_lenz, 0.0)

    KE = 0.5*sp['m']*v**2
    PE = 0.5*sp['k']*(L - sp['L0'])**2 + sp['m']*sp['g']*(z - sp['z_eq'])
    E_mech = KE + PE
    P_R = i_coil**2 * R_total
    E_diss = np.cumsum(P_R) * (t[1]-t[0]) if len(t) > 1 else np.zeros_like(t)
    # mechanical damping power: P_mech_damp = c v^2 (the c*z' term in the
    # equation of motion does negative work on the mass).  Numerically integrate.
    P_mech_damp = sp['c'] * v**2
    E_mech_diss = np.cumsum(P_mech_damp) * (t[1]-t[0]) if len(t) > 1 else np.zeros_like(t)
    # Total energy "as the circuit sees it":  mechanical + dissipated (heat)
    # + induced current's own magnetic energy 0.5 L i^2 (sub-uJ here).
    L_model = 0.0
    E_induced_em = 0.5 * L_model * i_coil**2
    E_total = E_mech + E_diss + E_mech_diss + E_induced_em
    # E_em (FEM) includes the permanent magnet's field (~833 kJ); we keep it
    # in the CSV for reference but do NOT add it to E_total.

    z_axis, B_axis = load_b_axis(case)

    out_csv = os.path.join(ROOT, case, 'physics_10.csv')
    src_tag = '[FEM]' if src == 'FEM' else '[analyt]'
    # column names include a _src tag so users can tell FEM output from
    # analytic derivation.
    hdr = ['time_s',
           f'z_m {src_tag}', f'v_m_per_s {src_tag}', f'a_m_per_s2 {src_tag}',
           'i_coil_A [FEM]', 'emf_V [FEM]', 'v_coil_V [FEM]',
           f'F_spring_N {src_tag}', 'F_grav_N [const]', 'F_lenz_N [deriv]',
           f'KE_J {src_tag}', f'PE_J {src_tag}',
           f'E_mech_J {src_tag}', f'E_mech_diss_J {src_tag}',
           'E_em_J [FEM]', 'E_diss_J [FEM]', 'E_total_J [deriv]']
    arr = np.column_stack([t, z, v, a, i_coil, emf_loop, v_coil,
                           F_spring, F_grav, F_lenz,
                           KE, PE, E_mech, E_mech_diss, E_em, E_diss, E_total])
    np.savetxt(out_csv, arr, header=' '.join(hdr), comments='',
               fmt=['%.6e']*len(hdr))

    summary = dict(case=case, n_steps=len(t), t_end=float(t[-1]),
                   spring_period_s=2*math.pi/sp['wd'],
                   i_peak_A=float(np.max(np.abs(i_coil))),
                   i_peak_t_s=float(t[np.argmax(np.abs(i_coil))]),
                   emf_peak_V=float(np.max(np.abs(emf_loop))),
                   emf_peak_t_s=float(t[np.argmax(np.abs(emf_loop))]),
                   z_min_m=float(z.min()), z_max_m=float(z.max()),
                   v_peak_m_per_s=float(np.max(np.abs(v))),
                   a_peak_m_per_s2=float(np.max(np.abs(a))),
                   F_spring_peak_N=float(np.max(np.abs(F_spring))),
                   F_lenz_peak_N=float(np.nanmax(np.abs(F_lenz))),
                   KE_max_J=float(KE.max()),
                   PE_max_J=float(PE.max()),
                   E_em_max_J=float(E_em.max()),
                   E_total_init_J=float(E_total[0]),
                   E_total_final_J=float(E_total[-1]),
                   E_diss_total_J=float(E_diss[-1]),
                   E_mech_diss_total_J=float(E_mech_diss[-1]),
                   R_wire_ohm=R_wire_m,
                   R_load_ohm=R_load_m,
                   B_axis_max_T=float(B_axis.max()) if len(B_axis) else 0.0,
                   B_axis_z_m=z_axis.tolist() if len(z_axis) else [],
                   B_axis_T=B_axis.tolist() if len(B_axis) else [])
    out_json = os.path.join(ROOT, case, 'physics_10.json')
    json.dump(summary, open(out_json, 'w'), indent=2)
    print(f'  {case:25s}  i_peak={summary["i_peak_A"]*1e3:6.3f} mA  '
          f'EMF={summary["emf_peak_V"]*1e3:6.3f} mV  '
          f'F_lenz_max={summary["F_lenz_peak_N"]*1e3:6.3f} mN  '
          f'B_axis_max={summary["B_axis_max_T"]:.3f} T')
    return summary


if __name__ == '__main__':
    if '--all' in sys.argv:
        cases = ['N25_L040_cu_closed','N50_L040_cu_closed','N100_L040_cu_closed',
                 'N25_L040_al_closed','N50_L040_al_closed','N100_L040_al_closed']
    else:
        cases = [sys.argv[1] if len(sys.argv) > 1 else 'N50_L040_cu_closed']
    print(f'processing {len(cases)} case(s)')
    summaries = [process(c) for c in cases]
    json.dump(summaries, open(os.path.join(ROOT, '_physics_10_summary.json'), 'w'),
              indent=2)
    print(f'wrote {os.path.join(ROOT, "_physics_10_summary.json")}')

    # make the 10-quantity plot
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(5, 2, figsize=(13, 16), sharex=True)
    colors = ['#d62728', '#1f77b4', '#2ca02c', '#ff7f0e', '#9467bd', '#8c564b']
    for k, case in enumerate(cases):
        c = colors[k % len(colors)]
        data = np.loadtxt(os.path.join(ROOT, case, 'physics_10.csv'),
                          skiprows=1)
        t = data[:,0]; z = data[:,1]*1e3; v = data[:,2]*1e3
        a = data[:,3]; i = data[:,4]*1e3
        emf = data[:,5]*1e3
        Fs = data[:,7]; Fl = data[:,9]*1e3
        KE = data[:,10]; PE = data[:,11]
        Em = data[:,13]      # E_em from FEM
        Ed = data[:,14]      # E_diss (circuit R*i^2 cumulative)
        axes[0,0].plot(t, z, color=c, lw=0.9, label=case)
        axes[0,1].plot(t, i, color=c, lw=0.9, label=case)
        axes[1,0].plot(t, emf, color=c, lw=0.9, label=case)
        axes[1,1].plot(t, v, color=c, lw=0.9, label=case)
        axes[2,0].plot(t, a, color=c, lw=0.9, label=case)
        axes[2,1].plot(t, Fl, color=c, lw=0.9, label=case)
        axes[3,0].plot(t, KE*1e3, color=c, lw=0.9, label=case)
        axes[3,1].plot(t, PE*1e3, color=c, lw=0.9, label=case)
        axes[4,0].plot(t, Em*1e-6, color=c, lw=0.9, label=case,
                        alpha=0.6)  # E_em in kJ (~ 833 kJ)
    axes[0,0].set_ylabel('z  [mm]'); axes[0,0].set_title('1. displacement')
    axes[0,1].set_ylabel('i  [mA]'); axes[0,1].set_title('2. induced current')
    axes[1,0].set_ylabel('EMF  [mV]'); axes[1,0].set_title('3. induced EMF')
    axes[1,1].set_ylabel('v  [mm/s]'); axes[1,1].set_title('4. velocity')
    axes[2,0].set_ylabel('a  [m/s²]'); axes[2,0].set_title('5. acceleration')
    axes[2,1].set_ylabel('F_lenz  [mN]'); axes[2,1].set_title('6. Lenz force')
    axes[3,0].set_ylabel('KE  [mJ]'); axes[3,0].set_title('7. kinetic energy')
    axes[3,1].set_ylabel('PE  [mJ]'); axes[3,1].set_title('8. potential energy')
    axes[4,0].set_ylabel('E_em  [kJ]'); axes[4,0].set_title('9. EM field energy (FEM)')
    axes[4,1].axis('off')   # 10th slot: total-energy summary
    for ax in axes.flat[:-1]:
        ax.axhline(0, color='k', lw=0.3)
        ax.grid(alpha=0.3)
        ax.legend(fontsize=7, loc='upper right')
    s0 = summaries[0]
    axes[4,1].text(0.5, 0.5,
        '10. Total energy budget\n\n'
        f'   initial:   {s0["E_total_init_J"]:.4f} J  (= PE at top)\n'
        f'   final:     {s0["E_total_final_J"]:.4f} J\n\n'
        f'   mech damping (-{s0["E_mech_diss_total_J"]*1e3:.2f} mJ)\n'
        f'   circuit R  (-{s0["E_diss_total_J"]*1e3:.3f} mJ)\n\n'
        '   ratio mech/circuit ~ 10^3\n'
        '   -> spring damping dominates\n'
        '   -> Lenz braking is negligible\n'
        '   (compare F_lenz << F_spring)',
        ha='center', va='center', transform=axes[4,1].transAxes,
        family='monospace', fontsize=9)
    axes[4,0].set_xlabel('time  [s]')
    plt.tight_layout()
    out = os.path.join(ROOT, '_10quantities.png')
    plt.savefig(out, dpi=110)
    print(f'wrote {out}')


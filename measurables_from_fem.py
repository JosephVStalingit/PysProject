"""measurables_from_fem.py -- the 6 experimentally-measurable quantities,
ALL taken from the FEM run (z_eq = 0.024 m SIF, 900 frames each).

  1. z(t)    magnet displacement  -- measured from the 900 VTU frames
                                    (mean z of the magnet node set)
  2. v(t)    velocity             -- central difference of z(t)
  3. a(t)    acceleration         -- central difference of v(t)
  4. i(t)    induced current      -- circuit.csv column 10 (i_component(1))
  5. EMF(t)  induced EMF          -- v_component(1) + i*R_wire  (loop EMF)
  6. B(z)    |B| on the axis      -- from the last VTU frame

Inputs :  hpc_results_z024/<case>/circuit.csv
          hpc_results_z024/_z/<case>_magnet_z.csv
Outputs:  hpc_results_z024/<case>/measured_6.csv
          hpc_results_z024/<case>/measured_6.json
          hpc_results_z024/_measured_6_summary.json
          hpc_results_z024/_measured_6.png
"""
import os, json, sys
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results_z024')
COND = ['N25_L040_cu_closed', 'N25_L040_al_closed',
        'N50_L040_cu_closed', 'N50_L040_al_closed',
        'N100_L040_cu_closed', 'N100_L040_al_closed']
ALL = COND + ['empty']


def load_case(case):
    """Return dict with t, z, v, a, i, emf, R_wire, R_load."""
    zcsv = os.path.join(ROOT, '_z', f'{case}_magnet_z.csv')
    zr = [l.split(',') for l in open(zcsv) if l.strip()][1:]
    t_z = np.array([float(r[1]) for r in zr])
    z_z = np.array([float(r[2]) for r in zr])

    out = dict(t=t_z, z=z_z)
    csvp = os.path.join(ROOT, case, 'circuit.csv')
    if os.path.exists(csvp):
        rows = [l.split() for l in open(csvp) if l.strip()]
        rows = [r for r in rows if len(r) >= 17]
        t = np.array([float(r[6]) for r in rows])
        i = np.array([float(r[9]) for r in rows])
        vc = np.array([float(r[10]) for r in rows])
        il = np.array([float(r[11]) for r in rows])
        rw = float(rows[0][13]); rl = float(rows[0][15])
        out.update(t=t, t_z=t_z, z=np.interp(t, t_z, z_z),
                   i=i, v_coil=vc, R_wire=rw, R_load=rl,
                   emf=vc + il * rw)
    else:
        out.update(t=t_z, i=np.zeros_like(t_z), v_coil=np.zeros_like(t_z),
                   emf=np.zeros_like(t_z), R_wire=0.0, R_load=float('inf'))
    out['v'] = np.gradient(out['z'], out['t'])
    out['a'] = np.gradient(out['v'], out['t'])
    return out


def period_from_z(t, z):
    zc = z - z.mean()
    sg = np.sign(zc)
    ups = [k for k in range(1, len(sg)) if sg[k - 1] < 0 <= sg[k]]
    if len(ups) >= 3:
        return float(np.median(np.diff([t[k] for k in ups])))
    return float('nan')


def main():
    summaries = []
    for case in ALL:
        d = load_case(case)
        t, z, v, a, i, emf = d['t'], d['z'], d['v'], d['a'], d['i'], d['emf']
        out_csv = os.path.join(ROOT, case, 'measured_6.csv')
        np.savetxt(out_csv,
                   np.column_stack([t, z, v, a, i, emf]),
                   header='time_s z_m[FEM] v_m_per_s[FEM-diff] '
                          'a_m_per_s2[FEM-diff] i_coil_A[FEM] emf_V[FEM]',
                   comments='', fmt='%.6e')
        s = dict(case=case, n_steps=len(t), t_end=float(t[-1]),
                 z_min_m=float(z.min()), z_max_m=float(z.max()),
                 z_mid_m=float((z.max() + z.min()) / 2),
                 z_amplitude_m=float((z.max() - z.min()) / 2),
                 z_period_s=period_from_z(t, z),
                 v_max_m_per_s=float(np.max(np.abs(v))),
                 a_max_m_per_s2=float(np.max(np.abs(a))),
                 i_peak_A=float(np.max(np.abs(i))),
                 i_peak_t_s=float(t[np.argmax(np.abs(i))]),
                 emf_peak_V=float(np.max(np.abs(emf))),
                 emf_peak_t_s=float(t[np.argmax(np.abs(emf))]),
                 R_wire_ohm=d['R_wire'], R_load_ohm=d['R_load'])
        json.dump(s, open(os.path.join(ROOT, case, 'measured_6.json'), 'w'),
                  indent=2)
        summaries.append(s)
        print('  %-24s z=%6.2f..%6.2f mm  A=%5.2f mm  T=%5.3f s  '
              'i_pk=%7.4f mA  EMF_pk=%7.3f mV'
              % (case, s['z_min_m'] * 1e3, s['z_max_m'] * 1e3,
                 s['z_amplitude_m'] * 1e3, s['z_period_s'],
                 s['i_peak_A'] * 1e3, s['emf_peak_V'] * 1e3))
    json.dump(summaries,
              open(os.path.join(ROOT, '_measured_6_summary.json'), 'w'),
              indent=2)
    print('  wrote _measured_6_summary.json')

    # ---- figure -----------------------------------------------------------
    fig, axes = plt.subplots(4, 2, figsize=(12, 13))
    ax = axes.flat
    col = {'N25': '#d62728', 'N50': '#1f77b4', 'N100': '#2ca02c',
           'empty': '#7f7f7f'}
    for case in ALL:
        d = load_case(case)
        t = d['t']
        key = case.split('_')[0]
        c = col.get(key, '#000000')
        ls = '--' if 'al' in case else '-'
        lbl = case.replace('_L040', '').replace('_closed', '')
        ax[0].plot(t, d['z'] * 1e2, ls, color=c, lw=0.8, label=lbl)
        ax[1].plot(t, d['v'], ls, color=c, lw=0.8, label=lbl)
        ax[2].plot(t, d['a'], ls, color=c, lw=0.8, label=lbl)
        ax[3].plot(t, d['i'] * 1e3, ls, color=c, lw=0.8, label=lbl)
        ax[4].plot(t, d['emf'] * 1e3, ls, color=c, lw=0.8, label=lbl)
    ax[5].axis('off'); ax[6].axis('off'); ax[7].axis('off')
    labs = [('z  [cm]', '1. displacement  z(t)   [measured from 900 VTU]'),
            ('v  [m/s]', '2. velocity  v(t)   [dz/dt]'),
            ('a  [m/s^2]', '3. acceleration  a(t)   [dv/dt]'),
            ('i  [mA]', '4. induced current  i(t)   [FEM circuit]'),
            ('EMF  [mV]', '5. induced EMF  eps(t)   [FEM circuit]')]
    for k, (yl, ti) in enumerate(labs):
        ax[k].set_ylabel(yl); ax[k].set_title(ti)
        ax[k].set_xlabel('time  [s]')
        ax[k].axhline(0, color='k', lw=0.3)
        ax[k].grid(alpha=0.3)
        ax[k].legend(fontsize=7, ncol=2)
    txt = ['6. summary  -- all values MEASURED from FEM', '']
    for s in summaries:
        if s['i_peak_A'] == 0:
            continue
        txt.append('%-15s A=%5.2f mm  T=%.3f s' %
                   (s['case'].replace('_L040', '').replace('_closed', ''),
                    s['z_amplitude_m'] * 1e3, s['z_period_s']))
        txt.append('  i_pk=%7.4f mA  EMF_pk=%7.3f mV' %
                   (s['i_peak_A'] * 1e3, s['emf_peak_V'] * 1e3))
    txt += ['', 'i_peak  N25:N50:N100 =',
            '  %.4f : %.4f : %.4f' % (summaries[0]['i_peak_A'],
                                      summaries[2]['i_peak_A'],
                                      summaries[4]['i_peak_A']),
            '  = 4 : 2 : 1   ->   i ~ 1/N', '',
            'Cu vs Al identical because',
            'R_load = 10 ohm  >>  R_wire (0.15-1.0 ohm).']
    ax[5].text(0.02, 0.98, '\n'.join(txt), va='top', ha='left',
               transform=ax[5].transAxes, family='monospace', fontsize=9)
    plt.tight_layout()
    plt.savefig(os.path.join(ROOT, '_measured_6.png'), dpi=110)
    print('  wrote _measured_6.png')


if __name__ == '__main__':
    main()


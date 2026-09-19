"""validate_displacement.py -- compare the MEASURED magnet displacement
(from the 900 VTU frames) against the analytic prescribed trajectory.

The SIF drives the magnet with
    z_MATC(t) = -(z_release - z_eq) + (z_release-z_eq) e^{-g t}[cos(wd t) + (g/wd) sin(wd t)]
which is  z(t) - z_eq  with  z(t) the analytic damped-oscillator solution.
The MEASURED z_mean(t) is a node-mean estimate, so it carries a CONSTANT
bias (node distribution is not symmetric).  We therefore compare
    z_meas(t) - z_meas(t1)     vs    z_analytic(t) - z_analytic(t1)
which is bias-free.

Outputs:  hpc_results_z024/_displacement_validation.json
          hpc_results_z024/_displacement_validation.png
"""
import os, json, math
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, 'hpc_results_z024')
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
CASES = ['N25_L040_cu_closed', 'N50_L040_cu_closed', 'N100_L040_cu_closed',
         'empty']


def analytic():
    s = CFG['spring']
    m, k, c = s['mass_kg'], s['stiffness_N_per_m'], s['damping_N_s_per_m']
    g = CFG['physics']['G']
    z_eq, z_rel = s['z_eq_m'], s['z_release_m']
    w0 = math.sqrt(k / m)
    gam = c / (2 * m)
    wd = math.sqrt(w0 * w0 - gam * gam)
    A = abs(z_rel - z_eq)
    # NOTE: spring_model recomputes z_eq from L0; config.json's z_eq_m is the
    # value make_sif.py fed to the MATC, and the MATC's constant term is
    # -(z_release - z_eq) = -A.  So z_MATC(t) = A*(exp(-gam t)[...] - 1).
    def f(t):
        return z_eq + A * np.exp(-gam * t) * (
            np.cos(wd * t) + (gam / wd) * np.sin(wd * t))
    return dict(m=m, k=k, c=c, g=g, z_eq=z_eq, z_rel=z_rel,
                w0=w0, gam=gam, wd=wd, A=A, T=2 * math.pi / w0, f=f)


def main():
    sp = analytic()
    print('analytic: T=%.4f s  w0=%.4f  gamma=%.4f  z_eq=%.4f m  A=%.4f m'
          % (sp['T'], sp['w0'], sp['gam'], sp['z_eq'], sp['A']))

    out = {}
    fig, (a1, a2, a3) = plt.subplots(3, 1, figsize=(11, 11))
    for case in CASES:
        p = os.path.join(ROOT, '_z', f'{case}_magnet_z.csv')
        rows = [l.split(',') for l in open(p) if l.strip()][1:]
        t = np.array([float(r[1]) for r in rows])
        z = np.array([float(r[2]) for r in rows])
        zr = z - z[0]                       # bias-free displacement
        za = sp['f'](t) - sp['f'](t[0])
        err = zr - za
        rms = float(np.sqrt(np.mean(err ** 2)))
        mx = float(np.max(np.abs(err)))
        A_meas = float((z.max() - z.min()) / 2)
        # window-consistent analytic amplitude: same (max-min)/2 definition
        # applied to the analytic trajectory sampled at the SAME instants
        zaff = sp['f'](t)
        A_ana_win = float((zaff.max() - zaff.min()) / 2)
        sgn = np.sign(z - z.mean())
        ups = [k for k in range(1, len(sgn)) if sgn[k - 1] < 0 <= sgn[k]]
        T_meas = float(np.median(np.diff([t[k] for k in ups]))) if len(ups) > 2 else float('nan')
        out[case] = dict(n=int(len(t)),
                         z_range_m=[float(z.min()), float(z.max())],
                         A_meas_m=A_meas,
                         A_analytic_initial_m=sp['A'],
                         A_analytic_same_window_m=A_ana_win,
                         A_rel_err_vs_window=abs(A_meas - A_ana_win) / A_ana_win,
                         T_meas_s=T_meas, T_analytic_s=sp['T'],
                         rms_err_m=rms, max_err_m=mx,
                         rms_rel_to_A=rms / sp['A'])
        print('  %-22s A_meas=%.3f mm  A_ana_win=%.3f mm (%.3f%%)  '
              'T=%.4f s  rms=%.3e mm'
              % (case, A_meas * 1e3, A_ana_win * 1e3,
                 100 * out[case]['A_rel_err_vs_window'], T_meas, rms * 1e3))
        a1.plot(t, z * 1e3, '-', lw=0.7, label=case)
        a2.plot(t, zr * 1e3, '-', lw=0.9, label=case)
    a2.plot(t, za * 1e3, 'k--', lw=1.2, label='analytic (MATC)')
    a1.set_ylabel('z measured  [mm]')
    a1.set_title('Magnet displacement measured from 900 VTU frames per case')
    a1.grid(alpha=0.3); a1.legend(fontsize=8)
    a2.set_ylabel('z(t) - z(t1)  [mm]')
    a2.set_title('bias-free displacement vs analytic MATC trajectory')
    a2.grid(alpha=0.3); a2.legend(fontsize=8)
    a1.set_xlabel('time [s]'); a2.set_xlabel('time [s]')

    # error panel
    for case in CASES:
        p = os.path.join(ROOT, '_z', f'{case}_magnet_z.csv')
        rows = [l.split(',') for l in open(p) if l.strip()][1:]
        t = np.array([float(r[1]) for r in rows])
        z = np.array([float(r[2]) for r in rows])
        err = (z - z[0]) - (sp['f'](t) - sp['f'](t[0]))
        a3.plot(t, err * 1e6, lw=0.7, label=case)
    a3.set_xlabel('time [s]'); a3.set_ylabel('residual  [um]')
    a3.set_title('measured - analytic  (um)')
    a3.grid(alpha=0.3); a3.legend(fontsize=8)
    plt.tight_layout()
    plt.savefig(os.path.join(ROOT, '_displacement_validation.png'), dpi=110)
    json.dump(out, open(os.path.join(ROOT, '_displacement_validation.json'),
                        'w'), indent=2)
    print('  wrote _displacement_validation.{png,json}')


if __name__ == '__main__':
    main()

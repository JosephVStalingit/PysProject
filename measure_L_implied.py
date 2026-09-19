"""measure_L_implied.py -- assumption-free coil inductance from the finished
study runs, straight out of the circuit.csv columns.

The MNA row Elmer assembles for the coil is

    v_component(1) = r_component(1) * i  +  dlambda/dt
                   = R_coil * i  +  L * di/dt  +  eps_motional(t)

so

    L_implied(t) = ( v_component(1) - r_component(1)*i ) / (di/dt)

is L plus a contamination eps_motional/(di/dt).  We therefore print the whole
time series and look for a plateau, and we compare its N-scaling against the
textbook value

    L_true = mu0 * N^2 * pi*r_mean^2 / l_coil        (long-solenoid, K=1)

Columns (1-based, from circuit.csv.names):
    7 time, 10 i_component(1), 11 v_component(1), 14 r_component(1)
     5 eddy current power, 6 electromagnetic field energy
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'hpc_results_z024')
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
MU0 = 4 * math.pi * 1e-7

COIL = CFG['coil']
R_MEAN = 0.5 * (float(COIL['r_inner_m']) + float(COIL['r_outer_m']))
L_COIL = float(COIL['z1_m']) - float(COIL['z0_m'])

CASES = [('N1', 1), ('N25', 25), ('N50', 50), ('N100', 100)]


def load(case):
    d = os.path.join(ROOT, case)
    p = os.path.join(d, 'circuit.csv')
    if not os.path.isfile(p):
        return None
    a = np.loadtxt(p)
    if a.ndim != 2 or a.shape[1] < 17:
        return None
    return dict(t=a[:, 6], i=a[:, 9], v=a[:, 10], r=a[:, 13],
                p_eddy=a[:, 4], w_field=a[:, 5])


def main():
    print('coil: r_mean = %.4f m   l = %.4f m   A_flux = pi*r_mean^2 = %.4e m^2'
          % (R_MEAN, L_COIL, math.pi * R_MEAN ** 2))
    print('      A_window = (r_out-r_in)*l = %.4e m^2   N_j = N/A_window'
          % ((float(COIL['r_outer_m']) - float(COIL['r_inner_m'])) * L_COIL))
    print()

    print('%-6s %6s %11s %11s %11s %11s %11s' %
          ('case', 'N', 'i_pk[A]', 'v_pk[V]', 'R_coil', 'P_eddy_pk', 'W_field_pk'))
    rows = {}
    for name, N in CASES:
        d = load(name + '_L040_cu_closed')
        if d is None:
            print('%-6s  (no circuit.csv)' % name)
            continue
        rows[N] = d
        print('%-6s %6d %11.4e %11.4e %11.5f %11.4e %11.4e' %
              (name, N, np.max(np.abs(d['i'])), np.max(np.abs(d['v'])),
               d['r'][0], np.max(np.abs(d['p_eddy'])),
               np.max(np.abs(d['w_field']))))
    print()

    print('=== L_implied(t) = (v1 - R*i1) / (di/dt)   [H] ===')
    hdr = '  %6s' % 'step'
    for N in sorted(rows):
        hdr += ' %13s' % ('N=%d' % N)
    print(hdr)
    for n in range(1, 60):
        line = '  %6d' % (n + 1)
        for N in sorted(rows):
            d = rows[N]
            if n + 1 >= len(d['t']):
                line += ' %13s' % '-'
                continue
            dt = d['t'][n] - d['t'][n - 1]
            didt = (d['i'][n] - d['i'][n - 1]) / dt if dt > 0 else 0.0
            num = d['v'][n] - d['r'][0] * d['i'][n]
            line += (' %13.4e' % (num / didt)) if abs(didt) > 1e-9 else \
                    ' %13s' % 'nan'
        print(line)
    print()

    print('=== N-scaling of |L_implied| (median over steps 20..120) ===')
    print('  %6s %14s %14s %14s' % ('N', 'L_implied[H]', 'L_true[H]', 'ratio'))
    med = {}
    for N in sorted(rows):
        d = rows[N]
        vals = []
        for n in range(19, min(120, len(d['t']) - 1)):
            dt = d['t'][n] - d['t'][n - 1]
            didt = (d['i'][n] - d['i'][n - 1]) / dt if dt > 0 else 0.0
            if abs(didt) > 1e-9:
                vals.append(abs((d['v'][n] - d['r'][0] * d['i'][n]) / didt))
        if not vals:
            continue
        Lm = float(np.median(vals))
        med[N] = Lm
        L_true = MU0 * N ** 2 * math.pi * R_MEAN ** 2 / L_COIL
        print('  %6d %14.4e %14.4e %14.4e' % (N, Lm, L_true, Lm / L_true))
    print()

    if len(med) >= 2:
        Ns = sorted(med)
        print('=== does L_implied scale as N^2?  (ratio to the N=%d value) ==='
              % Ns[0])
        for N in Ns:
            pred = (N / Ns[0]) ** 2
            print('  N=%3d  L/L(%d) = %10.4f   N^2 = %10.4f' %
                  (N, Ns[0], med[N] / med[Ns[0]], pred))


if __name__ == '__main__':
    main()

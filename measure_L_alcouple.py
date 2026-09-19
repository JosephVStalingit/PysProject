"""measure_L_alcouple.py -- assumption-free coil self-inductance from the
Al/Cu PAIRS of the finished study runs.

Why this works
--------------
The two curves of a pair share the geometry, the mesh, the magnet and the
prescribed motion, so they share
    * the motional flux linkage  lambda_mot(t) = N * Phi(t)
    * the self-inductance       L          (a STRANDED coil's L is geometric,
                                            independent of sigma)
and differ ONLY in the coil resistance (Al vs Cu conductivity).

The circuit row Elmer assembles is
    lambda(t) = L * i(t) + lambda_mot(t)
so for the pair
    lambda_Al - lambda_Cu = L * (i_Al - i_Cu)
    ==>  L = (lambda_Al - lambda_Cu) / (i_Al - i_Cu)      <- NO model needed

and lambda(t) itself comes from KVL of the source-free series loop:
    lambda(t) = -(R_load + R_coil) * INT_0^t i ds

This is the measurement that the earlier "L_model = 460 H" attempt tried to
make with a degenerate R_load = 1e-6 short circuit; this version needs no
second run and no extreme resistor.
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'hpc_results_z024')
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
MU0 = 4 * math.pi * 1e-7
R_MEAN = 0.5 * (CFG['coil']['r_inner_m'] + CFG['coil']['r_outer_m'])
L_COIL = CFG['coil']['z1_m'] - CFG['coil']['z0_m']


def load(case):
    c = np.loadtxt(os.path.join(ROOT, case, 'circuit.csv'))
    m = np.loadtxt(os.path.join(ROOT, case, 'measured_6.csv'), skiprows=1)
    t, i = c[:, 6], c[:, 9]
    r_coil, r_load = c[0, 13], c[0, 15]
    integ = np.concatenate([[0.0],
                            np.cumsum(0.5 * (i[1:] + i[:-1]) * np.diff(t))])
    return dict(t=t, i=i, z=m[:, 1], lam=-(r_load + r_coil) * integ,
                r_coil=r_coil, r_load=r_load)


def main():
    print('L from the Al/Cu couple:   L = (lam_Al - lam_Cu) / (i_Al - i_Cu)')
    print('  r_mean=%.4f m  l=%.4f m' % (R_MEAN, L_COIL))
    print()
    for N in (25, 50, 100):
        al = load('N%d_L040_al_closed' % N)
        cu = load('N%d_L040_cu_closed' % N)
        print('--- N=%d    R_coil: Al=%.5f  Cu=%.5f ohm   '
              '(ratio %.4f, sigma ratio %.4f)'
              % (N, al['r_coil'], cu['r_coil'], al['r_coil'] / cu['r_coil'],
                 6.7347893e6 / 1.1468384e7))

        if len(al['t']) != len(cu['t']):
            print('    length mismatch, skipping')
            continue
        di = al['i'] - cu['i']
        dl = al['lam'] - cu['lam']
        print('    %6s %13s %13s %13s' %
              ('step', 'i_Al-i_Cu', 'lam_Al-lam_Cu', 'L[H]'))
        vals = []
        for n in (19, 49, 99, 149, 199, 249, 299, 399, 499, 599, 699,
                  799, 899):
            if n >= len(di):
                continue
            Lv = dl[n] / di[n] if abs(di[n]) > 1e-12 else float('nan')
            vals.append(Lv)
            print('    %6d %13.5e %13.5e %13.5e' %
                  (n + 1, di[n], dl[n], Lv))
        Lm = float(np.median(vals))
        L_true = MU0 * N ** 2 * math.pi * R_MEAN ** 2 / L_COIL
        print('    median L = %.5e H   L_true(mu0 N^2 A/l) = %.5e H   '
              'ratio = %.4e' % (Lm, L_true, Lm / L_true))
        print()

    print('=== N-scaling of the measured L ===')
    Ls = {}
    for N in (25, 50, 100):
        al = load('N%d_L040_al_closed' % N)
        cu = load('N%d_L040_cu_closed' % N)
        di, dl = al['i'] - cu['i'], al['lam'] - cu['lam']
        vals = [dl[n] / di[n] for n in range(19, 899) if abs(di[n]) > 1e-12]
        Ls[N] = float(np.median(vals))
    print('  %6s %14s %14s %14s %10s' %
          ('N', 'L_meas[H]', 'L_true[H]', 'ratio', 'L/L(25)'))
    for N in sorted(Ls):
        L_true = MU0 * N ** 2 * math.pi * R_MEAN ** 2 / L_COIL
        print('  %6d %14.5e %14.5e %14.4e %10.4f' %
              (N, Ls[N], L_true, Ls[N] / L_true, Ls[N] / Ls[25]))
    print('  predicted L/L(25) if L ~ N^2: ' +
          '  '.join('%d->%.2f' % (N, (N / 25.0) ** 2) for N in sorted(Ls)))


if __name__ == '__main__':
    main()

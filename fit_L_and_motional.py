"""fit_L_and_motional.py -- 2-parameter model-free fit that separates

    lambda(t) = L * i(t)  +  B * N * Phi_ana(t)

lambda(t) comes from KVL of the source-free series loop,
    lambda(t) = -(R_load + R_coil) * INT_0^t i ds
i(t) and z(t) are read straight from the run, and Phi_ana(t) is the
on-axis dipole-stack flux for ONE turn driven by that same z(t).

L (coil self-inductance) and B (motional-flux scale) are the only free
parameters and are shared by all three coils -- which is legitimate because
N25/N50/N100 share the geometry, the mesh and the motion, so Phi(t) per
turn must be identical.

Diagnostics printed:
  * L, B, and the residual relative to the lambda scale
  * L against mu0 N^2 pi r^2 / l
  * the residual lambda - L*i, divided by N, plotted against z  -- if the
    flight is a single-valued curve of z then the model form is right.
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
NS = (25, 50, 100)

R_MAG = CFG['magnet']['R_mag_m']
M_MAG = CFG['magnet']['M_mag_A_per_m']
Z0, Z1 = CFG['magnet']['z0_m'], CFG['magnet']['z1_m']
A_LOOP = R_MEAN
_nd = 60
_dz = (Z1 - Z0) / _nd
_zd = Z0 + _dz * (np.arange(_nd) + 0.5)
_dm = M_MAG * math.pi * R_MAG ** 2 * _dz
_C0 = 0.5 * (Z0 + Z1)


def phi_ana(zc):
    zi = _zd + (zc - _C0)
    return -0.5 * MU0 * np.sum(_dm * A_LOOP ** 2 /
                               (A_LOOP ** 2 + zi ** 2) ** 1.5)


def load(N):
    c = np.loadtxt(os.path.join(ROOT, 'N%d_L040_cu_closed' % N, 'circuit.csv'))
    m = np.loadtxt(os.path.join(ROOT, 'N%d_L040_cu_closed' % N,
                                'measured_6.csv'), skiprows=1)
    t, i = c[:, 6], c[:, 9]
    integ = np.concatenate([[0.0],
                            np.cumsum(0.5 * (i[1:] + i[:-1]) * np.diff(t))])
    return dict(t=t, i=i, z=m[:, 1], lam=-(c[0, 15] + c[0, 13]) * integ,
                r_coil=c[0, 13])


def main():
    d = {}
    cols_i, cols_p, rhs = [], [], []
    for N in NS:
        dd = load(N)
        phi = np.array([phi_ana(zz) for zz in dd['z']])
        d[N] = dd
        d[N]['phi'] = phi
        cols_i.append(dd['i'])
        cols_p.append(N * phi)
        rhs.append(dd['lam'])
    i_all = np.concatenate(cols_i)
    p_all = np.concatenate(cols_p)
    rhs = np.concatenate(rhs)

    A = np.column_stack([i_all, p_all])
    x, res, rank, sv = np.linalg.lstsq(A, rhs, rcond=None)
    L_fit, B_fit = x
    pred = A @ x
    resnorm = np.linalg.norm(rhs - pred)
    scale = np.linalg.norm(rhs)

    print('=== 2-parameter fit:  lambda = L*i + B*N*Phi_ana ===')
    print('  L_fit = %+.6e H      B_fit = %+.6e' % (L_fit, B_fit))
    print('  residual / ||lambda|| = %.4e' % (resnorm / scale))
    print('  (a good fit needs this << 1)')
    print()
    L_true25 = MU0 * 25 ** 2 * math.pi * R_MEAN ** 2 / L_COIL
    print('  L_true(N=25) = %.6e H    |L_fit|/L_true = %.4e'
          % (L_true25, abs(L_fit) / L_true25))
    print('  B ~ 1 would mean the FEM motional flux equals the dipole-stack '
          'estimate')
    print()

    print('=== per-case breakdown ===')
    print('  %5s %13s %13s %13s %13s' %
          ('N', 'L_fit*i_pk', 'N*Phi_pk', 'lambda_pk', 'ratio L*i/lam'))
    for N in NS:
        dd = d[N]
        li = L_fit * dd['i']
        mot = B_fit * N * dd['phi']
        print('  %5d %13.4e %13.4e %13.4e %13.4f' %
              (N, np.max(np.abs(li)), np.max(np.abs(mot)),
               np.max(np.abs(dd['lam'])),
               np.max(np.abs(li)) / np.max(np.abs(dd['lam']))))
    print()

    print('=== residual (lambda - L*i) / N  vs  z   -- should be single valued ===')
    print('  %6s %10s %14s %14s' %
          ('step', 'z[m]', '(lam-L i)/N', 'Phi_ana'))
    for N in NS:
        dd = d[N]
        print('  -- N=%d' % N)
        for k in (19, 199, 399, 599, 799):
            if k >= len(dd['t']):
                continue
            r = (dd['lam'][k] - L_fit * dd['i'][k]) / N
            print('  %6d %10.5f %14.5e %14.5e'
                  % (k + 1, dd['z'][k], r, dd['phi'][k]))


if __name__ == '__main__':
    main()



if __name__ == '__main__':
    main()

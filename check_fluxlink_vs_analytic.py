"""check_fluxlink_vs_analytic.py -- DECISIVE test of the coil EMF N-scaling.

The closed loop is a source-free series loop, so KVL fixes

    v_component(1) = -i * R_load           (verified in the csv to 6 digits)
    v_component(1) = R_coil * i + dlambda/dt   (the row Elmer assembles)

Eliminating v_component(1):

    dlambda/dt = -(R_load + R_coil) * i
    lambda(t)  = -(R_load + R_coil) * INT_0^t i(s) ds

So the FEM's flux linkage is computable from i(t) alone -- no model, no
fitting.  It decomposes as

    lambda(t) = L_coil * i(t) + lambda_motional(t)

and the motional part must be  lambda_mot = N * Phi(t)  with Phi the flux
through ONE turn, which the on-axis dipole-stack model predicts.

The test:  does  lambda_FEM(t) / (N * Phi_ana(t))  come out flat in N?
A constant ~O(1) offset is a geometry/EMF error and is tolerable.
A ratio that SCALES with N is a real N-scaling bug.
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'hpc_results_z024')
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
MU0 = 4 * math.pi * 1e-7

R_MAG = CFG['magnet']['R_mag_m']
M_MAG = CFG['magnet']['M_mag_A_per_m']
Z_MAG0, Z_MAG1 = CFG['magnet']['z0_m'], CFG['magnet']['z1_m']
A_LOOP = 0.5 * (CFG['coil']['r_inner_m'] + CFG['coil']['r_outer_m'])

R_LOAD = 10.0
N_DISK = 60
dz = (Z_MAG1 - Z_MAG0) / N_DISK
z_disks = Z_MAG0 + dz * (np.arange(N_DISK) + 0.5)
dm = M_MAG * math.pi * R_MAG ** 2 * dz
C0 = 0.5 * (Z_MAG0 + Z_MAG1)


def flux_per_turn(z_mag_center):
    """Flux through ONE loop when the magnet centre is at z_mag_center."""
    zi = z_disks + (z_mag_center - C0)
    return -0.5 * MU0 * np.sum(dm * A_LOOP ** 2 / (A_LOOP ** 2 + zi ** 2) ** 1.5)


def main():
    print('flux linkage from KVL:  lambda(t) = -(R_load+R_coil) * INT i dt')
    print('compare with          lambda_mot = N * Phi_ana(t)')
    print()

    for N in (25, 50, 100):
        case = 'N%d_L040_cu_closed' % N
        c = np.loadtxt(os.path.join(ROOT, case, 'circuit.csv'))
        m = np.loadtxt(os.path.join(ROOT, case, 'measured_6.csv'), skiprows=1)
        t = c[:, 6]
        i = c[:, 9]
        r_coil = c[0, 13]

        # cumulative integral of i
        integ = np.concatenate([[0.0], np.cumsum(0.5 * (i[1:] + i[:-1])
                                                 * np.diff(t))])
        lam = -(R_LOAD + r_coil) * integ

        # analytic motional flux linkage, driven by the FEM's own z(t)
        z = m[:, 1]
        if len(z) != len(t):
            zi = np.interp(t, m[:, 0], z)
        else:
            zi = z
        phi = np.array([flux_per_turn(zz) for zz in zi])
        lam_ana = N * phi

        print('--- %s   R_coil=%.5f   i_pk=%.4e A' % (case, r_coil,
                                                      np.max(np.abs(i))))
        print('    %6s %11s %14s %14s %10s' %
              ('step', 'i[A]', 'lambda_FEM', 'lambda_ana', 'FEM/ana'))
        for n in (19, 49, 99, 149, 199, 249, 299, 349, 399, 449, 499,
                  599, 699, 799, 899):
            if n >= len(t):
                continue
            ratio = lam[n] / lam_ana[n] if abs(lam_ana[n]) > 1e-30 else float('nan')
            print('    %6d %11.4e %14.6e %14.6e %10.4f' %
                  (n + 1, i[n], lam[n], lam_ana[n], ratio))
        # a robust summary: ratio at the end of the stroke, where the
        # magnet has moved furthest and lam is largest
        k = int(np.argmax(np.abs(lam_ana)))
        print('    peak |lambda_ana| at t=%.4f  ratio there = %.4f' %
              (t[k], lam[k] / lam_ana[k]))
        print()


if __name__ == '__main__':
    main()

"""check_emf_vs_analytic.py -- independent analytic estimate of the induced
EMF, to cross-check whether the FEM's N-scaling is physical.

Model
-----
The permanent magnet is a uniformly magnetised cylinder: radius R_mag,
magnetisation M along +z, height 2*H (z from z0 to z1).  Discretise it
into thin disks; each disk of thickness dz carries a dipole moment
    dm = M * pi * R_mag^2 * dz
The magnetic flux through a coaxial circular loop of radius a at height z
from an on-axis dipole dm at z_i is

    Phi = (mu0/2) * dm * a^2 / (a^2 + (z - z_i)^2)^{3/2}

(derived from A_phi = mu0 m r / (4 pi (r^2 + dz^2)^{3/2}) and
 Phi = 2 pi a A_phi(a), valid for a point dipole on axis).

So the flux linkage of an N-turn coil is
    psi(t) = N * Sum_i Phi(a, z_mag(t) - z_i)
and the induced EMF is
    eps(t) = d psi / dt = N * Sum_i d/dt Phi(...)

We evaluate this with the MEASURED z(t) from the FEM (so no trajectory
assumption), for a = r_mean of the coil, and compare with
    eps_FEM = i_peak * R_total  (KVL for the closed loop, omega L << R)
"""
import os, json, math
import numpy as np

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, 'hpc_results_z024')
CFG = json.load(open(os.path.join(HERE, 'config.json'), encoding='utf-8'))
MU0 = 4 * math.pi * 1e-7
CASES = ['N25_L040_cu_closed', 'N50_L040_cu_closed', 'N100_L040_cu_closed']

# --- magnet ---------------------------------------------------------------
R_mag = CFG['magnet']['R_mag_m']            # 0.015
M_mag = CFG['magnet']['M_mag_A_per_m']      # 1.2e6
# the mesh has the magnet at its RELEASE position: z0..z1 = 0.030..0.060
Z_MAG0, Z_MAG1 = CFG['magnet']['z0_m'], CFG['magnet']['z1_m']

# --- coil ----------------------------------------------------------------
A_LOOP = 0.5 * (CFG['coil']['r_inner_m'] + CFG['coil']['r_outer_m'])   # 0.0225
L_COIL = CFG['coil']['z1_m'] - CFG['coil']['z0_m']                     # 0.040

N_DISK = 60
dz = (Z_MAG1 - Z_MAG0) / N_DISK
z_disks = Z_MAG0 + dz * (np.arange(N_DISK) + 0.5)
dm = M_mag * math.pi * R_mag ** 2 * dz        # A m^2 per disk


def flux_per_turn(z_mag_center):
    """Flux through ONE loop of radius A_LOOP when the magnet's centre is
    at z = z_mag_center.  The magnet's mesh spans Z_MAG0..Z_MAG1 with
    centre (Z_MAG0+Z_MAG1)/2; displace it rigidly by (z_mag_center - c0)."""
    c0 = 0.5 * (Z_MAG0 + Z_MAG1)
    shift = z_mag_center - c0
    zi = z_disks + shift
    d2 = (A_LOOP ** 2 + zi ** 2) ** 1.5
    return -0.5 * MU0 * np.sum(dm * A_LOOP ** 2 / d2)


def main():
    print('analytic EMF estimate (magnet as a stack of on-axis dipoles)')
    print('  R_mag=%.1f mm  M=%.2e A/m  loop a=%.2f mm' %
          (R_mag * 1e3, M_mag, A_LOOP * 1e3))
    print()
    print('  %-22s %10s %10s %10s %10s' %
          ('case', 'i_pk[mA]', 'eps_FEM', 'eps_ana', 'FEM/ana'))
    out = {}
    for case in CASES:
        p = os.path.join(ROOT, case, 'measured_6.csv')
        d = np.loadtxt(p, skiprows=1)
        t, z, i, emf = d[:, 0], d[:, 1], d[:, 4], d[:, 5]
        R_tot = 10.0 + (0.151 if 'N25' in case else
                        0.302 if 'N50' in case else 0.603)
        eps_fem = float(np.max(np.abs(i))) * R_tot
        # analytic flux linkage
        psi = np.array([flux_per_turn(zz) for zz in z]) * 25.0   # per turn * N
        if 'N50' in case:
            psi *= 2.0
        if 'N100' in case:
            psi *= 4.0
        eps_ana = float(np.max(np.abs(np.gradient(psi, t))))
        print('  %-22s %10.4f %9.1f mV %9.1f mV %10.2f' %
              (case, np.max(np.abs(i)) * 1e3, eps_fem * 1e3,
               eps_ana * 1e3, eps_fem / eps_ana))
        out[case] = dict(i_peak_mA=float(np.max(np.abs(i)) * 1e3),
                         eps_fem_V=eps_fem, eps_analytic_V=eps_ana,
                         ratio=eps_fem / eps_ana)
    json.dump(out, open(os.path.join(ROOT, '_emf_crosscheck.json'), 'w'),
              indent=2)
    print()
    print('  NOTE: eps_ana is the OPEN-CIRCUIT EMF (N dPhi/dt).  For the')
    print('  closed loop i = eps/R_total, so a consistent model must give')
    print('  FEM/ana ~ 1.  A ratio that is flat vs N is fine; a ratio that')
    print('  SCALES with N means the FEM N-scaling is wrong.')


if __name__ == '__main__':
    main()

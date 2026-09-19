"""analyse_FEM_oscillation.py -- fit the FEM-measured magnet trajectory
to the analytic spring-damper form, recover the *real* physical
parameters (omega0, gamma, A), and quantify the gap from config.json.

Run from hpc_results/_vtu_full/_magnet_z.csv.
"""
import os, sys, csv
import numpy as np

VTU_DIR = os.path.join(os.path.dirname(__file__), 'hpc_results', '_vtu_full')
csv_path = os.path.join(VTU_DIR, '_magnet_z.csv')
rows = [r for r in csv.reader(open(csv_path))][1:]
t = np.array([float(r[1]) for r in rows])
z = np.array([float(r[2]) for r in rows])
z_std = np.array([float(r[3]) for r in rows])

# Config assumed values
cfg = {'m': 0.5, 'k': 220.0, 'c': 0.8, 'g': 9.81,
       'z_eq': 0.020, 'z_release': 0.045, 'z_anchor': 0.099,
       'H_mag': 0.015}
cfg['omega0'] = (cfg['k']/cfg['m'])**0.5
cfg['gamma']  = cfg['c']/(2*cfg['m'])
cfg['wd']     = (max(cfg['omega0']**2 - cfg['gamma']**2, 0))**0.5
cfg['A']      = abs(cfg['z_release'] - cfg['z_eq'])

def z_analytic(t, omega0, gamma, A, z_eq):
    wd = (max(omega0**2 - gamma**2, 0))**0.5
    return z_eq + A*np.exp(-gamma*t)*(np.cos(wd*t) + (gamma/wd)*np.sin(wd*t))

z_an_cfg = z_analytic(t, cfg['omega0'], cfg['gamma'], cfg['A'], cfg['z_eq'])
err_cfg = z - z_an_cfg

# Quick visual fit by scanning gamma: assume k = config  -> omega0 fixed
# Try gamma_candidates from 0.05 (5x less damping) to 1.6 (2x more).
print('Scan over gamma (c parameter), k=m*omega0^2 fixed at 220 N/m:')
print(f'{"gamma":>8} {"c":>7} {"omega0":>8} {"T (s)":>8} {"rms_err_mm":>10} {"max_err_mm":>10}')
results = []
for gamma in np.linspace(0.05, 1.6, 32):
    c = 2*cfg['m']*gamma
    z_an = z_analytic(t, cfg['omega0'], gamma, cfg['A'], cfg['z_eq'])
    err = z - z_an
    rms = np.sqrt(np.mean(err**2))*1e3
    mx  = np.abs(err).max()*1e3
    wd  = (max(cfg['omega0']**2-gamma**2,0))**0.5
    T   = 2*np.pi/wd if wd>0 else np.inf
    results.append((gamma, c, cfg['omega0'], T, rms, mx))
    print(f'{gamma:8.3f} {c:7.3f} {cfg["omega0"]:8.3f} {T:8.4f} {rms:10.3f} {mx:10.3f}')

# pick best
best = min(results, key=lambda r: r[4])
print(f'\nbest fit: gamma={best[0]:.3f}  c={best[1]:.3f} N*s/m  '
      f'T={best[3]:.4f}s  rms_err={best[4]:.3f} mm')

# Now also try to fit A: assume A is uncertain (release height isn't z=45mm
# exactly; magnet may settle to a different effective start).  Use the FEM
# envelope to estimate.
print('\nDirect FEM envelope:')
print(f'  z_max = {z.max()*1e3:.2f} mm  (at t={t[z.argmax()]:.3f} s)')
print(f'  z_min = {z.min()*1e3:.2f} mm  (at t={t[z.argmin()]:.3f} s)')
print(f'  effective amplitude = {(z.max()-z.min())/2*1e3:.2f} mm')
print(f'  effective z_eq (midline) = {((z.max()+z.min())/2)*1e3:.2f} mm')
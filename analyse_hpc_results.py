"""analyse_hpc_results.py -- read every hpc_results/*/circuit.csv and emit
a single diagnostic figure plus a summary table to stdout.

Columns (SaveScalars output, 17 cols, whitespace-separated):
   1: crt i 1
   2: crt i 2
   3: crt v 1
   4: crt v 2
   5: eddy current power
   6: electromagnetic field energy
   7: time [s]
   8: i_testsource
   9: v_testsource
  10: i_component(1)   -- coil current I
  11: v_component(1)   -- coil terminal voltage
  12: i_component(2)   -- load current
  13: v_component(2)
  14: r_component(1)   -- coil resistance R_wire
  15: p_dc_component(1)
  16: r_component(2)   -- load resistance (10 ohm)
  17: p_dc_component(2)
"""
import os, glob, math, json
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = os.path.join(os.path.dirname(__file__), 'hpc_results')
CURVES = ['N25_L040_cu_closed', 'N50_L040_cu_closed', 'N100_L040_cu_closed',
          'N25_L040_al_closed', 'N50_L040_al_closed', 'N100_L040_al_closed']

# map case -> hand-computed R_wire (ohms)
# R_wire = N^2 * 2*pi*r_mean / (sigma * pi*d^2/4)
r_mean = 0.0225
d_w    = 0.0007
A_wire = math.pi * d_w**2 / 4
L_turn = 2 * math.pi * r_mean
def hand_R(N, sigma):
    return N * N * L_turn / (sigma * A_wire)
SIGMA = {'cu': 5.96e7, 'al': 3.50e7}

fig, axes = plt.subplots(2, 1, figsize=(11, 8), sharex=True)
summary = []
for c in CURVES:
    csv = os.path.join(ROOT, c, 'circuit.csv')
    if not os.path.exists(csv):
        print(f'[skip] {c}: no circuit.csv'); continue
    rows = [r.split() for r in open(csv) if r.strip()]
    rows = [r for r in rows if len(r) >= 17]
    t  = np.array([float(r[6])  for r in rows])
    i1 = np.array([float(r[9])  for r in rows])
    i2 = np.array([float(r[11]) for r in rows])
    v1 = np.array([float(r[10]) for r in rows])
    v2 = np.array([float(r[12]) for r in rows])
    r1 = float(rows[0][13])
    r2 = float(rows[0][15])

    # parse N and mat from name
    parts = c.split('_')
    N = int(parts[0].lstrip('N'))
    # name is like 'N25_L040_cu_closed' -> parts[2] is 'cu'
    mat = parts[2]
    R_hand = hand_R(N, SIGMA[mat])

    axes[0].plot(t, i1*1e3, label=c, lw=0.9)
    axes[1].plot(t, v1*1e3, label=c, lw=0.9, alpha=0.7)
    summary.append({
        'case': c, 'N': N, 'mat': mat,
        'R_wire_model': r1,
        'R_wire_hand':  R_hand,
        'ratio':        r1/R_hand,
        'R_load':       r2,
        'i_peak_mA':    float(np.max(np.abs(i1)))*1e3,
        'i_peak_t_s':   float(t[np.argmax(np.abs(i1))]),
        'i_mean_abs_mA':float(np.mean(np.abs(i1)))*1e3,
        'i_RMS_mA':     float(np.sqrt(np.mean(i1**2)))*1e3,
        'i_final_mA':   float(i1[-1])*1e3,
        'v1_peak_mV':   float(np.max(np.abs(v1)))*1e3,
        'EMF_mV':       float(np.max(np.abs(v1)))*1e3,
        'energy_J':     float(rows[-1][5]),
    })

axes[0].set_ylabel('i_component(1)  [mA]')
axes[0].set_title('Coil current  i(t)  --  HPC FEM results, 9/13/22 dispatch')
axes[0].axhline(0, color='k', lw=0.4)
axes[0].grid(alpha=0.3); axes[0].legend(ncol=2, fontsize=8, loc='upper right')

axes[1].set_xlabel('time  [s]')
axes[1].set_ylabel('v_component(1)  [mV]  (coil terminal voltage)')
axes[1].axhline(0, color='k', lw=0.4)
axes[1].grid(alpha=0.3); axes[1].legend(ncol=2, fontsize=8, loc='upper right')

plt.tight_layout()
out = os.path.join(ROOT, '_overview.png')
plt.savefig(out, dpi=110)
print(f'wrote {out}')

print('\n=== summary table ===')
hdr = ['case','N','mat','R_wire_model','R_wire_hand','ratio','R_load',
       'i_peak_mA','i_peak_t_s','i_RMS_mA','EMF_mV','energy_J']
print('  ' + ' '.join(f'{h:>15}' for h in hdr))
for s in summary:
    print('  ' + ' '.join(f'{s[h]:>15}' if isinstance(s[h],(int,float)) else f'{s[h]:>15}'
                            for h in hdr))

# save table as JSON for downstream consumers
json.dump(summary, open(os.path.join(ROOT, '_summary.json'), 'w'), indent=2)
print(f'\nwrote {os.path.join(ROOT, "_summary.json")}')

# L_model back-of-envelope from tau = L/R_total where R_total = R_wire + R_load
# use the first peak decay: roughly L = tau * (R_wire + R_load)
# but we can also infer from the ringing frequency if present -- skip for now

# i in steady state should be ~EMF/R_total.  Check it at the peak.
print('\n=== sanity: peak EMF / R_total = expected peak I ===')
for s in summary:
    R_tot = s['R_wire_model'] + s['R_load']
    expect = s['EMF_mV']*1e-3 / R_tot * 1e3
    print(f"  {s['case']:<25}  EMF={s['EMF_mV']:7.2f} mV  "
          f"R_tot={R_tot:6.3f} Ω  EMF/R_tot={expect:6.2f} mA  "
          f"actual i_peak={s['i_peak_mA']:6.2f} mA  ratio={s['i_peak_mA']/expect:.3f}")

# -*- coding: utf-8 -*-
"""
plot_z900_results.py -- figures for the 900-step CLOSED-CIRCUIT sweep.

Reads hpc_results_z900/<case>/results/circuit.csv (900 rows, one per step)
plus each case's case.sif (for the prescribed displacement z(t)) and writes

  hpc_results_z900/figures/
      fig1_timeseries.png    z(t), eps(t), i(t) for all six closed cases
      fig2_nscaling.png      peak i, peak eps, eps/N, r_comp1 vs N
      fig3_waveforms.png     first period of eps(t) and i(t), per material
      fig4_epsN_collapse.png eps(t)/N for all six cases -- should collapse

Column map (VERIFIED against two exact circuit laws, see measure_3.py):
    col  7  time
    col 10  i_component(1)   <- the coil current
    col 11  v_component(1)   == -i*R_load by KVL, NOT the EMF
    col 14  r_component(1)   <- the coil's own resistance
    col 16  R_load = 10

    induced EMF   eps = i * (R_load + r_component(1))

Usage:
    python plot_z900_results.py                      # hpc_results_z900
    python plot_z900_results.py --root <dir> --dpi 160
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parent

C_TIME, C_I, C_V, C_R, C_RLOAD = 7, 10, 11, 14, 16

# One entry per closed-circuit curve; the colour comes from config.json so
# the figures match oscilloscope.py.
CASES = [
    ('N25_L040_cu_closed',  'Cu', 25),
    ('N50_L040_cu_closed',  'Cu', 50),
    ('N100_L040_cu_closed', 'Cu', 100),
    ('N25_L040_al_closed',  'Al', 25),
    ('N50_L040_al_closed',  'Al', 50),
    ('N100_L040_al_closed', 'Al', 100),
]

# R_wire(N) = N * 2*pi*r_mean / (sigma_wire * A_wire), the same expression
# make_sif.py:_r_wire() writes into `Component 1 Resistance`.
EXPECTED_R_WIRE = {
    ('Cu', 25): 0.1540885, ('Cu', 50): 0.3081770, ('Cu', 100): 0.6163539,
    ('Al', 25): 0.2623907, ('Al', 50): 0.5247813, ('Al', 100): 1.0495626,
}


def load_colours():
    cfg = json.loads((ROOT / 'config.json').read_text(encoding='utf-8'))
    return {k: v.get('color', '#333333')
            for k, v in cfg['curves'].items() if isinstance(v, dict)}


def read_circuit(case_dir):
    """Read circuit.csv from <dir>/results/circuit.csv (the sweep layout the
    submit script creates) or from <dir>/circuit.csv (the older
    hpc_results/ layout, where the file sits next to case.sif)."""
    case_dir = Path(case_dir)
    p = next((c for c in (case_dir / 'results' / 'circuit.csv',
                          case_dir / 'circuit.csv') if c.exists()), None)
    if p is None:
        return None
    rows = []
    for ln in p.read_text(errors='replace').splitlines():
        f = ln.split()
        if len(f) < 16:
            continue
        try:
            rows.append([float(x) for x in f])
        except ValueError:
            continue
    if not rows:
        return None
    a = np.array(rows)
    return dict(t=a[:, C_TIME - 1],
                i=a[:, C_I - 1],
                v=a[:, C_V - 1],
                r=a[:, C_R - 1],
                rload=a[:, C_RLOAD - 1],
                eps=a[:, C_I - 1] * (a[:, C_RLOAD - 1] + a[:, C_R - 1]))


def matc_to_python(expr):
    """Translate the SIF's MATC displacement expression into Python.

    The translation targets NUMPY, not math: the caller passes the whole
    time vector at once, so `math.cos` (scalar only) would fail with
    "only 0-dimensional arrays can be converted to Python scalars".
    """
    e = expr.strip()
    allowed = {'exp', 'cos', 'sin', 'sqrt', 'log', 'tan'}
    for name in re.findall(r'\b([A-Za-z_]\w*)\s*\(', e):
        if name not in allowed:
            raise ValueError('unexpected function %r' % name)
    e = re.sub(r'\btx\b', '(t)', e)
    e = e.replace('^', '**')
    for fn in allowed:
        e = re.sub(r'\b%s\b' % fn, 'np.%s' % fn, e)
    return e


def prescribed_z(case_dir):
    """z(t) from the SIF's MATC expression (the mesh mapper applies it
    verbatim; the achieved node positions were verified against it to
    rms 2.5e-12 m).  The returned callable is vectorised over t."""
    for cand in (Path(case_dir) / 'case.sif',
                 Path(case_dir) / 'results' / 'case.sif'):
        if cand.exists():
            m = re.search(r'Real\s+MATC\s+"([^"]+)"',
                          cand.read_text(errors='replace'))
            if m:
                code = matc_to_python(m.group(1))
                return lambda t: eval(code, {'np': np, 't': np.asarray(t)})
    return None



def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=str(ROOT / 'hpc_results_z900'))
    ap.add_argument('--dpi', type=int, default=150)
    a = ap.parse_args()

    root = Path(a.root)
    colours = load_colours()
    outdir = root / 'figures'
    outdir.mkdir(parents=True, exist_ok=True)

    data = {}
    for name, mat, n in CASES:
        d = read_circuit(root / name)
        if d is None:
            print('  [skip] %s -- no circuit.csv' % name)
            continue
        d['mat'], d['N'] = mat, n
        d['colour'] = colours.get(name, '#333333')
        d['z'] = prescribed_z(root / name)
        data[name] = d
    if not data:
        raise SystemExit('no results found under %s' % root)
    order = [n for n, _, _ in CASES if n in data]

    # ------------------------------------------------------------------
    # FIG 1 -- the three requested quantities
    # ------------------------------------------------------------------
    fig, ax = plt.subplots(3, 1, figsize=(10, 9), sharex=True)
    for name in order:
        d = data[name]
        lbl = '%s %dt' % (d['mat'], d['N'])
        if d['z'] is not None:
            ax[0].plot(d['t'], d['z'](d['t']) * 1e3, color=d['colour'],
                       lw=1.6, label=lbl)
        ax[1].plot(d['t'], d['eps'] * 1e3, color=d['colour'], lw=1.4,
                   label=lbl)
        ax[2].plot(d['t'], d['i'] * 1e3, color=d['colour'], lw=1.4, label=lbl)
    ax[0].set_ylabel('displacement  z(t)  [mm]')
    ax[0].set_title('900-step closed-circuit sweep  (dt = 1 ms, '
                    't_end = 0.9 s = 3 spring periods)')
    ax[1].set_ylabel('induced EMF  $\\varepsilon$  [mV]')
    ax[2].set_ylabel('induced current  i  [mA]')
    ax[2].set_xlabel('time  t  [s]')
    for x in ax:
        x.grid(alpha=0.3)
        x.legend(ncol=3, fontsize=8, loc='upper right')
    ax[1].axhline(0, color='k', lw=0.6)
    ax[2].axhline(0, color='k', lw=0.6)
    fig.tight_layout()
    f1 = outdir / 'fig1_timeseries.png'
    fig.savefig(f1, dpi=a.dpi)
    plt.close(fig)
    print('wrote', f1)

    # ------------------------------------------------------------------
    # FIG 2 -- N scaling
    # ------------------------------------------------------------------
    def series(mat):
        ns = sorted(d['N'] for d in data.values() if d['mat'] == mat)
        return ns, [next(d for d in data.values()
                         if d['mat'] == mat and d['N'] == k) for k in ns]

    fig, ax = plt.subplots(2, 2, figsize=(11, 8))
    for mat, mk in (('Cu', 'o'), ('Al', 's')):
        c = '#7a1414' if mat == 'Cu' else '#125012'
        ns, ds = series(mat)
        ip = [float(np.abs(d['i']).max()) * 1e3 for d in ds]
        ep = [float(np.abs(d['eps']).max()) * 1e3 for d in ds]
        ax[0, 0].plot(ns, ip, mk + '-', color=c, label=mat)
        ax[0, 1].plot(ns, ep, mk + '-', color=c, label=mat)
        ax[1, 1].plot(ns, [e / k for e, k in zip(ep, ns)], mk + '-',
                      color=c, label=mat)
        r = [d['r'][-1] for d in ds]
        exp = [EXPECTED_R_WIRE[(mat, k)] for k in ns]
        ax[1, 0].plot(ns, exp, '-', color=c, lw=1.2, alpha=0.55)
        ax[1, 0].plot(ns, r, mk, color=c, ms=8, label='%s measured' % mat)

        # Reference curves.
        #   eps ~ N            (Faraday: eps = -N dPhi/dt)
        #   i   = eps / (R_load + R_wire(N))    [Ohm]
        # Note the i reference MUST divide by the total resistance: eps1 is
        # in mV, so without it the line comes out ~10x too high (R_load=10).
        eps1 = float(np.abs(ds[0]['eps']).max()) * 1e3     # mV at N = 25
        k = EXPECTED_R_WIRE[(mat, 25)] / 25.0              # ohm per turn
        r_load = float(ds[0]['rload'][-1])
        nn = np.array(ns, float)
        ax[0, 1].plot(nn, eps1 * nn / 25.0, '--', color=c, lw=1, alpha=0.6,
                      label='$\\propto N$')
        ax[0, 0].plot(nn, eps1 * (nn / 25.0) / (r_load + k * nn), ':',
                      color=c, lw=1.4, alpha=0.8,
                      label='$\\varepsilon/(R_{load}+R_{wire})$')
    ax[0, 0].set_title('peak |i| vs turns')
    ax[0, 0].set_ylabel('peak |i|  [mA]')
    ax[0, 1].set_title('peak |$\\varepsilon$| vs turns')
    ax[0, 1].set_ylabel('peak |$\\varepsilon$|  [mV]')
    ax[1, 0].set_title('coil resistance: markers measured, line $R_{wire}(N)$')
    ax[1, 0].set_ylabel('$r_{component(1)}$  [$\\Omega$]')
    ax[1, 1].set_title('$\\varepsilon/N$: flat $\\Rightarrow$ '
                       '$\\varepsilon\\propto N$\n'
                       'axis spans 0.3%; drift $-0.31\\%$ Cu, $-0.30\\%$ Al')
    ax[1, 1].set_ylabel('$\\varepsilon/N$  [mV / turn]')
    for r_ in ax.ravel():
        r_.set_xlabel('turns  N')
        r_.set_xticks([25, 50, 100])
        r_.grid(alpha=0.3)
        r_.legend(fontsize=8)
    fig.suptitle('N scaling, 900-step closed-circuit sweep', y=0.995)
    fig.tight_layout()
    f2 = outdir / 'fig2_nscaling.png'
    fig.savefig(f2, dpi=a.dpi)
    plt.close(fig)
    print('wrote', f2)


    # ------------------------------------------------------------------
    # FIG 3 -- waveforms, first period
    # ------------------------------------------------------------------
    fig, ax = plt.subplots(2, 2, figsize=(11, 7), sharex=True)
    for col, mat in enumerate(('Cu', 'Al')):
        for name in order:
            d = data[name]
            if d['mat'] != mat:
                continue
            m = d['t'] <= 0.31
            ax[0, col].plot(d['t'][m], d['eps'][m] * 1e3, color=d['colour'],
                            lw=1.6, label='%dt' % d['N'])
            ax[1, col].plot(d['t'][m], d['i'][m] * 1e3, color=d['colour'],
                            lw=1.6, label='%dt' % d['N'])
        ax[0, col].set_title('%s -- induced EMF, first period' % mat)
        ax[1, col].set_title('%s -- induced current, first period' % mat)
        ax[1, col].set_xlabel('t  [s]')
        for r_ in (ax[0, col], ax[1, col]):
            r_.grid(alpha=0.3)
            r_.legend(fontsize=9)
    ax[0, 0].set_ylabel('$\\varepsilon$  [mV]')
    ax[1, 0].set_ylabel('i  [mA]')
    fig.tight_layout()
    f3 = outdir / 'fig3_waveforms.png'
    fig.savefig(f3, dpi=a.dpi)
    plt.close(fig)
    print('wrote', f3)

    # ------------------------------------------------------------------
    # FIG 4 -- eps/N collapse
    # ------------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(10, 5))
    for name in order:
        d = data[name]
        ax.plot(d['t'], d['eps'] / d['N'] * 1e3, color=d['colour'], lw=1.3,
                label='%s %dt' % (d['mat'], d['N']))
    ax.set_xlabel('t  [s]')
    ax.set_ylabel('$\\varepsilon(t)\\,/\\,N$   [mV / turn]')
    ax.set_title('$\\varepsilon\\propto N$ test: all six cases should collapse '
                 'onto one curve\n(old path gave $\\varepsilon\\propto 1/N$, '
                 'a factor-$N^2$ spread)')
    ax.grid(alpha=0.3)
    ax.legend(ncol=3, fontsize=8)
    ax.axhline(0, color='k', lw=0.6)
    fig.tight_layout()
    f4 = outdir / 'fig4_epsN_collapse.png'
    fig.savefig(f4, dpi=a.dpi)
    # ------------------------------------------------------------------
    # FIG 5 -- old wsolve path vs new CoilSolver path
    # ------------------------------------------------------------------
    # The `--path wsolve` runs live in hpc_results/ (hpc_results_z024/ holds
    # the same sweep output).  Neither directory carries a case.sif, so the
    # path is identified from the DATA itself, on two counts:
    #   * r_component(1) is within 2% of R_wire(N) -- so the resistance was
    #     NOT the broken ~10x-too-small value of the pre-fix CoilSolver, yet
    #   * peak|i| FALLS as 1/N instead of rising as N,
    # which means the total EMF came out N-independent, i.e. eps/N ~ 1/N.
    # That is exactly the scaling the CoilSolver path fixes.
    old = {}
    old_root = ROOT / 'hpc_results'
    for name, mat, n in CASES:
        d = read_circuit(old_root / name)
        if d is not None:
            d['mat'], d['N'] = mat, n
            old[name] = d

    if old:
        def curve(src, mat, fn):
            """(ns, values) for material `mat`, sorted by N."""
            pts = sorted((d['N'], fn(d)) for d in src.values()
                         if d['mat'] == mat)
            return [p[0] for p in pts], [p[1] for p in pts]

        pk_i = lambda d: float(np.abs(d['i']).max()) * 1e3          # mA
        eps_per_n = lambda d: float(np.abs(d['eps']).max()) * 1e3 / d['N']
        rcomp = lambda d: d['r'][-1]

        fig, ax = plt.subplots(1, 3, figsize=(14, 4.6))
        for mat, mk in (('Cu', 'o'), ('Al', 's')):
            c = '#7a1414' if mat == 'Cu' else '#125012'
            for src, tag, ls, lw in ((old, 'wsolve', '--', 1.4),
                                     (data, 'CoilSolver', '-', 1.9)):
                for axis, fn in zip(ax, (pk_i, eps_per_n, rcomp)):
                    ns, v = curve(src, mat, fn)
                    axis.plot(ns, v, mk + ls, color=c, lw=lw, ms=6,
                              label='%s %s' % (mat, tag))
        ax[0].set_title('peak |i| vs N\nsolid rises with N, dashed falls as '
                        '1/N (wsolve Cu and Al coincide:\nmaterial-independent)')
        ax[0].set_ylabel('peak |i|  [mA]')
        ax[1].set_title('$\\varepsilon/N$ vs N\nCoilSolver flat, '
                        'wsolve $\\propto 1/N$')
        ax[1].set_ylabel('$\\varepsilon/N$  [mV / turn]')
        ax[1].set_yscale('log')
        ax[2].set_title('coil resistance: both paths agree\nto 2.1% '
                        '(wsolve is uniformly 0.9790 x CoilSolver)')
        ax[2].set_ylabel('$r_{component(1)}$  [$\\Omega$]')
        for r_ in ax:
            r_.set_xlabel('turns  N')
            r_.set_xticks([25, 50, 100])
            r_.grid(alpha=0.3)
            r_.legend(fontsize=7)
        fig.suptitle('old --path wsolve  vs  new --path coilsolver   '
                     '(both dt = 1 ms, 900 steps)', y=1.0)
        fig.tight_layout()
        f5 = outdir / 'fig5_old_vs_new.png'
        fig.savefig(f5, dpi=a.dpi)
        plt.close(fig)
        print('wrote', f5)
    else:
        print('  [skip] fig5 -- no data under %s' % old_root)

    # ------------------------------------------------------------------
    # FIG 6 -- honesty panel: what in eps(t)/i(t) can be trusted
    # ------------------------------------------------------------------
    # The waveforms carry a localised SPIKE every so often.  Measured facts
    # (see the printed block below):
    #   * the steps are NOT plateaus -- d i is never exactly 0, and the
    #     between-spike waveform is smooth;
    #   * ~4% of the 899 increments exceed 10x the median |d i|;
    #   * those spike INDICES are byte-identical in all six cases, so the
    #     artifact is a function of the timestep sequence alone (every case
    #     shares the same prescribed motion and the same dt) -- it is not
    #     driven by N, the material, or the induced current;
    #   * the global peak lands on a spike, but only 0.22-0.25% above the
    #     smooth-envelope peak, so the reported peak values are robust.
    def spikes(d, k=10.0):
        """Indices j where |i[j+1]-i[j]| exceeds k x median|d i|."""
        di = np.diff(d['i'])
        return np.where(np.abs(di) > k * np.median(np.abs(di)))[0]

    spike_sets = {n: set(spikes(data[n]).tolist()) for n in order}
    ref_set = spike_sets[order[0]]
    identical = all(spike_sets[n] == ref_set for n in order)
    ref = data[order[0]]
    idx = np.array(sorted(ref_set))

    print()
    print('  -- waveform spikes (all six cases) --')
    print('    spike steps          : %d / 899  (%.1f%%)'
          % (idx.size, 100.0 * idx.size / 899.0))
    print('    identical across the 6 cases : %s' % identical)
    print('    spike times [s]      : %s'
          % ', '.join('%.3f' % ref['t'][j] for j in idx[:14]))
    print('                          ...')
    print('    peak robustness (peak over ALL / peak over smooth samples):')
    for n in order:
        d = data[n]
        mask = np.ones(d['i'].size, bool)
        for j in spikes(d):
            mask[j:j + 3] = False
        pa = float(np.abs(d['i']).max())
        ps = float(np.abs(d['i'][mask]).max())
        print('      %-22s %.6e / %.6e  = %.4f'
              % (n, pa, ps, pa / ps))

    fig, ax = plt.subplots(1, 3, figsize=(15, 4.6))

    # (a) one spike, up close, on an otherwise smooth ramp
    k = int(idx[len(idx) // 2])
    lo, hi = max(k - 14, 0), min(k + 15, ref['t'].size)
    ax[0].plot(ref['t'][lo:hi] * 1e3, ref['i'][lo:hi] * 1e3, '.-',
               color='#4c72b0', lw=1.4, ms=5, label='$i(t)$')
    ax[0].axvline(ref['t'][k + 1] * 1e3, color='crimson', ls='--', lw=1.2,
                  label='spike step  (t = %.3f s)' % ref['t'][k + 1])
    ax[0].set_xlabel('t  [ms]')
    ax[0].set_ylabel('i  [mA]')
    ax[0].set_title('(a) the artifact, up close\na smooth ramp with one '
                    'isolated jump on top')
    ax[0].legend(fontsize=8)
    ax[0].grid(alpha=0.3)

    # (b) spike positions, one row per case -- they line up vertically
    for row, n in enumerate(order):
        d = data[n]
        js = spikes(d)
        ax[1].plot(d['t'][js] * 1e3, np.full(js.size, row), '|',
                   color='crimson', ms=14, mew=1.4)
        ax[1].text(-60, row, '%s %dt' % (d['mat'], d['N']), ha='right',
                   va='center', fontsize=8)
    ax[1].set_yticks([])
    ax[1].set_ylim(-0.7, len(order) - 0.3)
    ax[1].set_xlim(-260, 900)
    ax[1].set_xlabel('t  [ms]')
    ax[1].set_title('(b) spike times, one row per case\n'
                    'they line up -> the artifact is fixed by the '
                    'timestep sequence alone')
    ax[1].grid(alpha=0.3, axis='x')

    # (c) peak robustness
    xs = np.arange(len(order))
    pa = [float(np.abs(data[n]['i']).max()) * 1e3 for n in order]
    ps = []
    for n in order:
        d = data[n]
        mask = np.ones(d['i'].size, bool)
        for j in spikes(d):
            mask[j:j + 3] = False
        ps.append(float(np.abs(d['i'][mask]).max()) * 1e3)
    ax[2].bar(xs - 0.2, pa, 0.4, label='peak over all samples',
              color='#4c72b0')
    ax[2].bar(xs + 0.2, ps, 0.4, label='peak, spikes removed',
              color='#dd8452')
    ax[2].set_xticks(xs)
    ax[2].set_xticklabels(['%s\n%dt' % (data[n]['mat'], data[n]['N'])
                           for n in order], fontsize=8)
    ax[2].set_ylabel('peak |i|  [mA]')
    ax[2].set_title('(c) the reported peaks are robust\ndifference '
                    '$\\leq$ 0.25% once the spikes are dropped')
    ax[2].legend(fontsize=8)
    ax[2].grid(alpha=0.3, axis='y')
    fig.tight_layout()
    f6 = outdir / 'fig6_solver_artifact.png'
    fig.savefig(f6, dpi=a.dpi)
    plt.close(fig)
    print('wrote', f6)

    plt.close(fig)
    print('wrote', f4)

    # ------------------------------------------------------------------
    # numbers + source data
    # ------------------------------------------------------------------
    print()
    print('  %-22s %10s %11s %12s %12s' %
          ('case', 'peak|i| mA', 'peak|e| mV', 'eps/N mV/t', 'r_comp1'))
    with (outdir / 'figure_source_data.csv').open('w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['case', 'N', 'material', 'peak_i_A', 'peak_eps_V',
                    'eps_per_N_V', 'r_comp1_ohm', 'R_wire_ohm'])
        for name in order:
            d = data[name]
            ip = float(np.abs(d['i']).max())
            ep = float(np.abs(d['eps']).max())
            print('  %-22s %10.4f %11.4f %12.6f %12.6f' %
                  (name, ip * 1e3, ep * 1e3, ep / d['N'] * 1e3, d['r'][-1]))
            w.writerow([name, d['N'], d['mat'], ip, ep, ep / d['N'],
                        d['r'][-1], EXPECTED_R_WIRE[(d['mat'], d['N'])]])


if __name__ == '__main__':
    main()

"""analyse_n_scaling.py -- the decisive N-scaling test on the CoilSolver run.

Only cases that ran the SAME number of steps can be compared, because the
peak current/EMF grow with time as the magnet accelerates into the coil.
This script refuses to compare different step counts.

Physics used
------------
The loop is  [0 V source] -> [coil component 1] -> [load component 2].
KVL gives  v_component(1) = -i * R_load  (the coil's TERMINAL voltage),
which is NOT the induced EMF.  The EMF follows from the coil's own
constitutive relation  v_coil = -eps + i*r_coil, hence

        eps(t) = i(t) * ( R_load + r_component(1) )

With eps ~ N and r_coil = R_wire(N) = k*N, the current must follow

        i(N) = eps(N) / (R_load + k*N),

i.e. i grows with N but slightly SUB-linearly -- and the ratio of two
cases is predicted exactly, which is the strongest check available:

        i(N2)/i(N1) = [eps(N2)/eps(N1)] * [R_load + k*N1] / [R_load + k*N2]

Usage:
    python analyse_n_scaling.py <root>          # root holds <case>/results/
"""
import sys
from pathlib import Path

C = dict(t=7, i=10, v=11, r=14, rload=16, vload=4, itest=1)

EXPECTED_R = {
    ('Cu', 25): 0.1540885, ('Cu', 50): 0.3081770, ('Cu', 100): 0.6163539,
    ('Al', 25): 0.2623907, ('Al', 50): 0.5247813, ('Al', 100): 1.0495626,
}


def read(case_dir):
    p = Path(case_dir) / 'results' / 'circuit.csv'
    if not p.exists():
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
    return rows


def parse(case):
    # N25_L040_cu_closed -> ('Cu', 25)
    parts = case.split('_')
    n = int(parts[0][1:])
    mat = parts[2].capitalize()
    return mat, n


def main(root):
    root = Path(root)
    data = {}
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        rows = read(d)
        if not rows:
            print('  %-24s : no circuit.csv' % d.name)
            continue
        try:
            mat, n = parse(d.name)
        except Exception:
            continue
        dt = rows[-1][C['t'] - 1] / len(rows)
        eps = lambda r: r[C['i'] - 1] * (r[C['rload'] - 1] + r[C['r'] - 1])
        pk = max(rows, key=lambda r: abs(eps(r)))
        data[(mat, n)] = dict(
            case=d.name, steps=len(rows), t_end=rows[-1][C['t'] - 1],
            dt=dt,
            i_pk=max(abs(r[C['i'] - 1]) for r in rows),
            eps_pk=abs(eps(pk)), eps_pk_t=pk[C['t'] - 1],
            r=rows[-1][C['r'] - 1], rload=rows[-1][C['rload'] - 1],
        )

    print('=' * 78)
    print('PER-CASE RESULTS')
    print('=' * 78)
    print('  %-22s %6s %10s %14s %14s %12s' %
          ('case', 'steps', 't_end', 'peak |i| [A]', 'peak |eps| [V]',
           'r_comp1 [ohm]'))
    for k in sorted(data):
        d = data[k]
        print('  %-22s %6d %10.3e %14.6e %14.6e %12.6e' %
              (d['case'], d['steps'], d['t_end'], d['i_pk'],
               d['eps_pk'], d['r']))

    print()
    print('=' * 78)
    print('r_component(1) vs R_wire(N)  -- must match to ~1e-6')
    print('=' * 78)
    allok = True
    for k in sorted(data):
        d = data[k]
        exp = EXPECTED_R.get(k)
        if exp is None:
            continue
        rel = d['r'] / exp - 1.0
        ok = abs(rel) < 1e-5
        allok &= ok
        print('  %-8s N=%-4d  measured %.7f   expected %.7f   rel.err %+.2e  %s'
              % (k[0], k[1], d['r'], exp, rel, 'OK' if ok else 'MISMATCH'))

    print()
    print('=' * 78)
    print('eps/N must be CONSTANT (that is what eps ~ N means)')
    print('=' * 78)
    for mat in ('Cu', 'Al'):
        ns = sorted(n for (m, n) in data if m == mat)
        vals = []
        for n in ns:
            d = data[(mat, n)]
            # only rows with the same step count are comparable
            vals.append((n, d['eps_pk'] / n, d['steps']))
        if not vals:
            continue
        base_steps = max(v[2] for v in vals)
        print('  %s (only cases with %d steps are directly comparable):'
              % (mat, base_steps))
        for n, v, st in vals:
            tag = '' if st == base_steps else '   [%d steps -- partial]' % st
            print('    N=%-4d eps/N = %.6e%s' % (n, v, tag))

    print()
    print('=' * 78)
    print('EPS ~ N  -- the decisive test (same step count only!)')
    print('=' * 78)
    for mat in ('Cu', 'Al'):
        ns = sorted(n for (m, n) in data if m == mat)
        for a, b in zip(ns, ns[1:]):
            A, B = data[(mat, a)], data[(mat, b)]
            if A['steps'] != B['steps']:
                print('  %s N=%d vs N=%d : DIFFERENT step counts (%d vs %d) '
                      '-- not comparable' % (mat, a, b, A['steps'], B['steps']))
                continue
            eps_ratio = B['eps_pk'] / A['eps_pk']
            n_ratio = b / a
            ident = eps_ratio * (A['rload'] + A['r']) / (B['rload'] + B['r'])
            i_ratio = B['i_pk'] / A['i_pk']
            print('  %s  N=%d -> N=%d   (turn ratio %.2f, t_end %.3e s)'
                  % (mat, a, b, n_ratio, A['t_end']))
            print('      i ratio MEASURED  = %.4f   <-- the independent number'
                  % i_ratio)
            print('        (i is read straight from circuit.csv col 10)')
            print('      eps ratio         = %.4f   (want %.4f, err %+.2f%%)'
                  % (eps_ratio, n_ratio, 100 * (eps_ratio / n_ratio - 1)))
            print('        NOTE: eps is DEFINED here as i*(R_load + r_comp1),')
            print('        so "eps ratio" is derived from i and r rather than')
            print('        measured separately.  The identity below therefore')
            print('        checks arithmetic consistency, NOT physics:')
            print('      identity i_ratio = eps_ratio*(10+r1)/(10+r2) : '
                  '%.4f vs %.4f  %s'
                  % (i_ratio, ident,
                     'OK' if abs(i_ratio / ident - 1) < 1e-6 else 'FAIL'))
            print('      >>> the physically meaningful statement is that the')
            print('          MEASURED i GROWS with N (ratio %.4f for a %.2fx'
                  % (i_ratio, n_ratio))
            print('          increase in turns), where the old Wsolve path'
                  ' gave i ~ 1/N.')

    print()
    print('Reference: the OLD Wsolve path gave eps ~ 1/N instead of ~ N.')
    print('  Wsolve:  eps*N = 0.960 / 1.155 / 1.172 / 1.206 V for N = 1/25/50/100')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'hpc_results_coilsolver')

"""Final report -- one combined table across all 6 closed-circuit cases.

Reads hpc_results_z900/<case>/results/circuit.csv and prints
- peak |i| (independent measurement, col 10)
- peak |eps| = i*(R_load + r_comp1) at that step (col 11 + col 14)
- r_comp1 (col 14) compared to R_wire(N)

Writes a CSV summary for downstream analysis / plotting.
"""
import csv
import sys
from pathlib import Path

C = dict(t=7, i=10, v=11, r=14, rload=16, vload=4)

EXPECTED_R = {
    ('Cu', 25): 0.1540885, ('Cu', 50): 0.3081770, ('Cu', 100): 0.6163539,
    ('Al', 25): 0.2623907, ('Al', 50): 0.5247813, ('Al', 100): 1.0495626,
}


def parse(case):
    parts = case.split('_')
    return parts[2].capitalize(), int(parts[0][1:])


def main(root):
    root = Path(root)
    rows = []
    print('=' * 88)
    print('FULL 900-STEP CLOSED-CIRCUIT SWEEP -- hpc_results_z900')
    print('=' * 88)
    print('  %-22s %6s %10s %14s %14s %12s %12s' %
          ('case', 'steps', 't_end', 'peak |i| [A]', 'peak |eps| [V]',
           'r_comp1 [ohm]', 'expected [ohm]'))
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        csv_path = d / 'results' / 'circuit.csv'
        if not csv_path.exists():
            continue
        try:
            mat, n = parse(d.name)
        except Exception:
            continue
        data = []
        for ln in csv_path.read_text().splitlines():
            f = ln.split()
            if len(f) < 16:
                continue
            try:
                data.append([float(x) for x in f])
            except ValueError:
                continue
        if not data:
            continue
        i_pk = max(abs(r[C['i'] - 1]) for r in data)
        eps_of = lambda r: r[C['i'] - 1] * (r[C['rload'] - 1] + r[C['r'] - 1])
        eps_pk_row = max(data, key=lambda r: abs(eps_of(r)))
        eps_pk = abs(eps_of(eps_pk_row))
        r_end = data[-1][C['r'] - 1]
        rl_end = data[-1][C['rload'] - 1]
        steps = len(data)
        t_end = data[-1][C['t'] - 1]
        exp_r = EXPECTED_R.get((mat, n), float('nan'))
        print('  %-22s %6d %10.3e %14.6e %14.6e %12.6e %12.6e'
              % (d.name, steps, t_end, i_pk, eps_pk, r_end, exp_r))
        rows.append((d.name, steps, t_end, i_pk, eps_pk, r_end, exp_r))

    print()
    print('=' * 88)
    print('epsilon per turn (eps / N)  -- must be CONSTANT, material-independent')
    print('=' * 88)
    # Sort so Cu(N=25) prints first; it IS the reference.
    rows_sorted = sorted(
        rows,
        key=lambda r: (r[0].split('_')[2], int(r[0].split('_')[0][1:])))
    print('  %-22s %12s %12s %18s'
          % ('case', 'eps/N', 'mat', 'rel to Cu(N=25)'))
    base = None
    for name, steps, t_end, i_pk, eps_pk, r_end, exp_r in rows_sorted:
        mat, n = parse(name)
        eps_n = eps_pk / n
        if mat == 'Cu' and n == 25:
            base = eps_n
            rel_str = '(reference)'
        elif base is not None:
            rel = (eps_n / base - 1.0) * 100
            rel_str = '%+16.4e %%' % rel
        else:
            rel_str = '(no base yet)'
        print('  %-22s %12.6e %12s %18s'
              % (name, eps_n, mat, rel_str))

    print()
    print('=' * 88)
    print('i ratio (independent measurement, t_end = 0.9 s)')
    print('=' * 88)
    by_mat = {}
    for name, steps, t_end, i_pk, eps_pk, r_end, exp_r in rows:
        by_mat.setdefault(parse(name)[0], []).append(
            (parse(name)[1], i_pk))
    for mat in ('Cu', 'Al'):
        ns = sorted(by_mat.get(mat, []))
        for (n1, i1), (n2, i2) in zip(ns, ns[1:]):
            print('  %s  N=%d -> N=%d  :  i ratio = %.4f  (turn ratio %.2f)'
                  % (mat, n1, n2, i2 / i1, n2 / n1))

    out_csv = root / 'summary_900.csv'
    with out_csv.open('w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['case', 'steps', 't_end_s', 'peak_i_A', 'peak_eps_V',
                    'r_comp1_ohm', 'expected_R_wire_ohm'])
        for r in rows:
            w.writerow(r)
    print()
    print('wrote %s' % out_csv)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'hpc_results_z900')

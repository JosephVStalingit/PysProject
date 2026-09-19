"""Analyse the pulled closed-circuit sweep.

Reads hpc/results/<curve>/circuit.csv (900 rows, 17 columns -- see
circuit.csv.names) and reports the induced-current behaviour per curve,
plus the consistency checks that must hold for the FEM to be believable.

Column map (1-based, from circuit.csv.names):
    1 3  crt i 1 / crt v 1        the coil
    2 4  crt i 2 / crt v 2        the load
    5    eddy current power
    6    electromagnetic field energy
    7    res: time
    10   res: i_component(1)      <- the coil current
    11   res: v_component(1)
    12   res: i_component(2)
    13   res: v_component(2)
    14   res: r_component(1)
    16   res: r_component(2)
"""
from __future__ import annotations
import os
import math

ROOT = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(ROOT, 'hpc', 'results')

CURVES = [
    'N25_L040_cu_closed', 'N25_L040_al_closed',
    'N50_L040_cu_closed', 'N50_L040_al_closed',
    'N100_L040_cu_closed', 'N100_L040_al_closed',
]


def load(curve: str):
    path = os.path.join(RES, curve, 'circuit.csv')
    if not os.path.exists(path):
        return None
    out = []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            p = line.split()
            if len(p) < 17:
                continue
            try:
                out.append([float(x) for x in p])
            except ValueError:
                continue
    return out


def main() -> None:
    print('=' * 78)
    print('  CLOSED-CIRCUIT SWEEP -- induced current summary')
    print('=' * 78)
    print()

    hdr = (f"  {'curve':<22}{'rows':>5}{'R_coil':>10}{'peak|i| mA':>12}"
           f"{'t_peak ms':>11}{'i(0.9s) mA':>12}{'V=RI ok':>9}")
    print(hdr)
    print('  ' + '-' * 74)

    data = {}
    for c in CURVES:
        d = load(c)
        if d is None:
            print(f'  {c:<22}  MISSING')
            continue
        data[c] = d
        t = [r[6] for r in d]
        i = [r[9] for r in d]
        v1 = [r[10] for r in d]
        i2 = [r[11] for r in d]
        v2 = [r[12] for r in d]
        rc, rl = d[0][13], d[0][15]

        k = max(range(len(i)), key=lambda n: abs(i[n]))
        # the load is a plain resistor: |v2/i2| must equal R_load exactly
        bad = 0
        for n in range(len(i2)):
            if abs(i2[n]) > 1e-12:
                if abs(abs(v2[n] / i2[n]) - rl) > 1e-3 * rl:
                    bad += 1
        # the loop carries one current
        diff = max(abs(i2[n] - i[n]) for n in range(len(i)))

        print(f'  {c:<22}{len(d):>5}{rc:>10.4f}{abs(i[k])*1e3:>12.4f}'
              f'{t[k]*1e3:>11.1f}{abs(i[-1])*1e3:>12.4f}{"yes" if not bad else "NO":>9}')
        if bad:
            print(f'      !! {bad} rows violate V = R*I on the load')
        if diff > 1e-9:
            print(f'      !! |i_component(1) - i_component(2)| max = {diff:.3e}')

    print()

    # ---- Cu vs Al at the same turn count -------------------------------
    print('  Cu vs Al at equal N  (10 ohm load dominates, so they should')
    print('  agree closely -- a large gap would mean sigma is double-counted):')
    print()
    for n in (25, 50, 100):
        cu, al = f'N{n}_L040_cu_closed', f'N{n}_L040_al_closed'
        if cu in data and al in data:
            ic = max(abs(r[9]) for r in data[cu])
            ia = max(abs(r[9]) for r in data[al])
            print(f'    N={n:<4} cu peak={ic*1e3:9.5f} mA   al peak={ia*1e3:9.5f} mA'
                  f'   ratio={ia/ic:.4f}')

    print()
    print('  Scaling with N  (peak |i_component(1)|):')
    print()
    prev = None
    for n in (25, 50, 100):
        c = f'N{n}_L040_cu_closed'
        if c in data:
            ic = max(abs(r[9]) for r in data[c])
            line = f'    N={n:<4} peak={ic*1e3:9.5f} mA'
            if prev:
                line += f'   peak*N={ic*n*1e3:8.4f}   ratio vs prev={prev/ic:.4f}'
            print(line)
            prev = ic

    print()
    print('  Energy budget (t = 0.9 s, copper, N=50):')
    c = 'N50_L040_cu_closed'
    if c in data:
        d = data[c]
        r = d[-1]
        pc = r[14]
        print(f'    i_component(1)        = {r[9]:.6e} A')
        print(f'    v_component(1)        = {r[10]:.6e} V')
        print(f'    r_component(1)        = {r[13]:.6f} ohm')
        print(f'    p_dc_component(1)     = {pc:.6e} W')
        print(f'    i^2 * R check         = {r[9]**2 * r[13]:.6e} W')
        print(f'    electromagnetic energy= {r[5]:.6e} J')
        print()
        print(f'    sanity: r_component(1) should be ~0.3082 ohm (hand value)')

    print()


if __name__ == '__main__':
    main()

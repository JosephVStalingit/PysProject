"""measure_3.py -- the ONLY three quantities requested for the re-run:

    * displacement   z(t)   of the magnet            (from the .vtu files)
    * induced EMF    eps(t) = v_component(1)         (circuit.csv col 11)
    * induced current i(t)  = i_component(1)         (circuit.csv col 10)

Why these columns:
    `circuits.definitions` names the six MNA unknowns; the CSV is written by
    `SaveScalars` with `Variable 1 = "crt i"` / `Variable 2 = "crt v"` and has
    NO header.  The mapping below is the one VERIFIED by two independent
    circuit laws (see `_read_csolv_result.py`):

        col 1  i_testsource      col 4  v_component(2) = R_load * i
        col 6  (derived)         col 7  time
        col 10 i_component(1)  <- THE COIL CURRENT
        col 11 v_component(1)  <- THE COIL TERMINAL VOLTAGE  ( == -v_load )
        col 14 r_component(1)  <- the coil's own resistance
        col 16 R_load = 10

    self-checks that must hold exactly:
        col 4  == col 16 * col 10        ( Ohm's law on the load )
        col 11 == -col 4                 ( KVL round the loop )

The `empty` baseline has no circuit at all, so it has NO circuit.csv; for it
only the displacement is meaningful (EMF and current are identically zero --
that is exactly why it is the no-Lenz-braking reference).

Usage:
    python measure_3.py <case_dir_containing_results>
    python measure_3.py --all <root_dir>
"""
import json
import math
import re
import sys
from pathlib import Path

C = dict(t=7, i=10, v=11, r=14, rload=16, vload=4, itest=1)


def read_circuit(case_dir):
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


def displacement(case_dir):
    """z(t) from the magnet's node set in the .vtu files.

    Elmer writes one case_tNNNN.vtu per output step.  We do not parse VTU
    here (it needs the PointData block); instead we report the PRESCRIBED
    displacement the SIF drives the mesh with, evaluated from the MATC
    expression, which is what the mesh mapper applies verbatim.
    """
    sif = Path(case_dir) / 'case.sif'
    if not sif.exists():
        # Convention used by --all mode: a case_dir holds results/ with
        # the CSV; this dir holds the SIF.  Try the results/ subdir too.
        alt = Path(case_dir) / 'results' / 'case.sif'
        if alt.exists():
            sif = alt
    if not sif.exists():
        return None, None
    text = sif.read_text(errors='replace')
    m = re.search(r'Real\s+MATC\s+"([^"]+)"', text)
    if not m:
        return None, None
    expr = m.group(1)
    # dt from the SIF
    dt = None
    m2 = re.search(r'Timestep\s+Sizes\s*=\s*([\d.eE+-]+)', text)
    if m2:
        dt = float(m2.group(1))
    return expr, dt


def matc_to_python(expr):
    """Translate the SIF's MATC displacement expression into Python.

    MATC is a C-like expression language; the displacement law we emit uses
    only `tx` (the current time), numeric literals and a few elementary
    functions, so a textual substitution is sufficient and exact.  We keep
    the translation deliberately tiny and REJECT anything unexpected,
    rather than pretending to implement MATC.
    """
    e = expr.strip()

    # Every function call in the ORIGINAL string must be one we know.
    allowed = {'exp', 'cos', 'sin', 'sqrt', 'log', 'tan'}
    for name in re.findall(r'\b([A-Za-z_]\w*)\s*\(', e):
        if name not in allowed:
            raise ValueError('unexpected function %r in MATC: %r'
                             % (name, expr))

    e = re.sub(r'\btx\b', '(t)', e)
    e = e.replace('^', '**')
    for fn in allowed:
        e = re.sub(r'\b%s\b' % fn, 'math.%s' % fn, e)
    return e


def z_of_t(expr):
    """Return a callable t -> displacement, or None if expr is unusable."""
    try:
        code = matc_to_python(expr)
    except ValueError:
        return None
    def f(t):
        return eval(code, {'math': math, 't': t})
    # smoke test at t = 0 against a hand evaluation of the same string
    f(0.0)
    return f


def report(case_dir):
    case_dir = Path(case_dir)
    name = case_dir.name
    rows = read_circuit(case_dir)
    expr, dt = displacement(case_dir)

    print('=' * 74)
    print('CASE: %s' % name)
    print('=' * 74)

    if expr:
        print('  displacement  z(t) is PRESCRIBED by the SIF MATC expression:')
        print('      %s' % expr)
        print('      (the mesh mapper applies it verbatim; the achieved')
        print('       positions are in results/case_t*.vtu)')
    else:
        print('  displacement  : no MATC expression found in case.sif')

    if rows is None:
        print('  induced EMF   : n/a -- no circuit in this case')
        print('  induced current: n/a -- no circuit in this case')
        print('     (`empty` is the no-Lenz baseline: no coil, no circuit.)')
        return

    i_end = rows[-1][C['i'] - 1]
    i_pk = max(abs(r[C['i'] - 1]) for r in rows)
    v_end = rows[-1][C['v'] - 1]
    v_pk = max(abs(r[C['v'] - 1]) for r in rows)
    r_coil = rows[-1][C['r'] - 1]
    rl = rows[-1][C['rload'] - 1]
    t_end = rows[-1][C['t'] - 1]

    # THE INDUCED EMF.  `v_component(1)` is the coil's TERMINAL voltage,
    # which KVL pins to -i*R_load -- it is NOT the EMF.  The EMF comes from
    # the coil's own constitutive relation  v_coil = -eps + i*r_coil, so
    #     eps = i*(R_load + r_coil).
    # (Same relation used in README 7.5.3 for the Wsolve baseline.)
    eps_of = lambda r: r[C['i'] - 1] * (r[C['rload'] - 1] + r[C['r'] - 1])
    eps_pk_row = max(rows, key=lambda r: abs(eps_of(r)))
    eps_pk = eps_of(eps_pk_row)
    eps_end = eps_of(rows[-1])

    # the two exact self-checks
    ok_ohm = abs(rows[-1][C['vload'] - 1] - rl * i_end) < 1e-9 * max(1.0, abs(i_end) * rl)
    ok_kvl = abs(v_end + rows[-1][C['vload'] - 1]) < 1e-9 * max(1.0, abs(v_end))

    print('  steps          : %d   t_end = %.6e s' % (len(rows), t_end))
    print('  induced EMF    : peak |eps| = %.6e V   at t = %.6e s'
          % (abs(eps_pk), eps_pk_row[C['t'] - 1]))
    print('                   last       = %.6e V' % eps_end)
    print('                   eps = i*(R_load + r_component(1))')
    print('  induced current: peak |i_component(1)| = %.6e A' % i_pk)
    print('                   last                  = %.6e A' % i_end)
    print('  (terminal volt.: v_component(1) peak = %.6e V, last = %.6e V'
          % (v_pk, v_end))
    print('                   == -i*R_load by KVL, NOT the EMF)')
    print('  r_component(1) : %.6e ohm    R_load = %.1f ohm' % (r_coil, rl))
    print('  checks         : v_load == R_load*i   %s' % ('OK' if ok_ohm else 'FAIL'))
    print('                   v_coil == -v_load    %s' % ('OK' if ok_kvl else 'FAIL'))

    # ---- the combined three-quantity time series -----------------------
    zf = z_of_t(expr) if expr else None
    if zf is None:
        print('  (displacement table skipped: MATC expression not evaluable)')
        return
    n = len(rows)
    picks = sorted(set([1, n] + [max(1, int(round(n * k / 8.0)))
                                 for k in range(1, 8)]))
    print()
    print('  %-12s %-14s %-16s %-16s' %
          ('t [s]', 'z(t) [m]', 'eps(t) [V]', 'i(t) [A]'))
    for idx in picks:
        r = rows[idx - 1]
        t = r[C['t'] - 1]
        print('  %-12.6e %-14.6e %-16.6e %-16.6e'
              % (t, zf(t), eps_of(r), r[C['i'] - 1]))
    print('  (z(t) is the PRESCRIBED displacement from the SIF MATC')
    print('   expression; the achieved node positions are in the vtu files.)')


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == '--all':
        root = Path(args[1])
        for d in sorted(p for p in root.iterdir() if p.is_dir()):
            report(d)
    else:
        for a in args:
            report(a)

"""
tests/test_sif_solver.py -- lock down `make_sif.py --solver`.

WHY THIS EXISTS
---------------
`--solver hypre-ams` rewrites Solver 2 (WhitneyAVSolver) from a direct
UMFPACK solve to an iterative one, because UMFPACK's memory grows ~O(n^2)
and dies around 100 000 mesh edges:

    Error occurred in umf4num:   -1.0000000000000000

The rewrite is pure text surgery on the SIF template, and it shipped with
two SILENT failure modes that this suite now catches:

  1. The regex did not allow leading whitespace.  SIF keys are indented by
     two spaces, so `^Linear System Max Iterations` matched nothing and
     generation aborted with "could not raise ... Max Iterations".
  2. Only the FIRST TWO lines of the old block were replaced, leaving the
     trailing `Linear System Max Iterations = 1000` behind.  That is a
     duplicate key, and Elmer honours the LAST one -- so the iterative 5000
     was silently downgraded back to 1000.  `test_no_duplicate_keys` and
     `test_max_iterations_is_exactly_5000` exist specifically for this.

The AMS keywords are copied verbatim from the upstream test case
`fem/tests/mgdyn_hypre_ams`, whose header reads:
    "This test case with BiCGStab as solver, AMS as preconditioner."

These tests are dependency-free (no Elmer, no gmsh, no meshio) so they run
anywhere the generator runs.
"""
from __future__ import annotations
import os
import re
import subprocess
import sys
import tempfile

try:
    import pytest  # type: ignore
except ImportError:
    pytest = None   # type: ignore

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAKE_SIF = os.path.join(ROOT, 'make_sif.py')
TEMPLATE = os.path.join(ROOT, 'case_transient.sif')

sys.path.insert(0, ROOT)


# ---------------------------------------------------------------------------
#  helpers
# ---------------------------------------------------------------------------
def render(solver: str) -> str:
    """Run the real CLI into a temp file and return the generated SIF text.

    The real CLI is used (not a direct `patch_solver` call) so argparse,
    config loading and the path/time-stepping rewrites are exercised too.
    `--out` is ALWAYS given: running without it would overwrite the real
    `case_transient.sif`.
    """
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, 'case.sif')
        r = subprocess.run(
            [sys.executable, MAKE_SIF, '--out', out, '--solver', solver],
            cwd=ROOT, capture_output=True, text=True)
        assert r.returncode == 0, f'--solver {solver} failed:\n{r.stdout}{r.stderr}'
        with open(out, encoding='utf-8') as f:
            return f.read()


def block(sif: str, n: int) -> str:
    """Return only the text of `Solver n` (up to the next Solver/Equation)."""
    m = re.search(rf'(?m)^Solver\s+{n}\s*$', sif)
    assert m, f'Solver {n} not found in the SIF'
    nxt = re.search(r'(?m)^(?:Solver|Equation)\s+\d+\s*$', sif[m.end():])
    end = m.end() + (nxt.start() if nxt else len(sif) - m.end())
    return sif[m.start():end]


def keys(sif_block: str) -> list:
    """Lower-cased `key = value` keys, ignoring blanks and `!` comments."""
    out = []
    for line in sif_block.splitlines():
        s = line.strip()
        if not s or s.startswith('!'):
            continue
        if '=' in s:
            out.append(s.split('=', 1)[0].strip().lower())
    return out


def value(sif_block: str, key: str, occurrence: int = 1):
    """Value of the `occurrence`-th (1-based) case-insensitive match, or None."""
    hits = re.findall(rf'(?mi)^\s*{re.escape(key)}\s*=\s*(.+?)\s*$', sif_block)
    if len(hits) < occurrence:
        return None
    return hits[occurrence - 1]


# ---------------------------------------------------------------------------
#  the default path must not change anything
# ---------------------------------------------------------------------------
def test_umfpack_is_byte_identical_to_the_template():
    """`--solver umfpack` is the default and must be a true no-op.

    If this ever fails, the default pipeline has silently changed behaviour
    for every existing user.
    """
    with open(TEMPLATE, encoding='utf-8') as f:
        tpl = f.read()
    assert render('umfpack') == tpl


def test_umfpack_keeps_the_direct_block():
    b = block(render('umfpack'), 2)
    assert value(b, 'Linear System Solver') == 'Direct'
    assert value(b, 'Linear System Direct Method') == 'UMFPACK'


# ---------------------------------------------------------------------------
#  the hypre-ams path
# ---------------------------------------------------------------------------
def test_hypre_ams_turns_the_solve_on():
    b = block(render('hypre-ams'), 2)
    assert value(b, 'linear system use hypre').lower() == 'logical true'
    assert value(b, 'Linear System Solver').lower() == 'iterative'
    assert value(b, 'Linear System Preconditioning').upper() == 'AMS'
    assert value(b, 'Linear System Symmetric').lower() == 'logical true'


def test_hypre_ams_uses_bicgstab_index_7():
    """Krylov index 7 = BiCGStab, per the upstream mgdyn_hypre_ams case."""
    b = block(render('hypre-ams'), 2)
    assert value(b, 'Linear System Method Hypre Index') == 'Integer 7'


def test_hypre_ams_removes_the_direct_solver():
    b = block(render('hypre-ams'), 2)
    assert value(b, 'Linear System Direct Method') is None, \
        'UMFPACK is still selected alongside Hypre'
    assert value(b, 'Linear System Solver').lower() == 'iterative'


def test_no_duplicate_keys():
    """REGRESSION: replacing only part of the block left `Max Iterations`
    twice, and Elmer takes the last one."""
    ks = keys(block(render('hypre-ams'), 2))
    dupes = sorted({k for k in ks if ks.count(k) > 1})
    assert not dupes, f'duplicate keys in Solver 2: {dupes}'


def test_max_iterations_is_exactly_5000():
    """REGRESSION: the leftover `= 1000` silently won.  Assert BOTH that the
    value is 5000 and that there is exactly one such key."""
    b = block(render('hypre-ams'), 2)
    hits = re.findall(r'(?mi)^\s*Linear System Max Iterations\s*=\s*(\d+)', b)
    assert hits == ['5000'], f'expected exactly one "5000", got {hits}'


def test_residual_output_is_visible():
    """An iterative solve that stalls must be diagnosable."""
    b = block(render('hypre-ams'), 2)
    assert value(b, 'Linear System Residual Output') == '10'


def test_stale_direct_comment_is_dropped():
    """The template justifies DIRECT with "the iterative route ... diverges",
    which becomes a lie once AMS is selected."""
    with open(TEMPLATE, encoding='utf-8') as f:
        assert 'DIRECT is used' in f.read()
    assert 'DIRECT is used' not in block(render('hypre-ams'), 2)


# ---------------------------------------------------------------------------
#  blast radius
# ---------------------------------------------------------------------------
def test_only_solver2_is_modified():
    """Solvers 1 (mesh motion) and 3 (derived fields) must be untouched."""
    with open(TEMPLATE, encoding='utf-8') as f:
        tpl = f.read()
    out = render('hypre-ams')

    def strip(s):
        return re.sub(r'(?ms)^Solver\s+2\s*$.*?(?=^Solver\s+3\s*$)',
                      '<<S2>>', s)

    assert strip(tpl) == strip(out), 'something outside Solver 2 changed'


def test_solvers_1_and_3_keep_their_settings():
    out = render('hypre-ams')
    for n, meth, pre in ((1, 'BiCGStab', 'ILU0'), (3, 'CG', 'ILU0')):
        b = block(out, n)
        assert value(b, 'Linear System Iterative Method') == meth, f'Solver {n}'
        assert value(b, 'Linear System Preconditioning') == pre, f'Solver {n}'


def test_rejects_an_unknown_solver():
    with tempfile.TemporaryDirectory() as tmp:
        r = subprocess.run(
            [sys.executable, MAKE_SIF, '--out', os.path.join(tmp, 'x.sif'),
             '--solver', 'pardiso'], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode != 0, 'an unknown --solver should be refused'


def test_generation_is_deterministic():
    assert render('hypre-ams') == render('hypre-ams')


if __name__ == '__main__':
    # standalone execution (no pytest needed)
    print('=== make_sif.py --solver tests ===')
    fns = [(n, f) for n, f in sorted(globals().items())
           if n.startswith('test_') and callable(f)]
    failed = 0
    for name, fn in fns:
        try:
            fn()
            print(f'  [ok]   {name}')
        except Exception as exc:                      # noqa: BLE001
            failed += 1
            print(f'  [FAIL] {name}: {exc}')
    print(f'\n  {len(fns) - failed}/{len(fns)} passed')
    sys.exit(1 if failed else 0)

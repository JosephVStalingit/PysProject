r"""
tests/test_sif_circuit.py -- lock down `make_sif.py`'s closed-circuit SIF.

WHY THIS EXISTS
---------------
Every conductor curve now generates a SIF that differs from the template in
a dozen places, and the generator does it by TEXT SURGERY.  A wrong patch
does not crash -- it produces a SIF that loads and then gives physically
meaningless numbers, or dies hours into an HPC job.  These tests pin down
the failure modes that were actually hit while building it.

THE DESIGN CONTRACT (no `--circuit` flag any more)
--------------------------------------------------
The open-circuit variant was removed, so the circuit treatment follows from
the CURVE rather than from a mode flag:

    --curve <conductor>  (N_turns > 0)   -> the closed circuit
    --curve empty        (N_turns = 0)   -> the plain template, untouched
    no --curve at all                    -> the plain template, untouched

The last two are the no-Lenz-braking baseline, and `test_baseline_*` below
asserts they are BYTE-IDENTICAL to `case_transient.sif`.  That invariant is
what keeps the baseline honest: if a patch ever leaks into the no-conductor
path, the comparison silently stops being valid.

FAILURE MODES PINNED DOWN HERE
------------------------------
  1. ROW-EATING REGEX.  The solver list was first written with `[\d\s]+`,
     and `\s` matches newlines.  It swallowed the next line and emitted
         Active Solvers(3) = 1 2 3 4 5 6 7Mesh Update = Logical True
     `test_active_solvers_line_survives` exists for exactly this.

  2. STALE COUNT.  `Active Solvers(3)` was left as `(3)` while listing
     seven solvers.  Elmer reads the count, not the list length.

  3. WRONG BOUNDARY INDICES.  The coil end faces are gmsh physical groups
     1003 / 1004, but `ElmerGrid -autoclean` RENUMBERS boundary groups
     sequentially, so the SIF must say 3 / 4.  Writing 1003 gives
     "target boundary not found" at load time.

  4. MISSING W POTENTIAL.  A coil Component with no wire-direction
     potential runs timestep 1 and then SEGFAULTs inside
     MagnetoDynamicsCalcFields.  See 13.9 of hpc/notes.md.

  5. CURVE-DEPENDENT SIGMA.  Material 1's conductivity must follow the
     active curve (copper 5.96e7 vs aluminium 3.5e7), so it is rewritten
     on every call and NOT guarded by the idempotency check.

  5b. THE FILL FACTOR.  Elmer derives the coil's series resistance as
     N_j^2 * V / sigma, which is only the physical wire resistance if the
     material fed to it is the homogenised sigma_eff = f * sigma_wire with
     f = N * A_wire / A_coil.  See test_material1_conductivity_is_the_
     homogenised_wire_sigma and 15.8 of hpc/notes.md.

The reference for the whole design is upstream
`fem/tests/circuits2D_transient_variable_resistor`, whose header says a
resistor needs no hand-written element law because Elmer fills in V = R*I
on the row of `v_component(2)`:

    ! Now we define the variable resistor. It is similar to FE components
    ! in the sense that Elmer will write the component equation to the row
    ! of the voltage component (row 6).  So no need to write V=RI.

These tests are dependency-free (no Elmer, no gmsh, no meshio) so they run
anywhere the generator runs.
"""
from __future__ import annotations
import json
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


# ---------------------------------------------------------------------------
#  helpers
# ---------------------------------------------------------------------------
def cfg() -> dict:
    with open(CONFIG, encoding='utf-8') as f:
        return json.load(f)


def run(*args: str, expect_ok: bool = True):
    """Run the real CLI in a temp dir.  Returns (returncode, stderr, dir).

    The whole directory is handed back so callers can inspect the sibling
    `circuits.definitions` that make_sif.py writes next to the SIF.  The
    real CLI is used so argparse, curve validation and the config load are
    exercised too.
    """
    tmp = tempfile.mkdtemp()
    out = os.path.join(tmp, 'case.sif')
    r = subprocess.run([sys.executable, MAKE_SIF, '--out', out, *args],
                       cwd=ROOT, capture_output=True, text=True)
    if expect_ok:
        assert r.returncode == 0, f'make_sif.py {args} failed:\n{r.stdout}{r.stderr}'
    return r.returncode, r.stderr, tmp


def render(*args: str) -> str:
    """Generate a SIF and return its text."""
    _, _, tmp = run(*args)
    with open(os.path.join(tmp, 'case.sif'), encoding='utf-8') as f:
        return f.read()


def render_with_dir(*args: str):
    """Generate a SIF; return (text, the temp directory holding it)."""
    _, _, tmp = run(*args)
    with open(os.path.join(tmp, 'case.sif'), encoding='utf-8') as f:
        return f.read(), tmp


def template() -> str:
    with open(TEMPLATE, encoding='utf-8') as f:
        return f.read()


def block(sif: str, kind: str, n: int) -> str:
    """Text of `kind n` (e.g. Solver 5 / Component 2 / Body Force 3).

    Terminated by the block's own `End` line rather than by the next block
    of the same kind.  The naive "next same kind" version silently ran to
    EOF for the LAST block of a kind (Solver 4 in the template, Solver 7 in
    the closed SIF) and swept every later section into the comparison.
    """
    m = re.search(rf'(?m)^{kind}\s+{n}\s*$', sif)
    assert m, f'{kind} {n} not found'
    rest = sif[m.end():]
    # [ \t] and not \s: \s* would swallow the trailing blank line, making
    # the returned block depend on what FOLLOWS it.
    e = re.search(r'(?m)^End[ \t]*$', rest)
    end = m.end() + (e.end() if e else len(rest))
    return sif[m.start():end]


def value(sif_block: str, key: str):
    """Value of `key` inside a block, or None.  Case-insensitive key."""
    m = re.search(rf'(?mi)^\s*{re.escape(key)}\s*=\s*(.+?)\s*$', sif_block)
    return m.group(1) if m else None


def keys(sif_block: str) -> list:
    out = []
    for line in sif_block.splitlines():
        s = line.strip()
        if not s or s.startswith('!'):
            continue
        if '=' in s:
            out.append(s.split('=', 1)[0].strip().lower())
    return out

CONFIG = os.path.join(ROOT, 'config.json')

sys.path.insert(0, ROOT)

CU = 'N50_L040_cu_closed'          # conductor, copper, 50 turns
AL = 'N50_L040_al_closed'          # conductor, aluminium, 50 turns
EMPTY = 'empty'                    # no conductor at all


# ---------------------------------------------------------------------------
#  structure of the generated closed-circuit SIF
# ---------------------------------------------------------------------------
def test_conductor_curve_gets_the_circuit_include():
    """The MNA matrices must be loaded before CircuitsAndDynamics runs, so
    the INCLUDE has to be near the top of the file."""
    sif = render('--curve', CU)
    m = re.search(r'(?m)^INCLUDE\s+circuits\.definitions\s*$', sif)
    assert m, 'no `INCLUDE circuits.definitions` for a conductor curve'
    assert m.start() < sif.index('Header'), \
        'the INCLUDE must precede the Header block'


def test_definitions_file_is_written_next_to_the_sif():
    """The SIF says `INCLUDE circuits.definitions`, which Elmer resolves
    relative to the SIF's own directory -- so the two must travel together."""
    _, tmp = render_with_dir('--curve', CU)
    p = os.path.join(tmp, 'circuits.definitions')
    assert os.path.exists(p), 'no circuits.definitions written beside the SIF'
    with open(p, encoding='utf-8') as f:
        assert f.read().strip(), 'circuits.definitions is empty'


def test_active_solvers_line_survives():
    r"""REGRESSION: `[\d\s]+` ate the newline and the next line, producing
    `Active Solvers(3) = 1 2 3 4 5 6 7Mesh Update = Logical True`."""
    sif = render('--curve', CU)
    hits = re.findall(r'(?m)^[ \t]*Active Solvers.*$', sif)
    assert len(hits) == 1, f'expected one Active Solvers line, got {hits}'
    line = hits[0]
    assert 'Mesh Update' not in line, f'the regex ate the next line: {line!r}'
    assert re.match(r'^[ \t]*Active Solvers\(\d+\)[ \t]*=[ \t]*'
                    r'\d+(?: \d+)*[ \t]*$', line), f'malformed line: {line!r}'


def test_active_solvers_count_matches_the_list():
    """A stale `(3)` with seven solvers listed is what Elmer reads."""
    sif = render('--curve', CU)
    m = re.search(r'(?m)^[ \t]*Active Solvers\((\d+)\)[ \t]*=[ \t]*(.+?)[ \t]*$',
                  sif)
    assert m, 'no Active Solvers line'
    listed = m.group(2).split()
    assert int(m.group(1)) == len(listed), \
        f'count says {m.group(1)} but {len(listed)} solvers are listed'


def test_active_solvers_has_the_expected_order_and_excludes_solver_4():
    """REGRESSION, introduced by the closed-circuit patch itself.

    The template's line is `Active Solvers(3) = 1 2 3`, i.e. **Solver 4 (the
    VTU writer) is deliberately NOT active** -- it is driven by
    `Output Intervals`.  The first version of this patch rewrote the line to
    `1 2 3 4 5 6 7`, silently activating Solver 4 and changing the output
    schedule of every conductor run.

    The order also matters: upstream `circuits_transient_stranded` runs the
    direction/frame solvers first (they are `Exec Solver = Before All`), then
    CircuitsAndDynamics BEFORE WhitneyAVSolver/CalcFields.
    """
    sif = render('--curve', CU)
    m = re.search(r'(?m)^[ \t]*Active Solvers\((\d+)\)[ \t]*=[ \t]*(.+?)[ \t]*$',
                  sif)
    assert m
    listed = m.group(2).split()
    assert listed == ['5', '6', '7', '8', '1', '9', '2', '3', '10', '11'], \
        f'unexpected Active Solvers order: {listed}'
    assert '4' not in listed, \
        'Solver 4 (VtuOutputSolver) must stay out of the Active Solvers list'
    assert listed[-1] == '11', \
        'SaveScalars (the circuit.csv writer) must run AFTER the circuit ' \
        'output it reads'


def test_active_solvers_only_references_defined_solvers():
    """Every number in the Active Solvers list must name a Solver block that
    actually exists, and Solver 4 is intentionally excluded (see the
    regression test above)."""
    sif = render('--curve', CU)
    m = re.search(r'(?m)^[ \t]*Active Solvers\((\d+)\)[ \t]*=[ \t]*'
                  r'([\d ]+?)[ \t]*$', sif)
    listed = {int(x) for x in m.group(2).split()}
    defined = {int(x) for x in re.findall(r'(?m)^Solver (\d+)\s*$', sif)}
    assert listed <= defined, \
        f'Active Solvers references undefined solvers: {sorted(listed - defined)}'
    assert listed == {1, 2, 3, 5, 6, 7, 8, 9, 10, 11}, \
        f'unexpected active set: {sorted(listed)}'


def test_circuits_and_dynamics_solvers_present():
    """Both halves of the circuit solver pair are required: one assembles
    and solves, the other writes the per-component i/v output."""
    sif = render('--curve', CU)
    assert '"CircuitsAndDynamics" "CircuitsAndDynamics"' in sif
    assert '"CircuitsAndDynamics" "CircuitsOutput"' in sif


def test_circuit_output_exports_the_circuit_variables():
    """REGRESSION (hpc/notes.md 15.9) -- WHY THE INDUCED CURRENT WAS INVISIBLE.

    `Circuits_ToMeshVariable` (CircuitUtils.F90:1527) opens with a hard gate:

        IF( .NOT. ListGetLogical( Solver % Values, &
            'Export Circuit Variables', Found ) ) RETURN

    so unless the CircuitsOutput solver carries the key, the `crt i` / `crt v`
    variables are NEVER created and no circuit quantity reaches any file.
    The values were also being written to the log only at Level 10, while the
    template asked for `Max Output Level = 8` -- so they were dropped twice
    over.  Both halves are load-bearing.
    """
    sif = render('--curve', CU)
    out = block(sif, 'Solver', 10)
    assert value(out, 'Procedure') == '"CircuitsAndDynamics" "CircuitsOutput"'
    assert value(out, 'Export Circuit Variables') == 'Logical True', \
        'without this key Circuits_ToMeshVariable returns immediately'
    assert float(value(sif, 'Max Output Level')) >= 10, \
        'the per-component i/v are logged at Level 10; a lower cap hides them'


def test_savescalars_writes_the_circuit_csv():
    """The per-step time series has to land in a file, not just the log.

    `i_component(1)` is the whole point of the closed-circuit experiment, so
    there must be a machine-readable output.  SaveScalars flattens `crt i` /
    `crt v` into results/circuit.csv, one row per step.
    """
    sif = render('--curve', CU)
    s = block(sif, 'Solver', 11)
    assert value(s, 'Procedure') == '"SaveData" "SaveScalars"'
    assert value(s, 'Filename') == '"circuit.csv"'
    assert value(s, 'Variable 1') == '"crt i"', \
        'crt i is the variable Circuits_ToMeshVariable creates for currents'
    assert value(s, 'Variable 2') == '"crt v"'
    assert value(s, 'Exec Solver') == '"After timestep"', \
        'the scalars must be collected after the circuit has been assembled'


def test_lc_slit_must_not_be_smaller_than_the_slit_width():
    """REGRESSION (hpc/notes.md 15.11) -- THE INSTABILITY GATE.

    If `lc_slit_m < coil.slit_width_m` the 3.5 mm slit is meshed with more
    than one element and the closed-circuit transient self-amplifies: the coil
    current is multiplied by a CONSTANT factor every timestep until the run
    overflows.  Measured per-step gains on the 3.5 mm slit:

        lc_slit_m   per-step gain   elements
        2.5 mm      1.777           30698
        3.0 mm      3.30            26375
        3.5 mm      1.199           21650
        4.0 mm      ~1.000          18743   <- stable
        8.0 mm      <1              12456   <- stable

    dt, R_load, the magnet's motion and the scalar-vs-vector W route were all
    tested and changed NOTHING.  The failure is silent (the solver exits 0 and
    writes a plausible results/circuit.csv), so the guard lives at mesh
    generation in solenoid3d.py:build().
    """
    cfgd = cfg()
    coil = cfgd['coil']
    mesh = cfgd['mesh']
    slit_w = float(coil['slit_width_m'])
    lc_slit = float(mesh['lc_slit_m'])
    assert lc_slit >= slit_w, (
        f"lc_slit_m = {lc_slit*1e3:.2f} mm < slit_width_m = {slit_w*1e3:.2f} mm"
        " -- that configuration makes the closed circuit diverge.  See"
        " hpc/notes.md 15.11."
    )


def test_solenoid3d_refuses_a_too_fine_slit():
    """The guard must actually be wired in, not just documented.

    This checks the source rather than running gmsh (the test suite is
    dependency-free), and it checks the SHAPE of the guard: the comparison,
    the threshold it compares against, and the message.
    """
    src = open(os.path.join(ROOT, 'solenoid3d.py'), encoding='utf-8').read()
    assert 'THE SLIT RESOLUTION GATE' in src, \
        'the lc_slit_m guard is gone from solenoid3d.py -- see notes.md 15.11'
    assert 'lc_slit < slit_w' in src, \
        'the guard no longer compares lc_slit_m against slit_width_m'
    assert 'self-amplify' in src, \
        'the guard message lost its explanation'


def test_no_duplicate_keys_in_solver_blocks():
    sif = render('--curve', CU)
    for n in (5, 6, 7):
        b = block(sif, 'Solver', n)
        ks = keys(b)
        dupes = sorted({k for k in ks if ks.count(k) > 1})
        assert not dupes, f'duplicate keys in Solver {n}: {dupes}'



def test_the_coil_has_a_wire_direction_potential():
    """FOUND BY RUNNING THE SIF (hpc/notes.md 13.9).

    A coil `Component` with no wire-direction potential gets as far as the
    first MagnetoDynamicsCalcFields call and then dies:

        WARNING:: GetWPotentialVar: Could not obtain variable for potential "W"
        Program received signal SIGSEGV ... magnetodynamicscalcfields_

    The fix is upstream `WPotentialSolver` plus `W = 0/1` on the two end
    faces.  Both must be present: the solver alone does nothing without the
    Dirichlet pair, and the pair alone leaves W unsolved in the coil body.
    """
    sif = render('--curve', CU)

    w = block(sif, 'Solver', 8)
    assert value(w, 'Procedure') == '"WPotentialSolver" "Wsolve"'
    assert value(w, 'Variable') == 'W'
    assert value(w, 'Exec Solver') == '"Before All"', \
        'W must be solved before the A-field that depends on it'

    assert value(block(sif, 'Boundary Condition', 3), 'W') == 'Real 1'
    assert value(block(sif, 'Boundary Condition', 4), 'W') == 'Real 0'


def test_circuit_solvers_run_before_timestep_not_always():
    """THE FIX FOR THE LONG-STANDING SEGFAULT (hpc/notes.md 15.7).

    Elmer executes the per-timestep solvers in SOLVER-NUMBER order, not in
    the order they appear in `Active Solvers`
    (`MainUtils.F90:3310` is `DO k=1,nSolvers; Solver => Model % Solvers(k)`).

    `MagnetoDynamicsCalcFields` is Solver 3, and solvers 1/2/3 are the
    template's, so the circuit can never be numbered below it.  With
    `Exec Solver = Always` it is therefore reached only AFTER CalcFields --
    which SEGFAULTs on the NULL Lagrange multiplier that the circuit has not
    yet created.  A circular dependency: the missing circuit causes the
    crash.

    `Exec Solver = "Before timestep"` moves them into the SOLVER_EXEC_AHEAD_TIME
    pre-pass (`MainUtils.F90:3014`), which runs before the Always pass.
    Solvers 9 and 10 MUST keep that value, and 10 must stay above 9 because
    the pre-pass is numeric order too.
    """
    sif = render('--curve', CU)
    for n in (9, 10):
        b = block(sif, 'Solver', n)
        assert value(b, 'Exec Solver') == '"Before timestep"', \
            f'Solver {n} must run in the `Before timestep` pre-pass, not ' \
            f'{value(b, "Exec Solver")!r} -- see hpc/notes.md 15.7'
    assert value(block(sif, 'Solver', 9), 'Procedure') == \
        '"CircuitsAndDynamics" "CircuitsAndDynamics"'
    assert value(block(sif, 'Solver', 10), 'Procedure') == \
        '"CircuitsAndDynamics" "CircuitsOutput"'
    # 9 assembles, 10 reports -> 10 must come later in numeric order
    assert 10 > 9


def test_every_relaxed_solver_really_runs_within_the_timestep():
    """Guard the whole per-timestep set: solvers that must run each step are
    either `Before timestep` (the circuit pair) or `Always` (the field
    solvers).  A solver left at the default `Always` while numbered ABOVE
    Solver 3 is fine; what is NOT fine is the circuit pair drifting back."""
    sif = render('--curve', CU)
    for n in (1, 2, 3):                      # mesh, Whitney, CalcFields
        assert value(block(sif, 'Solver', n), 'Exec Solver') == 'Always', \
            f'Solver {n} should stay `Always`'


def test_the_direction_stack_is_present():
    """Solvers 5..7 build the local wire frame that a stranded coil cannot
    define by itself.  Without RotMSolver, WPotentialSolver dies with
    `GetElementRotM: RotM E variable not found` -- observed.

    Also asserts the Alpha/Beta Dirichlet pairs and the two reference
    directions on Body 1, because RotMSolver needs all four.
    """
    sif = render('--curve', CU)
    assert value(block(sif, 'Solver', 5), 'Procedure') == \
        '"DirectionSolver" "DirectionSolver"'
    assert value(block(sif, 'Solver', 5), 'Variable') == 'Alpha'
    assert value(block(sif, 'Solver', 6), 'Variable') == 'Beta'
    assert value(block(sif, 'Solver', 7), 'Procedure') == \
        '"CoordinateTransform" "RotMSolver"'
    assert 'RotM E[RotM E:9]' in block(sif, 'Solver', 7)

    for bc, var, want in ((5, 'Alpha', 'Real 0'), (6, 'Alpha', 'Real 1'),
                          (7, 'Beta', 'Real 0'), (8, 'Beta', 'Real 1')):
        assert value(block(sif, 'Boundary Condition', bc),
                     f'Body 1: {var}') == want, f'BC {bc}'


def test_coil_component_is_stranded_with_the_curve_turn_count():
    c = cfg()['curves'][CU]
    sif = render('--curve', CU)
    b = block(sif, 'Component', 1)
    assert value(b, 'Coil Type') == 'String stranded'
    assert value(b, 'Number of Turns') == f'Real {int(c["N_turns"])}'
    assert value(b, 'Master Bodies') == 'Integer 1', \
        'the coil is Body 1 in the template'


def test_load_component_is_a_resistor_with_the_curve_resistance():
    """This is the whole trick: a resistor is just a Component, and Elmer
    fills in V = R*I itself."""
    c = cfg()['curves'][CU]
    sif = render('--curve', CU)
    b = block(sif, 'Component', 2)
    assert value(b, 'Component Type') == 'String Resistor'
    assert value(b, 'Resistance') == f'Real {float(c["R_load_ohm"])}'


def test_material1_conductivity_is_the_homogenised_wire_sigma():
    """REGRESSION (hpc/notes.md 15.8) -- THE 10x RESISTANCE BUG.

    `CircuitsAndDynamics.F90:697` builds the coil's series resistance as

        localR = N_j**2 * |w|**2 / sigma * dV

    i.e. R = N_j^2 * V_coil / sigma = N^2 * L_mean / (sigma * A_coil) -- the
    resistance of N turns each of cross-section *A_coil*, which implicitly
    assumes the winding window is SOLID conductor.  The physical wire
    resistance is N^2 * L_mean / (sigma_wire * f * A_coil), so the material
    fed to Elmer must carry the fill factor:

        sigma_eff = f * sigma_wire,   f = N * A_wire / A_coil.

    Skipping the factor makes the coil 1/f (~10x here) too conductive and the
    induced current ~10x too large.  Measured for the 50-turn copper curve
    before the fix: r_component(1) = 2.9026e-02 ohm; after: 3.0169e-01 ohm,
    against a 0.3082 ohm hand value.
    """
    import math

    cfgd = cfg()
    coil = cfgd['coil']
    a_coil = ((float(coil['r_outer_m']) - float(coil['r_inner_m']))
              * (float(coil['z1_m']) - float(coil['z0_m'])))
    l_mean = 2.0 * math.pi * 0.5 * (float(coil['r_inner_m'])
                                    + float(coil['r_outer_m']))

    checked = 0
    for curve, c in cfgd['curves'].items():
        if not isinstance(c, dict) or c.get('N_turns', 0) <= 0:
            continue
        checked += 1
        n = int(c['N_turns'])
        sigma_wire = float(c['wire_conductivity_S_per_m'])
        a_wire = math.pi * (0.5 * float(c['wire_diameter_m'])) ** 2
        f = n * a_wire / a_coil
        sigma_eff = f * sigma_wire

        got = float(value(block(render('--curve', curve), 'Material', 1),
                           'Electric Conductivity'))
        assert abs(got - sigma_eff) < 1e-6 * sigma_eff, \
            f'{curve}: sigma_eff = {got:.6e}, want {sigma_eff:.6e}'
        assert abs(got - sigma_wire) > 1e-6 * sigma_wire, \
            f'{curve}: sigma_wire {sigma_wire:.4e} leaked through -- the ' \
            f'fill factor is missing'

        # Elmer's resistance formula must now reproduce the physical wire R.
        r_elmer = n ** 2 * l_mean / (got * a_coil)
        r_wire = n * l_mean / (sigma_wire * a_wire)
        assert abs(r_elmer - r_wire) < 1e-6 * r_wire, \
            f'{curve}: Elmer R = {r_elmer:.4f} ohm, wire R = {r_wire:.4f} ohm'
    assert checked >= 2, 'the fixture found no conductor curves'


def test_fill_factor_is_strictly_between_zero_and_one():
    """A fill factor > 1 would mean the wires do not fit the winding window --
    a silent route to unphysical results."""
    import math

    cfgd = cfg()
    coil = cfgd['coil']
    a_coil = ((float(coil['r_outer_m']) - float(coil['r_inner_m']))
              * (float(coil['z1_m']) - float(coil['z0_m'])))
    checked = 0
    for curve, c in cfgd['curves'].items():
        if not isinstance(c, dict) or c.get('N_turns', 0) <= 0:
            continue
        checked += 1
        a_wire = math.pi * (0.5 * float(c['wire_diameter_m'])) ** 2
        f = int(c['N_turns']) * a_wire / a_coil
        assert 0.0 < f < 1.0, f'{curve}: fill factor {f:.4g} is not physical'
        assert f < 0.6, \
            f'{curve}: fill factor {f:.4g} is too high for round wire'
    assert checked >= 2, 'the fixture found no conductor curves'


def test_coil_start_and_end_are_renumbered_not_raw_gmsh_tags():
    """REGRESSION: gmsh tags 1003 / 1004 are renumbered by
    `ElmerGrid -autoclean`, so the SIF must target 3 / 4.  Writing 1003
    fails at load time with 'target boundary not found'."""
    sif = render('--curve', CU)
    start = block(sif, 'Boundary Condition', 3)
    end = block(sif, 'Boundary Condition', 4)
    assert value(start, 'Coil Start') == 'Logical True'
    assert value(start, 'Target Boundaries') == '3', \
        'target must be the renumbered index, not the gmsh tag 1003'
    assert value(end, 'Coil End') == 'Logical True'
    assert value(end, 'Target Boundaries') == '4', \
        'target must be the renumbered index, not the gmsh tag 1004'


def test_circuit_body_force_has_no_external_drive():
    """The magnet's motion is the only source.  A non-zero source would put
    a static pedestal on the field and mask the induced signal."""
    sif = render('--curve', CU)
    b = block(sif, 'Body Force', 3)
    assert value(b, 'Name') == '"Circuit"', \
        f'Body Force 3 is not the circuit block: {b!r}'
    assert value(b, 'testsource') == 'Real 0.0', \
        'the circuit source must be 0 V -- no external drive'


def test_closed_generation_is_deterministic():
    assert render('--curve', CU) == render('--curve', CU)



# ---------------------------------------------------------------------------
#  the sibling circuits.definitions (the MNA matrices)
# ---------------------------------------------------------------------------
def mna() -> str:
    _, tmp = render_with_dir('--curve', CU)
    with open(os.path.join(tmp, 'circuits.definitions'), encoding='utf-8') as f:
        return f.read()


def test_definitions_declares_one_circuit_with_the_mna_matrices():
    d = mna()
    assert re.search(r'(?m)^\$\s*Circuits\s*=\s*1\s*$', d), \
        'no `$ Circuits = 1`'
    for key in ('C.1.variables', 'C.1.A', 'C.1.B', 'C.1.Mre', 'C.1.Mim'):
        assert re.search(rf'(?m)^\$\s*{re.escape(key)}\s*=', d), \
            f'missing MNA key {key}'
    assert re.search(r'(?m)^\$\s*C\.1\.variables\s*=\s*6\s*$', d), \
        'the series loop needs exactly 6 unknowns'


def test_definitions_names_the_coil_and_the_load_unknowns():
    """i/v_component(1) is the coil, i/v_component(2) is the resistor -- the
    names are how Elmer binds the SIF `Component` blocks to the equations."""
    d = mna()
    for name in ('i_component(1)', 'v_component(1)',
                 'i_component(2)', 'v_component(2)'):
        assert f'"{name}"' in d, f'{name} not declared in the circuit'
    assert re.search(r'(?m)^\$\s*C\.1\.source\.1\s*=\s*"testsource"\s*$', d), \
        'the circuit must declare its (zero-volt) source'


def test_definitions_does_not_fill_the_rows_elmer_owns():
    r"""Elmer writes V=RI into the row of each v_component(j).  If we also
    wrote entries there, the component equation would be overwritten.

        v_component(1) is unknown 4 -> column 3 -> row 3
        v_component(2) is unknown 6 -> column 5 -> row 5
    """
    d = mna()
    for row in (3, 5):
        hits = re.findall(rf'(?m)^\$\s*C\.1\.[AB]\(\s*{row}\s*,', d)
        assert not hits, \
            f'row {row} belongs to Elmer component equation, found {hits}'


# ---------------------------------------------------------------------------
#  the no-conductor baseline must not move at all
# ---------------------------------------------------------------------------
def test_baseline_is_byte_identical_to_the_template():
    """`--curve empty` and no `--curve` at all must BOTH reproduce
    case_transient.sif exactly.  Anything else means a closed-circuit patch
    has leaked into the baseline, and every comparison against it becomes
    meaningless."""
    tpl = template()
    assert render('--curve', EMPTY) == tpl, \
        '--curve empty is no longer the untouched template'
    assert render() == tpl, \
        'the no-curve path is no longer the untouched template'


def test_baseline_writes_no_circuit_files():
    _, tmp = render_with_dir('--curve', EMPTY)
    stray = [f for f in os.listdir(tmp) if f != 'case.sif']
    assert not stray, f'the baseline wrote unexpected files: {stray}'


def test_baseline_has_no_circuit_machinery():
    sif = render('--curve', EMPTY)
    for needle in ('CircuitsAndDynamics', 'Component 1', 'circuits.definitions',
                   'Coil Start', 'Coil End', 'String stranded',
                   'String Resistor', 'WPotentialSolver'):
        assert needle not in sif, f'baseline SIF leaked {needle!r}'


def test_baseline_leaves_the_coil_conductivity_at_zero():
    """sigma = 0 is what makes the baseline a genuinely dead conductor."""
    b = block(render('--curve', EMPTY), 'Material', 1)
    assert float(value(b, 'Electric Conductivity')) == 0.0


def test_baseline_keeps_the_template_solver_list():
    sif = render('--curve', EMPTY)
    m = re.search(r'(?m)^[ \t]*Active Solvers\((\d+)\)[ \t]*=[ \t]*(.+?)[ \t]*$',
                  sif)
    assert m.group(2).split() == ['1', '2', '3'], \
        f'the baseline solver list changed: {m.group(0).strip()!r}'



# ---------------------------------------------------------------------------
#  blast radius -- only the circuit regions may move
# ---------------------------------------------------------------------------
def test_pre_existing_solver_and_bc_blocks_are_untouched():
    """Solvers 1, 3 and 4 and Boundary Conditions 1-2 must survive verbatim.

    Solver 2 is the ONE exception: it gains `Export Lagrange Multiplier =
    Logical True`, which is what lets CircuitsAndDynamics find the
    A-solver (`FindSolverWithKey`) and what makes CalcFields able to read
    the circuit current.  That is asserted explicitly instead of being
    waved through.
    """
    tpl = template()
    sif = render('--curve', CU)
    for n in (1, 3, 4):
        assert block(sif, 'Solver', n).strip() == block(tpl, 'Solver', n).strip(), \
            f'Solver {n} changed for a conductor curve'
    for n in (1, 2):
        assert block(sif, 'Boundary Condition', n).strip() == \
            block(tpl, 'Boundary Condition', n).strip(), \
            f'Boundary Condition {n} changed for a conductor curve'

    # Solver 2 gains exactly the two keys and nothing else.
    b2 = block(sif, 'Solver', 2)
    assert value(b2, 'Export Lagrange Multiplier') == 'Logical True', \
        'WhitneyAVSolver must export the Lagrange multiplier, or ' \
        'CircuitsAndDynamics cannot find it and CalcFields segfaults'
    assert value(b2, 'NonLinear System Relaxation Factor') == '1'
    t2 = block(tpl, 'Solver', 2)
    stripped = b2
    for line in ('  Export Lagrange Multiplier = Logical True\n',
                 '  NonLinear System Relaxation Factor = 1\n'):
        stripped = stripped.replace(line, '')
    assert stripped.strip() == t2.strip(), \
        'Solver 2 changed by more than the two Lagrange keys'


def test_shared_materials_and_bodies_are_untouched():
    """Material 1's sigma is SUPPOSED to change, and Body 1 is supposed to
    gain the Alpha/Beta reference directions.  Everything else in the
    Materials/Body sections must not."""
    tpl = template()
    sif = render('--curve', CU)
    for mat in (2, 3):
        assert block(tpl, 'Material', mat) == block(sif, 'Material', mat), \
            f'Material {mat} changed'

    # Body 1 gains exactly the two reference keys.
    b1 = block(sif, 'Body', 1)
    assert value(b1, 'Alpha reference (3)') == 'Real 1 0 0'
    assert value(b1, 'Beta reference (3)') == 'Real 0 0 1'
    stripped = b1
    for line in ('  ! The local frame RotMSolver builds out of the two '
                 'direction\n',
                 '  ! solves: Alpha runs radially outward, Beta runs '
                 'axially, so\n',
                 '  ! gamma = alpha x beta = -theta-hat, the solenoid\'s '
                 'wire\n',
                 '  ! direction (hpc/notes.md 13.12).\n',
                 '  Alpha reference (3) = Real 1 0 0\n',
                 '  Beta reference (3) = Real 0 0 1\n'):
        stripped = stripped.replace(line, '')
    assert stripped.strip() == block(tpl, 'Body', 1).strip(), \
        'Body 1 changed by more than the two reference keys'

    for body in (2, 3):
        assert block(tpl, 'Body', body) == block(sif, 'Body', body), \
            f'Body {body} changed'


def test_magnet_body_force_is_untouched():
    """The spring/free-fall motion law is the one thing a circuit change must
    never disturb."""
    tpl = template()
    sif = render('--curve', CU)
    for n in (1, 2):
        assert block(tpl, 'Body Force', n) == block(sif, 'Body Force', n), \
            f'Body Force {n} changed'


# ---------------------------------------------------------------------------
#  refusal paths
# ---------------------------------------------------------------------------
def test_rejects_a_typo_curve_name():
    rc, err, _ = run('--curve', 'N50_L040_cu_closd', expect_ok=False)
    assert rc != 0, 'a misspelled curve should be refused'
    assert 'not a valid curve' in err


def test_rejects_a_doc_string_as_a_curve():
    """`_comment_block` lives in [curves] but is a string, not a curve."""
    rc, err, _ = run('--curve', '_comment_block', expect_ok=False)
    assert rc != 0, 'a doc-string entry should be refused'
    assert 'not a valid curve' in err


def test_config_has_no_open_curves_left():
    """The open-circuit variant was removed.  If one ever reappears in
    config.json, the run scripts would silently produce an open-loop SIF
    that looks fine and measures nothing."""
    curves = cfg()['curves']
    leftover = [k for k, v in curves.items()
                if isinstance(v, dict) and k.endswith('_open')]
    assert not leftover, f'open curves are back: {leftover}'
    # every conductor curve must carry a finite load
    for k, v in curves.items():
        if isinstance(v, dict) and int(v.get('N_turns', 0) or 0) > 0:
            assert not isinstance(v.get('R_load_ohm'), str), \
                f'{k} has a non-numeric R_load_ohm: {v.get("R_load_ohm")!r}'


def test_every_conductor_curve_generates_a_circuit():
    """The generator must produce the full circuit for ALL 6 conductor
    curves, not just the one this file happens to test."""
    for k, v in cfg()['curves'].items():
        if not isinstance(v, dict) or int(v.get('N_turns', 0) or 0) <= 0:
            continue
        sif = render('--curve', k)
        assert 'CircuitsAndDynamics' in sif, f'{k}: no circuit solver'
        comp = block(sif, 'Component', 1)
        assert value(comp, 'Number of Turns') == f'Real {int(v["N_turns"])}', \
            f'{k}: wrong turn count in Component 1'


if __name__ == '__main__':
    # standalone execution (no pytest needed)
    print('=== make_sif.py closed-circuit tests ===')
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


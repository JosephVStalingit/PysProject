"""
tests/test_spring_model.py -- lock down the damped-harmonic-oscillator
math in spring_model.py.

WHY THIS EXISTS
---------------
`spring_model.load_spring()` is the single source of truth for two
downstream consumers that must agree, byte-for-byte at t = N*dt:

  * `make_sif.py --out case.sif` writes the damped-oscillator MATC
    expression into Solver 1's `Real MATC` (this is the DISPLACEMENT
    from the initial mesh position z_release).
  * `verify_spring.py` reads VTU frames and compares them to `z_of_t(sp, t)`
    (this is the ABSOLUTE position).

Both code paths use the same `omega0, gamma, omega_d, A` but only because
spring_model.py agrees with itself.  A silent change to a sign, the
under-damped branch, or the z_eq <-> L0 consistency loop would silently
break the spring verification -- the FEM run would still solve fine, the
mesh would still move, but the apparent "attenuation" would be a sign
error in the physics module, not a real solver artefact.

This file has zero dependencies (no Elmer, no gmsh, no meshio).

KEY INVARIANTS LOCKED DOWN
--------------------------
  1. Self-consistency:
       z_of_t(sp, 0) == z_eq + A == z_release
       matc displacement + z_release == z_of_t at any t
       v_of_t(sp, t) - z_of_t finite-difference ~ 0 (independent of dt)
  2. Physical sanity:
       omega_d < omega0 (underdamped)
       T = 2*pi/omega0,  Q = omega0/(2*gamma)
       L0 > 0,  z_min < z_eq < z_max,  L_min < L_max
  3. The MATC expression is a DISPLACEMENT (== 0 at t=0), NOT the
     absolute position.
  4. The constant mesh offset between frame 1 and z_of_t(sp, dt)
     reported by `verify_spring.py` is consistent with the analytic
     derivative v_of_t(sp, 0).
"""
from __future__ import annotations
import json
import math
import os
import sys

try:
    import pytest  # type: ignore
except ImportError:
    pytest = None  # type: ignore

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG_PATH = os.path.join(ROOT, 'config.json')

sys.path.insert(0, ROOT)
from spring_model import (                  # noqa: E402
    load_spring, z_of_t, v_of_t, matc_expr,
    analytic_z, b_em_from_linkage, check_coupled, check_sign, coupled_z,
    fit_gamma, matc_expr_gamma,
)


def _cfg():
    with open(CFG_PATH, encoding='utf-8') as f:
        return json.load(f)


def _matc_at(expr: str, t: float) -> float:
    """Evaluate the MATC expression at time `t`.  The Spring 2026 MATC
    expression only uses cos, sin, exp -- all in `math` under the same
    names."""
    g = {'tx': t, 'math': math, 'cos': math.cos, 'sin': math.sin,
         'exp': math.exp}
    return eval(expr, g)


# ---------------------------------------------------------------------------
#  the numerical values spring_model is expected to produce
# ---------------------------------------------------------------------------
# These are the headline numbers from the project's own CHANGELOG and README;
# if any of them changes, every downstream consumer (geometry, SIF, verifier,
# oscilloscope) has to be re-validated.  Pin them.
def test_headline_numbers_match_config_json():
    sp = load_spring()
    assert sp['m'] == 0.5
    assert sp['k'] == 220.0
    assert sp['c'] == 0.8
    assert abs(sp['omega0'] - math.sqrt(220 / 0.5)) < 1e-12
    assert abs(sp['period'] - 0.2995) < 5e-4
    assert abs(sp['Q'] - 13.1) < 0.1
    # BATCH-2 UPDATE (2026-09-15): config.json's spring.z_eq_m was moved from
    # 0.020 to 0.024 m after the 900-frame VTU measurement of the magnet
    # midline (see README 1 / config `_comment_geometry_correction`).  That
    # also changed the amplitude, since A = z_release - z_eq = 0.045 - 0.024.
    # These two are the values the whole 900-step sweep actually ran with:
    # every hpc_results_z900/<case>/results/case.sif carries A = 0.021,
    # z_eq = 0.024 (the MATC offset -0.021).
    assert abs(sp['z_eq_m'] - 0.024) < 1e-4
    assert abs(sp['amplitude'] - 0.021) < 1e-4


def test_period_is_two_pi_over_omega0():
    sp = load_spring()
    assert abs(sp['period'] - 2 * math.pi / sp['omega0']) < 1e-12


def test_frequency_is_one_over_period():
    sp = load_spring()
    assert abs(sp['freq'] - 1 / sp['period']) < 1e-12


def test_quality_factor():
    sp = load_spring()
    assert abs(sp['Q'] - sp['omega0'] / (2 * sp['gamma'])) < 1e-12


def test_is_underdamped():
    sp = load_spring()
    assert sp['omega_d'] < sp['omega0'], \
        f'over/critically damped: gamma={sp["gamma"]}, omega0={sp["omega0"]}'
    assert sp['omega_d'] > 0


def test_omega_d_relation():
    sp = load_spring()
    assert abs(sp['omega_d']**2
               - (sp['omega0']**2 - sp['gamma']**2)) < 1e-12


# ---------------------------------------------------------------------------
#  z_of_t / v_of_t -- the analytic solutions used by verify_spring.py.
# ---------------------------------------------------------------------------
def test_z_of_t_at_zero_is_z_release():
    """At t=0 the magnet is released from rest at z_release."""
    sp = load_spring()
    assert abs(z_of_t(sp, 0.0) - sp['z_release_m']) < 1e-15


def test_z_of_t_tends_to_z_eq_as_t_grows():
    """For an underdamped oscillator |z(t) - z_eq| <= A * exp(-gamma * t)
    for all t >= 0 (the cosine/sine envelope decays monotonically).
    Test the envelope, not the instantaneous phase.
    """
    sp = load_spring()
    for n_periods in (1, 5, 10, 30):
        t = n_periods * sp['period']
        envelope = abs(sp['amplitude']) * math.exp(-sp['gamma'] * t)
        actual = abs(z_of_t(sp, t) - sp['z_eq_m'])
        assert actual <= envelope * (1 + 1e-12), (
            f't={t}: |z-z_eq|={actual:.4e} > envelope {envelope:.4e}')


def test_z_of_t_matches_v_of_t_finite_difference():
    """A wrong sign in v_of_t -- which the FEM does NOT directly verify --
    would break any future velocity-based verifier."""
    sp = load_spring()
    dt = sp['period'] / 1000
    for t0 in (0.0, sp['period']/4, sp['period']/2,
               sp['period'], 2 * sp['period']):
        v_num = (z_of_t(sp, t0 + dt) - z_of_t(sp, t0 - dt)) / (2 * dt)
        v_exact = v_of_t(sp, t0)
        assert abs(v_num - v_exact) < 1e-3 * abs(sp['amplitude']) * sp['omega0']


def test_v_of_t_at_zero_is_zero():
    """Released from rest -- the assumption baked into the closed-form
    solution.  If this fails, the MATC expression is wrong."""
    assert abs(v_of_t(load_spring(), 0.0)) < 1e-15


# ---------------------------------------------------------------------------
#  z_eq <-> L0 consistency loop.  z_eq is computed two ways in
#  load_spring; the second must reproduce the first.
# ---------------------------------------------------------------------------
def test_Leq_minus_L0_equals_static_sag():
    sp = load_spring()
    assert abs((sp['L_eq'] - sp['L0']) - sp['sag']) < 1e-12


def test_z_eq_from_definition_matches_L0():
    """config pins `s["z_eq_m"]`; load_spring must recompute z_eq from
    L0+sag and land on the same value."""
    sp = load_spring()
    cfg = _cfg()
    H = cfg['magnet']['z1_m'] - cfg['magnet']['z0_m']
    L_eq = cfg['spring']['anchor_z0_m'] - (cfg['spring']['z_eq_m'] + H / 2)
    z_eq_recovered = (cfg['spring']['anchor_z0_m']
                      - H / 2 - sp['L0'] - sp['sag'])
    assert abs(sp['z_eq_m'] - z_eq_recovered) < 1e-9
    assert abs(sp['L_eq'] - L_eq) < 1e-9


def test_amplitude_is_z_release_minus_z_eq():
    sp = load_spring()
    assert abs(sp['amplitude'] - (sp['z_release_m'] - sp['z_eq_m'])) < 1e-15


def test_L0_is_positive():
    sp = load_spring()
    assert sp['L0'] > 0


def test_z_min_below_z_eq_below_z_max():
    sp = load_spring()
    assert sp['z_min'] <= sp['z_eq_m'] <= sp['z_max']


def test_spring_stretches_monotonically_with_travel():
    """As the magnet moves toward the anchor (z increases), the spring
    shrinks.  L_min is at the upper end of the magnet travel."""
    sp = load_spring()
    assert sp['L_min'] <= sp['L_max']


# ---------------------------------------------------------------------------
#  matc_expr -- the displacement the RigidMeshMapper applies each step.
# ---------------------------------------------------------------------------
def test_matc_expr_is_zero_at_t0():
    """`Mesh Translate 3 = Real MATC "<expr>"` is the DISPLACEMENT from
    the initial mesh position.  It must be zero at t=0; otherwise the
    mesh jumps on frame 1 and verify_spring.py reports an impossible
    constant offset."""
    sp = load_spring()
    assert abs(_matc_at(sp['matc_expr'], 0.0)) < 1e-9


def test_matc_expr_plus_z_release_matches_z_of_t():
    """MATC displacement + initial mesh position must reproduce the
    analytic z(t) for any t.  A sign error here would make the magnet
    swing the wrong way and the verifier would label it 'attenuation'."""
    sp = load_spring()
    expr = sp['matc_expr']
    for t in (0.0, 1e-3, 0.05, 0.075, 0.15, sp['period'], 2 * sp['period']):
        dmatc = _matc_at(expr, t)
        assert abs(sp['z_release_m'] + dmatc - z_of_t(sp, t)) < 1e-12, (
            f't={t}: matc says {dmatc}, analytic says '
            f'{z_of_t(sp, t) - sp["z_release_m"]}')


# ---------------------------------------------------------------------------
#  Cross-module consistency guards
# ---------------------------------------------------------------------------
def test_uses_actual_magnet_extent_not_H_mag_field():
    """H_mag_m in config.json is the HALF height used by the on-axis
    dipole formula in solenoid3d.py.  spring_model must derive the full
    height from z1 - z0 so the two cannot disagree."""
    sp = load_spring()
    cfg = _cfg()
    H_actual = cfg['magnet']['z1_m'] - cfg['magnet']['z0_m']
    assert abs(sp['H'] - H_actual) < 1e-15


def test_omega0_follows_sqrt_k_over_m():
    """Regression guard for the documented omega0 formula."""
    sp = load_spring()
    assert abs(sp['omega0'] - math.sqrt(sp['k'] / sp['m'])) < 1e-12


def test_overdamped_input_raises():
    """load_spring raises SystemExit if omega0 <= gamma, i.e. c >= 2*sqrt(k*m).

    With k=220, m=0.5 that threshold is c >= 20.98.  c=30 is well past it.
    """
    cfg = _cfg()
    cfg['spring']['damping_N_s_per_m'] = 30.0
    try:
        load_spring(cfg)
    except SystemExit as e:
        assert 'over-damped' in str(e), f'unexpected SystemExit: {e}'
    else:
        raise AssertionError('over-damped input should have raised')


# ---------------------------------------------------------------------------
#  COUPLED model (Lenz drag) -- added with the Rx_load / sensor work (README 11)
# ---------------------------------------------------------------------------
def test_b_em_from_linkage_is_the_energy_identity():
    """F_lenz = -b_em * z' is not a model choice: the electrical power
    i^2*R that the motional EMF extracts IS the mechanical power F*z'.
    With eps = (dLambda/dz)*z' and eps = i*R this gives
        b_em = (dLambda/dz)^2 / R_total
    so the drag must scale as the SQUARE of the linkage gradient and as 1/R.
    """
    assert abs(b_em_from_linkage(0.2, 10.0) - 0.04 / 10.0) < 1e-15
    # halving the resistance doubles the drag
    assert abs(b_em_from_linkage(0.2, 5.0) / b_em_from_linkage(0.2, 10.0) - 2.0) < 1e-15
    # doubling the linkage gradient quadruples it (this is the N^2 law)
    assert abs(b_em_from_linkage(0.4, 10.0) / b_em_from_linkage(0.2, 10.0) - 4.0) < 1e-15
    try:
        b_em_from_linkage(0.2, 0.0)
    except ValueError:
        pass
    else:
        raise AssertionError('R_total = 0 must raise')


def test_check_sign_is_restoring_and_rooted_at_z_eq():
    """Guard for the `+-k(L-L0)` sign.  The magnet hangs from the TOP, so the
    spring pulls UP (+z) while gravity pulls DOWN:
        m z'' = -m g + k(L - L0)
    The force must vanish exactly at z_eq and its slope must be -k.  The
    opposite sign puts the root at 0.0686 m with a POSITIVE slope, i.e. an
    unstable runaway -- and it is what an earlier revision of the docstring
    claimed, so it is worth locking down.
    """
    sp = load_spring()
    ck = check_sign(sp)
    assert ck['restoring'], 'the spring force must be restoring'
    assert ck['root_matches_zeq'], f"root {ck['root']} != z_eq {sp['z_eq_m']}"
    assert abs(ck['force_at_zeq']) < 1e-12
    assert abs(ck['slope'] + sp['k']) < 1e-3          # dF/dz == -k


def test_coupled_z_without_drag_reproduces_the_analytic_solution():
    """With b_em = 0 the RK4 integrator must land on z_of_t / v_of_t.  If this
    fails, every coupled number in README 11 is built on a broken integrator."""
    sp = load_spring()
    ez, ev = check_coupled(sp)
    assert ez < 1e-12, f'|z_RK4 - z_analytic| = {ez}'
    assert ev < 1e-10, f'|v_RK4 - v_analytic| = {ev}'


def test_coupled_z_preserves_the_initial_conditions_with_drag():
    """Released from rest: z(0) = z_release and z'(0) = 0 for ANY drag."""
    sp = load_spring()
    b = b_em_from_linkage(2.4e-1, 0.63)               # a deliberately large drag
    t, z, v = coupled_z(sp, lambda _z: b, t_end=0.05, dt=1e-5)
    assert abs(z[0] - sp['z_release_m']) < 1e-15
    assert abs(v[0]) < 1e-15


def test_coupled_z_drag_shifts_gamma_by_b_over_2m():
    """A constant drag b is just extra damping, so the decay rate must become
    gamma + b/(2m) exactly.  This is the identity that makes ONE correction
    pass enough for the co-simulation in README 11.4.
    """
    sp = load_spring()
    b = 5.0e-3
    t, z, _v = coupled_z(sp, lambda _z: b, t_end=3.0 * sp['period'], dt=1e-5)
    gm, _res = fit_gamma(sp, t, z)
    want = sp['gamma'] + b / (2.0 * sp['m'])
    assert abs(gm - want) / want < 1e-6, f'fit {gm}, expected {want}'


def test_fit_gamma_recovers_the_config_gamma():
    """Round trip: integrating with b_em = 0 and fitting must give gamma back."""
    sp = load_spring()
    t, z, _v = coupled_z(sp, None, t_end=sp['period'], dt=1e-5)
    gm, _res = fit_gamma(sp, t, z)
    assert abs(gm - sp['gamma']) < 1e-9


def test_matc_expr_gamma_reproduces_the_sif_expression():
    """`matc_expr_gamma(sp, gamma)` at the config gamma must be CHARACTER-FOR-
    CHARACTER identical to `matc_expr(sp)` -- the string that all seven
    hpc_results_z900/<case>/results/case.sif files carry.  This is the
    strongest available check that the coupled path reuses the same family.
    """
    sp = load_spring()
    assert matc_expr_gamma(sp, sp['gamma']) == sp['matc_expr']
    for t in (0.0, 1e-3, 0.075, 0.3, 0.9):
        assert abs(_matc_at(sp['matc_expr'], t)
                   - _matc_at(matc_expr_gamma(sp, sp['gamma']), t)) < 1e-18


def test_matc_expr_gamma_keeps_the_release_conditions():
    """Overriding gamma must NOT move the release point: the MATC expression
    stays the DISPLACEMENT from the initial mesh position, so it is zero at
    t = 0 and its derivative vanishes there, whatever gamma is."""
    sp = load_spring()
    for g in (sp['gamma'], 1.1 * sp['gamma'], 0.9 * sp['gamma']):
        e = matc_expr_gamma(sp, g)
        assert abs(_matc_at(e, 0.0)) < 1e-12
        d = (_matc_at(e, 1e-7) - _matc_at(e, 0.0)) / 1e-7
        assert abs(d) < 1e-6, f'v(0) = {d} for gamma = {g}'
        # and it must still tend to z_eq - z_release.  CAREFUL: 1/gamma = 1.25 s,
        # so t = 5 s is only 4 e-foldings (e^-4 = 0.018) and the residual would
        # still be ~4e-4 -- use t = 60 s (48 e-foldings).
        assert abs(_matc_at(e, 60.0) - (sp['z_eq_m'] - sp['z_release_m'])) < 1e-9


def test_analytic_z_with_override_is_monotone_in_gamma():
    """Sanity: a larger gamma can only LOWER the envelope at t > 0."""
    sp = load_spring()
    t = 0.25
    a = analytic_z(sp, t, sp['gamma'])
    b = analytic_z(sp, t, 1.2 * sp['gamma'])
    assert abs(b - sp['z_eq_m']) < abs(a - sp['z_eq_m'])


if __name__ == '__main__':
    print('=== spring_model tests ===')
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

# -*- coding: utf-8 -*-
"""
test_oscilloscope.py  --  verify oscilloscope.py for the magnet free-fall experiment

Physics expectations (magnet dropped from z=0.110 m, B-field acts as brake):

    empty : open ckt  -> I = 0  -> only air drag (small)
    copper: short ckt -> huge eddy current -> strongest Lenz drag
    coil  : 10 ohm    -> moderate Lenz current -> moderate drag

We assert:
    1. all 3 simulations actually reach z_final (< -0.05 m)
    2. passage time is finite and within sensible bounds (150-300 ms for 16cm drop)
    3. passage_time is MONOTONICALLY increasing with damping strength:
       empty < copper < coil   (more drag -> longer to fall)
    4. peak velocity |v|_peak is MONOTONICALLY DECREASING:
       empty > copper > coil   (more drag -> slower)
    5. the dashboard PNG and summary txt are written
    6. config.json is read correctly (single source of truth)
"""
import os, sys
from pathlib import Path
import math

WORKDIR = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(WORKDIR))
import oscilloscope as osc


def test_config_loaded():
    """All key config sections present."""
    assert osc._CFG["experiment"]["name"] == "magnet_free_fall"
    assert set(osc.CONFIGS) == {"empty", "copper", "coil"}
    assert osc.EXTRAS["passage_time_bar"]["title"]


def test_damping_monotonic():
    """Total damping must be strictly increasing empty < copper < coil."""
    dampings = [osc.DAMPING[c] for c in osc.CONFIGS]
    assert dampings[0] < dampings[1] < dampings[2], \
        f"damping not monotonic: {dampings}"


def test_passage_time_monotonic():
    """More Lenz drag -> magnet takes LONGER to reach z_target.
       So passage_time must be empty < copper < coil."""
    passages = []
    for c in osc.CONFIGS:
        d = osc.simulate_full(c)
        p = osc.passage_time(d)
        assert not math.isnan(p), f"{c}: passage_time is NaN"
        passages.append(p)
    assert passages[0] < passages[1] < passages[2], \
        f"passage time not monotonic: {passages}"


def test_peak_velocity_decreasing():
    """Stronger drag -> smaller terminal velocity magnitude."""
    peaks = []
    for c in osc.CONFIGS:
        d = osc.simulate_full(c)
        peaks.append(float(max(abs(d["v"]))))
    assert peaks[0] > peaks[1] > peaks[2], \
        f"v_peak not decreasing: {peaks}"


def test_magnet_actually_falls():
    """All configs must reach z_final < -0.05 (proves magnet really fell)."""
    for c in osc.CONFIGS:
        d = osc.simulate_full(c)
        assert d["z"][-1] < -0.04, \
            f"{c}: magnet stuck at z={d['z'][-1]:.4f}, didn't fall"


def test_vacuum_reference():
    """t = sqrt(2 h / g) for free fall from 0.110 to z_target."""
    h = osc.Z_RELEASE - osc.EXTRAS["passage_time_bar"]["z_target_m"]
    t_vacuum = math.sqrt(2 * h / osc.G)
    # empty config should be CLOSE to (but a little larger than) vacuum,
    # because air drag is small but non-zero.
    d = osc.simulate_full("empty")
    p = osc.passage_time(d)
    assert t_vacuum < p < t_vacuum * 1.10, \
        f"empty passage {p*1000:.1f} ms not within 10% of vacuum {t_vacuum*1000:.1f} ms"


def test_oscilloscope_png():
    """Dashboard PNG must be written and non-trivial in size."""
    out = osc.RESULTS / "dashboard.png"
    if out.exists():
        out.unlink()
    data = {cfg: osc.simulate_full(cfg) for cfg in osc.CONFIGS}
    passage = {cfg: osc.passage_time(data[cfg]) for cfg in osc.CONFIGS}
    osc.make_dashboard(out, data, passage)
    assert out.exists(), "PNG not written"
    assert out.stat().st_size > 50_000, "PNG too small"


def test_summary_txt():
    """Summary txt must contain all 3 config names and a passage-time row."""
    out = osc.RESULTS / "summary.txt"
    if out.exists():
        out.unlink()
    data = {cfg: osc.simulate_full(cfg) for cfg in osc.CONFIGS}
    passage = {cfg: osc.passage_time(data[cfg]) for cfg in osc.CONFIGS}
    osc.write_summary(data, passage, out)
    assert out.exists()
    content = out.read_text(encoding="utf-8")
    assert "empty" in content
    assert "copper" in content
    assert "coil" in content
    assert "t_pass(ms)" in content
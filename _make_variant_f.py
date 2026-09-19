"""Variant F: follow upstream coil.sif exactly -- NonConductive coil body plus
an EXPLICIT `Resistance` on Component 1.

Why this is needed now
----------------------
Variant C (CoilSolver + W vector) fixed the EMF scaling -- i(25)/i(1) =
24.9871 vs the expected 25, where the Wsolve path gave 0.0474 -- but it made
the RESISTANCE wrong:

    r_component(1) = 13.030 (N=25)  vs  13.081 (N=1)   ratio 0.996

i.e. N-INDEPENDENT, whereas a real wire has R = N * L_turn / (A_wire*sigma).
The two paths are complementary: Wsolve gets R right and the EMF wrong,
CoilSolver gets the EMF right and R wrong.  The reason is that CoilSolver
normalises the wire vector itself (CoilSolver.F90:2378
`NormCoeff = DesiredCurrentDensity / SQRT(SUM(GradPot**2))`, so |w| already
carries its own 1/N), and that normalisation is what the lumped-R integral
then re-squares.

Upstream sidesteps the whole question: its coil body is a "Dummy" material
with NO conductivity, and the resistance is stated on the Component:

    coil.sif   Material 1   Name = "Dummy"      (only mu_r, eps_r)
    coil.sif   Component 1  Resistance = Real 0

so `CircuitsAndDynamics.F90` takes `Comp % Resistance` instead of the
volume integral.  That is an exact, mesh-independent, N-exact R.

This probe uses Resistance = 1e-3 ohm ONLY to prove the mechanism (that the
value is taken from the Component rather than from the integral); the
physically correct R_wire(N) is then a mechanical change in make_sif.py.

Run:  python _make_variant_f.py
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ELMER = ROOT / 'elmer262' / 'bin' / 'ElmerSolver.exe'
TEST_R = '1.0e-3'


def build(src_case, name):
    src = ROOT / '_smoke_csolv' / src_case / 'case.sif'
    text = src.read_text(encoding='utf-8')

    # 1. the coil body's Material must stop being conductive
    text, n1 = re.subn(
        r'(?ms)(^Material 1\n.*?^  Electric Conductivity = )[0-9.eE+-]+',
        r'\g<1>1.0e-12', text)
    assert n1 == 1, 'coil Electric Conductivity not found (%d)' % n1

    # 2. put an explicit Resistance on Component 1
    text, n2 = re.subn(
        r'(?m)^(  Coil Normal\(3\) = Real 0\.0 0\.0 1\.0\s*)$',
        r'\g<1>\n  Resistance = Real ' + TEST_R, text)
    assert n2 == 1, 'Component 1 Coil Normal anchor not found (%d)' % n2

    d = ROOT / '_smoke_csolv' / name
    if d.exists():
        shutil.rmtree(d)
    shutil.copytree(ROOT / '_smoke_csolv' / src_case, d)
    shutil.rmtree(d / 'results', ignore_errors=True)
    (d / 'case.sif').write_text(text, encoding='utf-8', newline='\n')
    print('[built] %s   conductivity->1e-12, Resistance=%s' % (name, TEST_R))
    print('        Resistance lines:')
    for i, ln in enumerate(text.splitlines(), 1):
        if 'Resistance' in ln or 'Electric Conductivity' in ln:
            print('          %4d: %s' % (i, ln))
    return d


dirs = [build('N25_L040_cu_closed', 'probeF_N25'),
        build('N1_L040_cu_closed', 'probeF_N1')]

for d in dirs:
    log = d / 'local.log'
    with open(log, 'w') as fh:
        p = subprocess.Popen([str(ELMER), 'case.sif'], cwd=str(d),
                             stdout=fh, stderr=subprocess.STDOUT)
    print('[launched] %s  pid=%d' % (d.name, p.pid))

print()
print('waiting for both ...')
for d in dirs:
    pass

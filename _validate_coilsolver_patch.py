"""Local dry-run of the awk SIF transformation used by hpc/test_coilsolver_v2.sh.

There is no awk on this Windows box, so this script ports the awk rules
BACK to Python one-for-one, in the same precedence order, and asserts the
result.  It does not replace running the shell script (that also exercises
ElmerSolver), it only proves the line surgery is correct BEFORE spending an
HPC allocation on it -- the same mistake that wasted job 122245457 (variant
D, killed by CoilSolver.F90:140 because our SIF pre-set `Coil Start`).

Run:  python _validate_coilsolver_patch.py
"""
import sys
from pathlib import Path

SRC = Path('hpc/cases/N25_L040_cu_closed/case.sif')
# optional: --write <dir> <source-case-dir>  (defaults to the N25 case)
if len(sys.argv) > 2 and sys.argv[1] == '--write' and len(sys.argv) > 3:
    SRC = Path(sys.argv[3]) / 'case.sif'
    if not SRC.exists():
        sys.exit('no such source SIF: %s' % SRC)
print('[src] %s' % SRC)

out = []
ins8 = v8 = done8 = insc = 0
nst = nen = nb = neq = 0
ineq1 = eq1done = 0
bodynr = 0

for line in SRC.read_text(encoding='utf-8').splitlines():
    # 0b. Equation 1 must carry the solver's Equation string as a LOGICAL KEY
    #     (MainUtils.F90:1622-1636), else AddEquationBasics Fatals with
    #     "Variable > coiltmp < exists but it is not associated to any
    #      equation".  Confirmed locally: renaming the solver's string to the
    #     block Name does NOT work, adding this key DOES.
    if line == 'Equation 1':
        ineq1 = 1
    if ineq1 and not eq1done and line.startswith('  Name = '):
        out.append(line)
        out.append('  Wire direction = Logical True')
        eq1done = 1
        continue
    # 1. Solver 8: Wsolve -> CoilSolver
    if line == '  Procedure = "WPotentialSolver" "Wsolve"':
        out.append('  Procedure = "CoilSolver" "CoilSolver"')
        continue
    # arm the Solver-8 rules at its Equation line
    if line == '  Equation = "Wire direction"':
        ins8 = 1
    # 2. Solver 8: DELETE `Variable = W` -- CoilSolver sets its own scratch
    #    variable (F90:73) and exports CoilPot/CoilPotB itself (F90:75-88).
    if line == '  Variable = W':
        if ins8 and not v8:
            v8 = 1
            continue
    # 3. normalisation keys, inserted after Solver 8's CG line
    if line.startswith('  Linear System Iterative Method = CG'):
        out.append(line)
        if ins8 and not done8:
            out += [
                '  Normalize Coil Current = Logical True',
                '  Fix Input Current Density = True',
                # NO `Coil Closed` -- verified locally that setting it makes
                # CoilSolver fail with "Scaling of potential failed!" because
                # it assumes a cut-free closed loop and our coil has a radial
                # slit.  `Electrode Boundaries` fully specifies the cut-mode
                # path instead, and with it the whole solve runs.
                '  Narrow Interface = Logical True',
                '  Save Coil Set = Logical True',
                '  Save Coil Index = Logical True',
                '  Calculate Elemental Fields = Logical True',
                '  Nonlinear System Consistent Norm = True',
            ]
            done8 = 1
        continue
    # 4. Component 1: CoilSolver keys (Coil Normal HERE, never in the solver)
    if line.startswith('  Number of Turns = Real'):
        out.append(line)
        if insc == 0:
            out += [
                '  Coil Use W Vector = Logical True',
                '  W Vector Variable Name = String "CoilCurrent e"',
                '  ! CoilSolver.F90:358-359 Fatals if Coil Normal is also in',
                '  ! the SOLVER section -- it must live here, on the component.',
                '  Coil Normal(3) = Real 0.0 0.0 1.0',
                '  Desired Current Density = Real 1',
                '  Electrode Area = Real 1',
            ]
            insc = 1
        continue
    # 5. CoilSolver owns Coil Start / Coil End -> strip our pre-set ones
    if line == '  Coil Start = Logical True':
        nst += 1
        continue
    if line == '  Coil End = Logical True':
        nen += 1
        continue
    # 6. Equation split (NO `next` in awk either -- the Body line is printed)
    if line.startswith('Body ') and line[5:].strip().isdigit():
        bodynr = int(line.split()[1])
    if line == '  Equation = 1' and bodynr > 1:
        out.append('  Equation = 2')
        nb += 1
        continue
    if line == '  Active Solvers(10) = 5 6 7 8 1 9 2 3 10 11':
        out.append('  Active Solvers(9) = 5 6 7 1 9 2 3 10 11')
        neq += 1
        continue
    # 7. 30 steps
    if line.startswith('  Timestep Intervals'):
        out.append('  Timestep Intervals     = 30')
        continue
    out.append(line)


text = '\n'.join(out) + '\n'
text += """
! ============================================================
!  Equation 2 -- added by test_coilsolver_v2.sh
!    Everything EXCEPT Body 1.  CoilSolver (Solver 8) deliberately
!    absent: CoilSolver.F90:387 Fatals when a body that is active in an
!    Equation carrying CoilSolver does not belong to a Component.
!    Identical to Equation 1 minus Solver 8.  Numbered 2, not 4, because
!    Elmer requires the numbered Equation blocks to be contiguous.
! ============================================================
Equation 2
  Name = "MagneticsNoCoilSolver"
  Active Solvers(9) = 5 6 7 1 9 2 3 10 11
  Mesh Update = Logical True
End
"""

print('[counters] variable=%d keys=%d strippedCoilStart=%d strippedCoilEnd=%d '
      'bodiesToEq4=%d eq1Trimmed=%d' % (v8, done8, nst, nen, nb, neq))

fails = []
if not done8:
    fails.append('Solver 8 normalisation keys not inserted')
if not v8:
    fails.append('Solver 8 `Variable = W` line not removed')
if 'Variable = CoilPot' in text:
    fails.append('Variable = CoilPot must NOT be set -- CoilSolver.F90:73 owns '
                 'the solver Variable (-nooutput CoilTmp) and F90:75-88 '
                 'exports CoilPot/CoilPotB as separate fields')
if '  Variable = W' in text:
    fails.append('Variable = W still present')
if insc != 1:
    fails.append('Component 1 CoilSolver keys not inserted exactly once')
if nst != 1 or nen != 1:
    fails.append('Coil Start/End not stripped exactly once each')
if nb != 2:
    fails.append('expected Body 2 + Body 3 moved to Equation 4, got %d' % nb)
if neq != 1:
    fails.append('Equation 1 Active Solvers not trimmed')
if 'Body 2' not in text or 'Body 3' not in text:
    fails.append('a Body line was swallowed')
if text.count('Procedure = "CoilSolver" "CoilSolver"') != 1:
    fails.append('CoilSolver procedure not present exactly once')
if text.count('"WPotentialSolver" "Wsolve"') != 0:
    fails.append('Wsolve still referenced')
if text.count('  Coil Normal(3) = Real') != 1:
    fails.append('Coil Normal must appear EXACTLY once as an active key '
                 '(component only); comment mentions do not count')
if text.count('  Coil Start = Logical True') != 0:
    fails.append('Coil Start still present')
if text.count('  Coil End = Logical True') != 0:
    fails.append('Coil End still present')
if text.count('Active Solvers(9) = 5 6 7 1 9 2 3 10 11') != 2:
    fails.append('expected the trimmed solver list in Equation 1 AND 4')
if text.count('  Equation = 2') != 2:
    fails.append('expected exactly two bodies on Equation 2')
if text.count('  Coil Closed = Logical True') != 0:
    fails.append('Coil Closed must NOT be set -- it asks for the no-cuts '
                 'closed-loop treatment and our coil has a radial slit; with '
                 'it CoilSolver dies with "Scaling of potential failed!"')
if text.count('  Wire direction = Logical True') != 1:
    fails.append('Equation 1 must carry `Wire direction = Logical True` '
                 '(MainUtils.F90:1633)')
if text.count('  Equation = 4') != 0:
    fails.append('Equation 4 must not appear -- numbered Equations must be '
                 'contiguous (Elmer: "Entry missing for: Equation 2")')
if text.count('\nEquation 1\n') != 1 or text.count('\nEquation 2\n') != 1:
    fails.append('expected exactly one Equation 1 block and one Equation 2 block')

print()
print('=== resulting key lines ===')
keys = ('Procedure =', 'Variable =', 'Normalize Coil Current', 'Fix Input',
        'Coil Closed', 'Narrow Interface', 'Save Coil Set', 'Save Coil Index',
        'Calculate Elemental Fields', 'Nonlinear System Consistent',
        'Number of Turns', 'Coil Use W Vector', 'W Vector Variable',
        'Coil Normal', 'Desired Current Density', 'Electrode Area',
        'Active Solvers', 'Body ', 'Equation =', 'Coil Start', 'Coil End',
        'Timestep Intervals')
for i, ln in enumerate(text.splitlines(), 1):
    if any(k in ln for k in keys):
        print('  %4d: %s' % (i, ln))

# --- optional: dump the transformed SIF so a LOCAL ElmerSolver can be run ---
#     (this box has elmer262/bin/ElmerSolver.exe plus CoilSolver.dll, so the
#      SIF can be iterated on locally instead of burning HPC allocations)
if len(sys.argv) > 2 and sys.argv[1] == '--write':
    dest = Path(sys.argv[2])
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'case.sif').write_text(text, encoding='utf-8', newline='\n')
    print('[wrote] %s  (%d B)' % (dest / 'case.sif', len(text)))

print()
if fails:
    print('[FAIL] ' + '\n       '.join(fails))
    sys.exit(1)
print('[OK] all assertions passed')


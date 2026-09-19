"""Find apostrophes / backticks inside the single-quoted awk program of
hpc/test_coilsolver_v2.sh.

A single quote anywhere inside the awk program CLOSES the shell's single
quoted string early, so the following text is re-tokenised and awk tries to
open it as a FILE:

    awk: fatal: cannot open file `CoilTmp)

That is exactly how HPC job 122248196 silently produced a 14-line SIF from a
561-line source, while the locally-run Python port of the same transformation
was fine.  This checker makes the class of bug impossible to miss.
"""
from pathlib import Path

p = Path(__file__).resolve().parent / 'hpc' / 'test_coilsolver_v2.sh'
lines = p.read_text(encoding='utf-8').splitlines()

start = end = None
for i, ln in enumerate(lines):
    if ln.rstrip() == "  awk '":
        start = i
    if start is not None and end is None and i > start and "' \"$SRC/case.sif\"" in ln:
        end = i

print('awk program spans lines %d..%d of %s'
      % (start + 1, (end or start) + 1, p.name))
# The terminator line legitimately contains one closing quote; skip it.
last = end if end is not None else len(lines) - 1
bad = 0
for i in range(start + 1, last):
    ln = lines[i]
    if "'" in ln:
        print('  line %d: %s' % (i + 1, ln))
        bad += 1
print()
if bad:
    print('[FAIL] %d apostrophe(s) inside the awk program -- a single quote '
          'closes the shell string, awk then opens the rest as a FILE and '
          'silently writes an empty output' % bad)
else:
    print('[OK] no apostrophes inside the awk program')
    print('     (backticks are harmless inside a single-quoted shell string,'
          ' but they are best avoided too)')

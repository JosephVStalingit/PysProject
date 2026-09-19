#!/usr/bin/env python3
"""patch_diag_sif.py -- rewrite the N-dependent knobs in a copy of the N25
case.sif, to build diagnostic cases.

Usage:
    patch_diag_sif.py <sif> <sigma_eff> <turns> <N_j>

Patches, each exactly once where it matters:
  * the FIRST `Electric Conductivity = <not 1e-12>`  (Material 1 = coil)
  * every `Number of Turns = Real <n>`
  * every `Stranded Coil N_j = Real <x>`             (Component 1 + Body Force 3)
"""
import sys, re

p, sig, turns, nj = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(p, encoding='utf-8').read()

s, n1 = re.subn(r'(?m)^(  Electric Conductivity\s*=\s*)(?!1\.0e-12)\S+',
                lambda m: m.group(1) + sig, s, count=1)
s, n2 = re.subn(r'(?m)^(  Number of Turns\s*=\s*Real\s*)\S+',
                lambda m: m.group(1) + turns, s)
s, n3 = re.subn(r'(?m)^(  Stranded Coil N_j\s*=\s*Real\s*)\S+',
                lambda m: m.group(1) + nj, s)

ok = (n1 == 1 and n2 >= 1 and n3 >= 1)
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print('  patched sigma=%d turns=%d Nj=%d' % (n1, n2, n3))
if not ok:
    print('  [err] patch incomplete')
    sys.exit(1)
# echo the result for verification
for ln in s.split('\n'):
    if re.match(r'^  (Electric Conductivity|Number of Turns|Stranded Coil N_j)',
                ln):
        print('    ' + ln)

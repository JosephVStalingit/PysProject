import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_val')


def col(case, j, sub='rl'):
    p = os.path.join(BASE, case, sub, 'results', 'circuit.csv')
    t, out = [], []
    for line in open(p, encoding='utf-8', errors='replace'):
        f = line.split()
        if len(f) >= 17:
            try:
                t.append(float(f[6]))
                out.append(float(f[j]))
            except ValueError:
                pass
    return t, out


# open circuit: the load dominates, so eps = i * R_total
t_o, i_o = col('L_open', 9)
r_load_open = 1.0e6
t_s, i_s = col('L_short', 9)

print(f'  open  rows={len(i_o)}  peak |i| = {max(abs(x) for x in i_o):.4e} A')
print(f'  short rows={len(i_s)}  peak |i| = {max(abs(x) for x in i_s):.4e} A')
print(f'  eps_open peak = {max(abs(x) for x in i_o)*r_load_open:.4f} V')
print()

# i_short(t) = (1/L) * INT_0^t eps_open(s) ds   ->   L = INT eps / i_short
rows = min(len(t_o), len(t_s))
integ = 0.0
print('   step   t(s)      eps_open(V)   INT-eps(V.s)   i_short(A)    L_implied(H)')
for n in range(rows):
    if n > 0:
        dt = t_o[n] - t_o[n - 1]
        integ += 0.5 * (i_o[n] + i_o[n - 1]) * r_load_open * dt
    if (n + 1) % 6 == 0 or n == rows - 1:
        eps = i_o[n] * r_load_open
        Lv = integ / i_s[n] if abs(i_s[n]) > 1e-30 else float('nan')
        print(f'   {n+1:>4}  {t_o[n]:<9.4f} {eps:+.4e}   {integ:+.4e}   '
              f'{i_s[n]:+.4e}  {Lv:.4e}')

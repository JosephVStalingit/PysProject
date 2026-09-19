"""Pretty-print the physical dimensions and material parameters."""
import io, json

d = json.load(open('config.json', encoding='utf-8'))


def show(path, key, fmt='', unit=''):
    p = d
    for k in path.split('.'):
        p = p[k]
    if isinstance(p, dict):
        out = ', '.join(f'{k}={v}' for k, v in p.items() if not isinstance(v, dict))
    elif isinstance(p, (int, float)):
        out = (fmt or '{}').format(p)
    else:
        out = str(p)
    print(f'  {key:<34} {out} {unit}')


print('=== 1. 磁体  ===')
show('magnet', 'M (磁化强度 M_mag_A_per_m)', '{:.0e}', 'A/m')
show('magnet', 'R_mag (半径)',             '{:.0f}', 'mm')
show('magnet', 'H_mag (半高)',             '{:.1f}', 'mm')
show('magnet', 'z0 / z1 (底/顶高程)',     '{:.3f} / {:.3f}', 'm')

print()
print('=== 2. 线圈骨架 (bore former) ===')
show('coil', 'r_inner (内径)',             '{:.0f}', 'mm')
show('coil', 'r_outer (外径)',             '{:.0f}', 'mm')
show('coil', 'z0 / z1 (底/顶高程)',       '{:.3f} / {:.3f}', 'm')
show('coil', 'slit_width (径向切口宽度)', '{:.0f}', 'mm')

print()
print('=== 3. 弹簧 (阻尼谐振子) ===')
show('spring', 'stiffness (刚度 k)',  '{:.0f}', 'N/m')
show('spring', 'damping (阻尼 c)',    '{:.2f}', 'N*s/m')
show('spring', 'mass (质量 m)',       '{:.2f}', 'kg')
show('spring', 'z_eq / z_release (平衡/释放高程)', '{:.3f} / {:.3f}', 'm')

print()
print('=== 4. 空气域 (远场) ===')
show('geometry', 'R_air (半径)',       '{:.3f}', 'm')
show('geometry', 'air z0 / z1 (底/顶高程)', '{:.3f} / {:.3f}', 'm')

print()
print('=== 5. 六条曲线参数 ===')
print(f'  {"curve":<26}{"N":>5}{"R_load":>10}{"wire_d_mm":>11}{"sigma S/m":>14}')
for n, c in d['curves'].items():
    if not isinstance(c, dict):
        continue
    sig = c.get('wire_conductivity_S_per_m')
    dw = c.get('wire_diameter_m') or 0
    sig = c.get('wire_conductivity_S_per_m') or 0
    print(f'  {n:<26}{c.get("N_turns",""):>5}{c.get("R_load_ohm",""):>10}'
          f'{dw*1e3:>11.2f}{sig:>14.2e}')

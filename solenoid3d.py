"""
solenoid3d.py  --  Build the magnet-free-fall mesh.

Usage (CLI):
    python solenoid3d.py                       # default: --config no-coil
    python solenoid3d.py --config no-coil
    python solenoid3d.py --config copper-tube
    python solenoid3d.py --config stranded-coil

Three configurations differ only in Body 1 (the bore region):
  no-coil       :  Body 1 = "AirInside"  (just empty air inside the bore)
  copper-tube   :  Body 1 = "CopperTube"  (solid conductor)
  stranded-coil :  Body 1 = "StrandedCoil" (geometry identical to
                   copper-tube, but flagged as a stranded coil for
                   Elmer circuit coupling)

Geometry layout (units in metres):  -- magnet-free-fall (no spring/anchor)

  Z = +0.110  AirDomain top   (magnet release plane)
  Z = +0.090 +---------------+  magnet top
              |    Magnet    |  Body 2, R=15mm, H=30mm
  Z = +0.060  magnet bottom
  Z = +0.040 +---------------+  coil/bore region top
              |    Body 1    |  depends on --config
  Z =  0.000  coil/bore region middle
  Z = -0.040  coil/bore region bottom
  Z = -0.080  AirDomain bottom

(See config.json -> geometry / magnet / coil for full source-of-truth.)
"""
from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
import gmsh


# ---- Default dimensions (m); overridden by config.json if present ----
CFG_PATH = Path(__file__).with_name("config.json")


def _load_config() -> dict:
    if CFG_PATH.is_file():
        with open(CFG_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


_C = _load_config()


def _geom(key, default):
    return _C.get("geometry", {}).get(key, default)


def _mesh(key, default):
    return _C.get("mesh", {}).get(key, default)


def _mag(key, default):
    return _C.get("magnet", {}).get(key, default)


# ---- Dimensions (m) ----
R_MAG    = _mag("R_mag_m",  0.015)
MAG_Z0   = _mag("z0_m",     0.060)
MAG_Z1   = _mag("z1_m",     0.090)
R_AIR    = _geom("R_air_m", 0.080)
AIR_Z0   = _geom("air_z0_m",-0.080)
AIR_Z1   = _geom("air_z1_m", 0.110)
S_OUT    = 0.025
S_IN     = 0.020
S_Z0     = 0.000
S_Z1     = 0.040
# spring + anchor are no longer used (free-fall experiment);
# kept here as no-op to avoid breaking imports
SPR_R_OUT = 0.008
SPR_R_IN  = 0.006
SPR_Z0   = 0.092
SPR_Z1   = 0.099
ANCH_Z0  = 0.099
ANCH_Z1  = 0.101


def cyl(r, z0, z1):
    return gmsh.model.occ.addCylinder(0, 0, z0, 0, 0, z1 - z0, r)


def parse_args():
    # --config choices come from config.json [curves] block.
    # Each curve carries its own `sif_suffix` -> geometry variant.
    import json as _json
    cfg = _json.load(open('config.json', encoding='utf-8'))
    suffixes = [cfg['curves'][k]['sif_suffix'] for k in cfg['curves']]
    default  = suffixes[0] if suffixes else 'no-coil'
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', default='model3d.msh')
    ap.add_argument('--config', choices=suffixes, default=default,
                    help='geometry variant (from config.json [curves])')
    return ap.parse_args()

def build(out_path: str, config: str) -> None:
    gmsh.initialize()
    gmsh.option.setNumber('General.Terminal', 1)
    gmsh.option.setNumber('General.ExpertMode', 1)
    gmsh.model.add('spring_oscillator')

    gmsh.option.setNumber('Mesh.CharacteristicLengthMin', _mesh("lc_min_m", 0.003))
    gmsh.option.setNumber('Mesh.CharacteristicLengthMax', _mesh("lc_max_m", 0.010))

    # ---- primitives ----
    air       = cyl(R_AIR,  AIR_Z0,  AIR_Z1)
    coil_out  = cyl(S_OUT,  S_Z0,   S_Z1)
    coil_in   = cyl(S_IN,   S_Z0,   S_Z1)
    mag       = cyl(R_MAG,  MAG_Z0, MAG_Z1)
    print(f'[debug] cyl tags: air={air}, coil_out={coil_out}, coil_in={coil_in}, '
          f'mag={mag}', file=sys.stderr)

    # ---- bore volume (Body 1) per config (sif_suffix -> body_name from config.json) ----
    # Look up body_name from config.json [curves] so adding a new curve
    # does not require editing this file.
    import json as _json
    cfg = _json.load(open('config.json', encoding='utf-8'))
    sif_to_body = {cfg['curves'][k]['sif_suffix']: cfg['curves'][k]['body_name']
                   for k in cfg['curves']}
    sif_to_n    = {cfg['curves'][k]['sif_suffix']: cfg['curves'][k]['N_turns']
                   for k in cfg['curves']}
    bore_name = sif_to_body.get(config, 'AirInside')
    n_turns   = sif_to_n.get(config, 0)
    if n_turns <= 0 or config == 'no-coil':
        bore_tag = air
    else:                       # coil-like configurations need a hollow cylinder
        bore, _ = gmsh.model.occ.cut(
            [(3, coil_out)], [(3, coil_in)],
            removeObject=True, removeTool=True)
        bore_tag = bore[0][1]

    # ---- fragment everything ----
    # For 'no-coil' we use the air cylinder as the bore; for the
    # other two configs the bore is a separate volume that overlaps
    # the air, so we pass it as well.  Skip duplicates.
    fragment_input = []
    seen = set()
    for v in (air, bore_tag, mag):
        if v not in seen:
            fragment_input.append((3, v))
            seen.add(v)
    fragments, _ = gmsh.model.occ.fragment(
        fragment_input, [], removeObject=True, removeTool=True)
    gmsh.model.occ.synchronize()
    # Re-query surviving volume tags AFTER synchronize (gmsh renumbers them)
    all_dim_tags = gmsh.model.getEntities(dim=3)

    # ---- classify by bounding box ----
    coil_vols, mag_vols, air_vols = [], [], []

    for dim, tag in all_dim_tags:
        if dim != 3:
            continue
        bbox = gmsh.model.getBoundingBox(dim, tag)
        xmin, ymin, zmin, xmax, ymax, zmax = bbox
        rmax = max(abs(xmin), abs(xmax), abs(ymin), abs(ymax))

        if (rmax < R_MAG + 1e-4 and MAG_Z0 - 1e-4 < zmin
              and zmax < MAG_Z1 + 1e-4):
            mag_vols.append(tag)
        elif (S_Z0 - 1e-4 < zmin and zmax < S_Z1 + 1e-4
              and rmax < S_OUT + 1e-4):
            coil_vols.append(tag)
        else:
            air_vols.append(tag)

    assert coil_vols, f'no coil/air-bore volumes for {config}'
    assert mag_vols,  'no magnet volumes classified'

    # ---- physical groups ----
    gmsh.model.addPhysicalGroup(3, coil_vols,  tag=1, name=bore_name)
    gmsh.model.addPhysicalGroup(3, mag_vols,   tag=2, name='Magnet')
    gmsh.model.addPhysicalGroup(3, air_vols,   tag=3, name='Air')

    # ---- boundaries ----
    outer = []
    for t in air_vols:
        for dim, tag in gmsh.model.getBoundary([(3, t)], combined=False, oriented=False):
            if dim != 2:
                continue
            bb = gmsh.model.getBoundingBox(2, tag)
            if bb[2] < AIR_Z0 + 1e-4 and bb[5] > AIR_Z1 - 1e-4:
                outer.append(tag)
    gmsh.model.addPhysicalGroup(2, outer, tag=1001, name='MagneticInfinity')

    # ---- per-volume mesh size ----
    def size(tags, lc):
        for t in tags:
            gmsh.model.mesh.setSize(
                gmsh.model.getBoundary([(3, t)], combined=False, oriented=False), lc)
    size(coil_vols, _mesh("lc_coil_m", 0.0012))
    size(mag_vols + air_vols, _mesh("lc_others_m", 0.004))

    # ---- write ----
    # Generate a true first-order mesh so ElmerGrid can
    # promote it to native second order (type 510 / 306)
    # via its `-increase` flag.  Note: gmsh 4.x with HXT
    # 3D algorithm (default) often leaves boundary nodes
    # at order 2 even when Mesh.ElementOrder=1, so we also
    # switch to the legacy Frontal-Delaunay algorithm for
    # both surface and volume meshes.
    gmsh.option.setNumber('Mesh.ElementOrder', 1)
    gmsh.option.setNumber('Mesh.SecondOrderIncomplete', 1)
    gmsh.option.setNumber('Mesh.HighOrderOptimize', 0)
    gmsh.option.setNumber('Mesh.Algorithm', 6)        # Frontal-Delaunay 2D
    gmsh.option.setNumber('Mesh.Algorithm3D', 4)     # MMG3D 3D (legacy)
    gmsh.option.setNumber('Mesh.MshFileVersion', 2.2)
    gmsh.option.setNumber('Mesh.Format', 1)
    gmsh.model.mesh.generate(3)
    gmsh.write(out_path)
    gmsh.finalize()

    print(f'[ok] wrote {out_path}')
    print(f'     config        : {config}')
    print(f'     experiment    : magnet free fall (no spring, no anchor)')
    print(f'     coil-bore vols: {len(coil_vols)} ({bore_name})')
    print(f'     magnet vols   : {len(mag_vols)}')
    print(f'     air vols      : {len(air_vols)}')
    print(f'     outer surface : {len(outer)} faces')


def main():
    args = parse_args()
    try:
        build(args.out, args.config)
    except Exception as exc:
        print(f'[err] {exc}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

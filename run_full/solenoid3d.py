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
def _find_config() -> Path:
    """Prefer ./config.json so a STUDY CASE DIRECTORY can override the
    geometry, and only fall back to the copy sitting next to this script.

    Using `Path(__file__).with_name(...)` unconditionally would silently
    ignore the case config, which makes every sweep produce an identical
    mesh."""
    here = Path("config.json")
    if here.is_file():
        return here
    return Path(__file__).with_name("config.json")


CFG_PATH = _find_config()


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


def _coil(key, default):
    """Coil/bore geometry. config.json -> [coil] is the single source of
    truth; it is the SAME block the oscilloscope uses to integrate the flux,
    so geometry and post-processing can never drift apart."""
    return _C.get("coil", {}).get(key, default)


# ---- Dimensions (m) ----
R_MAG    = _mag("R_mag_m",  0.015)
MAG_Z0   = _mag("z0_m",     0.060)
MAG_Z1   = _mag("z1_m",     0.090)
R_AIR    = _geom("R_air_m", 0.080)
AIR_Z0   = _geom("air_z0_m",-0.080)
AIR_Z1   = _geom("air_z1_m", 0.110)
S_OUT    = _coil("r_outer_m", 0.025)
S_IN     = _coil("r_inner_m", 0.020)
S_Z0     = _coil("z0_m",      0.000)
S_Z1     = _coil("z1_m",      0.040)
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
    # Several curves usually SHARE one suffix (copper/aluminium open+closed all
    # use the same winding geometry), so de-duplicate while keeping the order:
    # `dict.fromkeys` is order-preserving.
    # Skip non-dict entries (e.g. `_comment_block`) so a top-level comment
    # can live in [curves] without breaking iteration.
    import json as _json
    cfg = _json.load(open('config.json', encoding='utf-8'))
    suffixes = list(dict.fromkeys(v['sif_suffix']
                                  for v in cfg['curves'].values()
                                  if isinstance(v, dict)
                                  and v.get('sif_suffix')))
    default  = suffixes[0] if suffixes else 'no-coil'
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--out', default='model3d.msh')
    ap.add_argument('--config', choices=suffixes, default=default,
                    help='geometry variant (from config.json [curves]); '
                         f'curves: {", ".join(k for k, v in cfg["curves"].items() if isinstance(v, dict))}')
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
    # Use the SAME parsed config as the geometry helpers above (_C), otherwise
    # the body names could come from a different file than the dimensions.
    # Same isinstance guard as in parse_args() so a [curves]._comment_block
    # doc entry does not corrupt these maps.
    cfg = _C
    sif_to_body = {v['sif_suffix']: v['body_name']
                   for v in cfg['curves'].values() if isinstance(v, dict)}
    sif_to_n    = {v['sif_suffix']: v['N_turns']
                   for v in cfg['curves'].values() if isinstance(v, dict)}
    bore_name = sif_to_body.get(config, 'AirInside')
    n_turns   = sif_to_n.get(config, 0)

    # ---- THE SLIT RESOLUTION GATE (hpc/notes.md 15.11) -------------------
    # A closed-circuit run is only stable when ONE element spans the slit.
    # If lc_slit_m < slit_width_m the gap is meshed with real elements and the
    # coupled A / circuit / W-potential problem develops a self-amplifying
    # mode: the coil current is multiplied by a CONSTANT factor EVERY timestep
    # until the run overflows.  Measured per-step gains on the 3.5 mm slit:
    #
    #     lc_slit_m   per-step gain   elements   verdict
    #     2.5 mm      1.777           30698      exploded by t = 9 ms
    #     3.0 mm      3.30            26375      worse
    #     3.5 mm      1.199           21650      marginal
    #     4.0 mm      ~1.000          18743      stable
    #     8.0 mm      <1              12456      stable
    #
    # Nothing else moves this: dt (1 ms vs 2 ms), R_load (10 vs 100 ohm), the
    # magnet's motion (frozen vs moving) and the scalar-vs-vector W route were
    # ALL tested and changed nothing.  And the failure is SILENT -- the solver
    # exits 0 and writes a plausible-looking results/circuit.csv -- so it has
    # to be caught here, at mesh generation, not at solve time.
    slit_w = _coil("slit_width_m", 0.0015)
    lc_slit = _mesh("lc_slit_m", 0.0012)
    if n_turns > 0 and lc_slit < slit_w:
        raise SystemExit(
            f"[err] lc_slit_m = {lc_slit*1e3:.2f} mm is SMALLER than "
            f"slit_width_m = {slit_w*1e3:.2f} mm.\n"
            f"      That meshes the slit with more than one element and makes\n"
            f"      the closed-circuit transient self-amplify without limit.\n"
            f"      Set lc_slit_m >= slit_width_m in config.json [mesh].\n"
            f"      See hpc/notes.md 15.11."
        )
    slit_tools = []
    if n_turns <= 0 or config == 'no-coil':
        bore_tag = air
    else:                       # coil-like configurations need a hollow cylinder
        bore, _ = gmsh.model.occ.cut(
            [(3, coil_out)], [(3, coil_in)],
            removeObject=True, removeTool=True)

        # ---- radial slit -------------------------------------------------
        # WPotentialSolver conducts W along the coil's WIRE direction: its
        # local tensor is diag(0,0,1) and is rotated by RotM only when
        # CoilType /= 'massive'.  The W = 0 / W = 1 pair must therefore sit
        # on two faces SEPARATED ALONG THE WIRE.  A solenoid's wire runs in
        # theta, so those two faces are the sides of a radial slit -- the
        # top/bottom disks the previous version tagged are z-normal and can
        # only ever produce an AXIAL current.  See hpc/notes.md 13.12.
        #
        # The box is kept (removeTool=False) so it can be handed to the
        # fragment below: without that the slit is a VOID belonging to no
        # volume, and the mesh would simply have a hole through the coil.
        # Its boundary is coplanar with the coil's (z = S_Z0/S_Z1 planes,
        # x = S_OUT face) so the fragment produces no slivers.
        slit_gap = _coil("slit_width_m", 0.0015)
        slit_box = gmsh.model.occ.addBox(
            0.0, -0.5 * slit_gap, S_Z0,
            S_OUT, slit_gap, S_Z1 - S_Z0)
        cut, _ = gmsh.model.occ.cut(
            [(3, bore[0][1])], [(3, slit_box)],
            removeObject=True, removeTool=False)
        bore_tag = cut[0][1]
        slit_tools.append(slit_box)
        print(f'[debug] radial slit: width={slit_gap * 1e3:.3f} mm, '
              f'tool tag={slit_box}', file=sys.stderr)

    # ---- fragment everything ----
    # For 'no-coil' we use the air cylinder as the bore; for the
    # other two configs the bore is a separate volume that overlaps
    # the air, so we pass it as well.  Skip duplicates.
    fragment_input = []
    seen = set()
    for v in (air, bore_tag, mag, *slit_tools):
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
              and rmax < S_OUT + 1e-4
              and (xmax - xmin) > 2 * S_OUT - 1e-3):
            # A real annulus spans the FULL diameter in x.  The radial-slit
            # tool is a slab from x = 0 to x = S_OUT, so its x-extent is only
            # S_OUT and this test rejects it -- otherwise the slit volume
            # would satisfy every other condition and be swallowed into the
            # coil body, silently removing the slit from the model.
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

    # ---- magnet surface (needed for mesh-motion boundary conditions) ----
    mag_srf = []
    for t in mag_vols:
        for dim, tag in gmsh.model.getBoundary([(3, t)], combined=False,
                                                oriented=False):
            if dim == 2:
                mag_srf.append(tag)
    gmsh.model.addPhysicalGroup(2, mag_srf, tag=1002, name='MagnetSurface')

    # ---- coil faces for the stranded-coil circuit ----
    #
    # WPotentialSolver conducts W along the coil's WIRE direction (its local
    # tensor is diag(0,0,1), rotated by RotM when CoilType /= 'massive'), so
    # the `W = 0` / `W = 1` pair must sit on two faces SEPARATED ALONG THE
    # WIRE.  For a solenoid the wire runs in theta, hence the radial slit
    # cut above; its two faces are CoilStart / CoilEnd.
    #
    # The four original faces then serve the Alpha/Beta direction solves
    # that build RotM, i.e. the local frame
    #     alpha = r-hat   <- inner / outer cylinder
    #     beta  = z-hat   <- bottom / top disk
    #     gamma = alpha x beta = -theta-hat  <- the wire direction
    #
    # All six faces are consumed -- exactly as in upstream
    # `fem/tests/circuits_transient_stranded`, whose coil is a six-sided
    # block.  See hpc/notes.md 13.12.
    #
    # Physical group tags 1003/1004 keep their names (CoilStart/CoilEnd),
    # but they now refer to the SLIT, not to the top/bottom disks.  The four
    # new groups take 1005..1008.
    a_in, a_out, b_bot, b_top = [], [], [], []
    coil_start_srf, coil_end_srf = [], []
    if n_turns > 0:
        for t in coil_vols:
            for dim, tag in gmsh.model.getBoundary([(3, t)], combined=False,
                                                    oriented=False):
                if dim != 2:
                    continue
                bb = gmsh.model.getBoundingBox(2, tag)
                dx, dy, dz = bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2]

                if dz <= 1e-6:
                    # z-normal flat disk -> beta: the two flat end disks
                    # give the axial direction of the local frame.
                    z_mid = 0.5 * (bb[2] + bb[5])
                    (b_bot if abs(z_mid - S_Z0) < 1e-4
                     else b_top).append(tag)
                elif dy <= 1e-6:
                    # planar and y-normal -> one side of the radial slit.
                    # Which side gets W=1 vs W=0 only fixes the SIGN of the
                    # induced current, which is physically arbitrary.
                    (coil_start_srf if bb[1] < 0.0
                     else coil_end_srf).append(tag)
                else:
                    # cylindrical (r = const) -> alpha.  Inner boundary is
                    # alpha = 0, outer is alpha = 1, so the frame goes
                    # radially outward.
                    r_face = 0.5 * max(dx, dy)
                    (a_in if r_face < 0.5 * (S_IN + S_OUT)
                     else a_out).append(tag)

        for tag, name in ((1003, 'CoilStart'), (1004, 'CoilEnd'),
                          (1005, 'Alpha0'), (1006, 'Alpha1'),
                          (1007, 'Beta0'), (1008, 'Beta1')):
            grp = {1003: coil_start_srf, 1004: coil_end_srf,
                   1005: a_in, 1006: a_out,
                   1007: b_bot, 1008: b_top}[tag]
            if grp:
                gmsh.model.addPhysicalGroup(2, grp, tag=tag, name=name)
        print(f'[debug] coil faces: CoilStart={len(coil_start_srf)} '
              f'CoilEnd={len(coil_end_srf)} Alpha0={len(a_in)} '
              f'Alpha1={len(a_out)} Beta0={len(b_bot)} Beta1={len(b_top)}',
              file=sys.stderr)
        if not (coil_start_srf and coil_end_srf):
            raise SystemExit('[err] radial slit produced no face pair -- the '
                             'stranded coil cannot be built.  Check '
                             'slit_width_m in config.json [coil].')

    # ---- per-volume mesh size ----
    # NOTE: with `General.ExpertMode = 1` gmsh only honours mesh-size
    # constraints given on POINTS, so we collect the corner points of each
    # volume's boundary (recursively) and set the size there.
    # The LAST call wins for points shared between volumes, so we apply the
    # COARSE size first and let the fine sizes override it.
    def size(tags, lc):
        pts, seen = [], set()
        for t in tags:
            for dim, tag in gmsh.model.getBoundary(
                    [(3, t)], combined=False, oriented=False, recursive=True):
                if dim == 0 and tag not in seen:
                    pts.append((0, tag))
                    seen.add(tag)
        if pts:
            gmsh.model.mesh.setSize(pts, lc)

    size(air_vols,  _mesh("lc_others_m", 0.010))
    size(mag_vols,  _mesh("lc_magnet_m", 0.0025))
    size(coil_vols, _mesh("lc_coil_m",   0.0025))
    # The radial slit LAST so its finer size wins: the slit is ~1.5 mm wide
    # while lc_coil_m is 8 mm, so without this the mesher would step straight
    # over it and W would have no face pair to jump between.  See
    # hpc/notes.md 13.12.
    if slit_tools:
        size(slit_tools, _mesh("lc_slit_m", 0.0012))

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
    print(f'     magnet surface: {len(mag_srf)} faces')


def main():
    args = parse_args()
    try:
        build(args.out, args.config)
    except Exception as exc:
        print(f'[err] {exc}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

"""``FloorPlan`` → DXF (pianta 2D su layer + modello 3D) e OBJ (solo 3D).

DXF R2010 in metri ($INSUNITS = 6): si apre in AutoCAD, BricsCAD, DraftSight,
ArchiCAD, Revit, LibreCAD (il 2D) e si converte in DWG con qualsiasi CAD.
Il 3D è fatto di mesh POLYFACE (le più compatibili fra i CAD):

* muri estrusi da 0 all'altezza ``wall_height_m``;
* sopra le porte un architrave da ``DOOR_HEIGHT_M``; sotto/sopra le finestre
  parapetto fino a ``SILL_HEIGHT_M`` e architrave da ``WINDOW_TOP_M``;
* pavimento: sagoma con spessore ``SLAB_M`` sotto quota 0.
"""
from __future__ import annotations

import io
from typing import Dict, Iterable, List, Sequence, Tuple

from app.core.planimetria import FloorPlan, Point

DOOR_HEIGHT_M = 2.10
SILL_HEIGHT_M = 0.90
WINDOW_TOP_M = 2.20
SLAB_M = 0.20

Vec3 = Tuple[float, float, float]
Face = List[Vec3]

LAYERS = {
    # nome: (colore ACI, descrizione)
    "PA_MURI": (7, "Muri (pianta)"),
    "PA_APERTURE_PORTE": (3, "Porte"),
    "PA_APERTURE_FINESTRE": (5, "Finestre"),
    "PA_VANI": (8, "Vani"),
    "PA_TESTI": (2, "Superfici dei vani"),
    "PA_SAGOMA": (1, "Sagoma lorda"),
    "PA_3D_MURI": (7, "Muri 3D"),
    "PA_3D_APERTURE": (4, "Architravi e parapetti 3D"),
    "PA_3D_PAVIMENTO": (9, "Pavimento 3D"),
}


# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------
def _clean(ring: Sequence[Point]) -> List[Point]:
    out: List[Point] = []
    for p in ring:
        if not out or (abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6):
            out.append((float(p[0]), float(p[1])))
    if len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def _signed_area(ring: Sequence[Point]) -> float:
    return 0.5 * sum(
        ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1]
        for i in range(len(ring))
    )


def extrude(outer: Sequence[Point], holes: Iterable[Sequence[Point]], z0: float, z1: float) -> List[Face]:
    """Prisma da poligono con fori: facce con normali verso l'esterno."""
    from ezdxf.math.triangulation import mapbox_earcut_2d

    outer = _clean(outer)
    holes = [h for h in (_clean(h) for h in holes) if len(h) >= 3]
    if len(outer) < 3 or abs(_signed_area(outer)) < 1e-6 or z1 <= z0:
        return []
    if _signed_area(outer) < 0:
        outer = outer[::-1]  # esterno antiorario
    holes = [h if _signed_area(h) < 0 else h[::-1] for h in holes]  # fori orari

    faces: List[Face] = []
    for tri in mapbox_earcut_2d(outer, holes or None):
        pts = [(float(v.x), float(v.y)) for v in tri]
        if len(pts) != 3:
            continue
        if _signed_area(pts) < 0:
            pts = pts[::-1]
        faces.append([(x, y, z1) for x, y in pts])  # sopra, verso +z
        faces.append([(x, y, z0) for x, y in pts[::-1]])  # sotto, verso -z
    for ring in [outer, *holes]:
        for i in range(len(ring)):
            (ax, ay), (bx, by) = ring[i], ring[(i + 1) % len(ring)]
            faces.append([(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)])
    return faces


def build_mesh(plan: FloorPlan) -> Dict[str, List[Face]]:
    """Gruppi di facce 3D: ``muri``, ``aperture``, ``pavimento``."""
    h = plan.wall_height_m
    walls: List[Face] = []
    for poly in plan.walls:
        walls += extrude(poly.outer, poly.holes, 0.0, h)
    openings: List[Face] = []
    for op in plan.openings:
        if op.kind == "porta":
            ranges = [(min(DOOR_HEIGHT_M, h - 0.05), h)]
        else:
            ranges = [(0.0, SILL_HEIGHT_M), (min(WINDOW_TOP_M, h - 0.05), h)]
        for z0, z1 in ranges:
            openings += extrude(op.polygon, [], z0, z1)
    floor: List[Face] = []
    for poly in plan.footprint:
        floor += extrude(poly.outer, poly.holes, -SLAB_M, 0.0)
    return {"muri": walls, "aperture": openings, "pavimento": floor}


# ---------------------------------------------------------------------------
# DXF
# ---------------------------------------------------------------------------
def _fmt_area(value: float) -> str:
    return f"{value:.2f}".replace(".", ",") + " m²"


def to_dxf(plan: FloorPlan, title: str = "Planimetria") -> bytes:
    import ezdxf
    from ezdxf import units
    from ezdxf.render import MeshBuilder

    doc = ezdxf.new("R2010", setup=True)
    doc.units = units.M
    doc.header["$INSUNITS"] = units.M
    doc.header["$MEASUREMENT"] = 1  # metrico
    for name, (color, desc) in LAYERS.items():
        layer = doc.layers.add(name, color=color)
        layer.description = desc
    msp = doc.modelspace()

    for poly in plan.walls:
        rings = [_clean(poly.outer)] + [_clean(h) for h in poly.holes]
        rings = [r for r in rings if len(r) >= 3]
        if not rings:
            continue
        for ring in rings:
            msp.add_lwpolyline(ring, close=True, dxfattribs={"layer": "PA_MURI"})
        hatch = msp.add_hatch(color=256, dxfattribs={"layer": "PA_MURI"})
        hatch.set_solid_fill(color=256)
        for i, ring in enumerate(rings):
            hatch.paths.add_polyline_path(ring, is_closed=True, flags=1 if i == 0 else 16)

    for poly in plan.footprint:
        msp.add_lwpolyline(_clean(poly.outer), close=True, dxfattribs={"layer": "PA_SAGOMA"})

    for op in plan.openings:
        layer = "PA_APERTURE_PORTE" if op.kind == "porta" else "PA_APERTURE_FINESTRE"
        msp.add_lwpolyline(_clean(op.polygon), close=True, dxfattribs={"layer": layer})

    for room in plan.rooms:
        msp.add_lwpolyline(_clean(room.polygon), close=True, dxfattribs={"layer": "PA_VANI"})
        text = _fmt_area(room.area_m2)
        if room.label:
            text = f"{room.label}\\P{text}"
        mtext = msp.add_mtext(text, dxfattribs={"layer": "PA_TESTI", "char_height": 0.25})
        mtext.set_location(room.label_point, attachment_point=5)  # middle center

    layers3d = {"muri": "PA_3D_MURI", "aperture": "PA_3D_APERTURE", "pavimento": "PA_3D_PAVIMENTO"}
    for group, faces in build_mesh(plan).items():
        if not faces:
            continue
        mesh = MeshBuilder()
        for face in faces:
            mesh.add_face(face)
        mesh.render_polyface(msp, dxfattribs={"layer": layers3d[group]})

    doc.set_modelspace_vport(height=max(10.0, plan.stats.perimeter_m / 3), center=_center(plan))
    doc.header["$PROJECTNAME"] = title[:100]
    stream = io.StringIO()
    doc.write(stream)
    return stream.getvalue().encode("utf-8")


def _center(plan: FloorPlan) -> Point:
    pts = [p for poly in plan.footprint for p in poly.outer] or [(0.0, 0.0)]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)


# ---------------------------------------------------------------------------
# OBJ
# ---------------------------------------------------------------------------
def to_obj(plan: FloorPlan, title: str = "Planimetria") -> bytes:
    """Wavefront OBJ in metri, convenzione Y in alto (x, z, -y)."""
    lines = [
        f"# {title} - PreApe (estrazione automatica dalla planimetria, da verificare)",
        "# unita: metri, asse Y verso l'alto",
    ]
    index: Dict[Vec3, int] = {}
    body: List[str] = []
    for group, faces in build_mesh(plan).items():
        if not faces:
            continue
        body.append(f"g {group}")
        for face in faces:
            ids = []
            for x, y, z in face:
                key = (round(x, 4), round(z, 4), round(-y, 4))
                if key not in index:
                    index[key] = len(index) + 1
                    lines.append(f"v {key[0]:.4f} {key[1]:.4f} {key[2]:.4f}")
                ids.append(str(index[key]))
            body.append("f " + " ".join(ids))
    return ("\n".join(lines + body) + "\n").encode("utf-8")

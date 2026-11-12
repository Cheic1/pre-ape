"""Planimetria → geometria vettoriale, DXF/OBJ e API /documents/{id}/cad."""
import base64
import io

import ezdxf
import numpy as np
import pytest

from conftest import create_survey
from planimetria_fixtures import (
    EXPECTED_GROSS_M2,
    EXPECTED_ROOMS_M2,
    plan_pdf,
    plan_png,
    plan_scanned_jpeg,
)

from app.core.planimetria import CadParams, NoWallsFound, extract_floor_plan
from app.core.planimetria.export import LAYERS, build_mesh, extrude, to_dxf, to_obj
from app.core.planimetria.raster import find_scale

PDF = "application/pdf"


@pytest.fixture(scope="module")
def plan():
    return extract_floor_plan(plan_pdf(), PDF)


class TestExtraction:
    def test_scale_read_from_pdf_text(self, plan):
        assert plan.scale_denominator == 200
        assert plan.warnings == []

    def test_rooms_and_areas(self, plan):
        areas = [r.area_m2 for r in plan.rooms]
        assert len(areas) == 3
        for got, expected in zip(areas, EXPECTED_ROOMS_M2):
            assert got == pytest.approx(expected, rel=0.03)
        assert plan.stats.gross_area_m2 == pytest.approx(EXPECTED_GROSS_M2, rel=0.02)
        assert plan.stats.perimeter_m == pytest.approx(36.0, rel=0.02)

    def test_openings(self, plan):
        doors = [o for o in plan.openings if o.kind == "porta"]
        windows = [o for o in plan.openings if o.kind == "finestra"]
        assert len(doors) == 2 and len(windows) == 4
        assert all(not d.exterior for d in doors)
        assert all(w.exterior for w in windows)
        assert all(w.width_m == pytest.approx(1.2, abs=0.05) for w in windows)
        assert all(d.width_m == pytest.approx(0.9, abs=0.05) for d in doors)

    def test_coordinates_in_metres_from_origin(self, plan):
        xs = [p[0] for p in plan.footprint[0].outer]
        ys = [p[1] for p in plan.footprint[0].outer]
        assert min(xs) == pytest.approx(0, abs=0.05) and max(xs) == pytest.approx(10, abs=0.05)
        assert min(ys) == pytest.approx(0, abs=0.05) and max(ys) == pytest.approx(8, abs=0.05)

    def test_png_with_dpi(self):
        plan = extract_floor_plan(plan_png(), "image/png")
        assert plan.stats.rooms == 3
        assert any("Scala non trovata" in w for w in plan.warnings)

    def test_scanned_jpeg(self):
        plan = extract_floor_plan(plan_scanned_jpeg(), "image/jpeg")
        assert (plan.stats.rooms, plan.stats.doors, plan.stats.windows) == (3, 2, 4)
        for got, expected in zip([r.area_m2 for r in plan.rooms], EXPECTED_ROOMS_M2):
            assert got == pytest.approx(expected, rel=0.03)

    def test_scale_override(self):
        plan = extract_floor_plan(plan_pdf(), PDF, CadParams(scale_denominator=100))
        assert plan.stats.gross_area_m2 == pytest.approx(EXPECTED_GROSS_M2 / 4, rel=0.02)

    def test_meters_per_px_calibration(self, plan):
        calibrated = extract_floor_plan(
            plan_pdf(), PDF, CadParams(meters_per_px=plan.meters_per_px * 1.1, wall_height_m=3.0)
        )
        assert calibrated.scale_denominator is None
        assert calibrated.wall_height_m == 3.0
        assert calibrated.stats.perimeter_m == pytest.approx(1.1 * plan.stats.perimeter_m, rel=0.01)
        assert calibrated.stats.rooms == 3

    def test_blank_page_has_no_walls(self):
        from fpdf import FPDF

        pdf = FPDF()
        pdf.add_page()
        with pytest.raises(NoWallsFound):
            extract_floor_plan(bytes(pdf.output()), PDF)

    def test_bad_pdf(self):
        with pytest.raises(ValueError):
            extract_floor_plan(b"%PDF-1.4 rotto", PDF)

    def test_find_scale(self):
        assert find_scale("Planimetria  SCALA 1 : 100  foglio") == 100
        assert find_scale("scala di 1/500") == 500
        assert find_scale("nessuna") is None
        assert find_scale("scala 1:5") is None


class TestExport:
    def test_extrude_is_closed_box(self):
        faces = extrude([(0, 0), (2, 0), (2, 1), (0, 1)], [], 0, 3)
        # 2 triangoli sopra + 2 sotto + 4 lati
        assert len(faces) == 8
        # volume col teorema della divergenza (normali coerenti verso l'esterno)
        vol = 0.0
        for f in faces:
            for i in range(1, len(f) - 1):
                a, b, c = (np.array(f[0]), np.array(f[i]), np.array(f[i + 1]))
                vol += np.dot(a, np.cross(b, c)) / 6
        assert vol == pytest.approx(6.0)

    def test_extrude_with_hole(self):
        faces = extrude([(0, 0), (4, 0), (4, 4), (0, 4)], [[(1, 1), (3, 1), (3, 3), (1, 3)]], 0, 1)
        vol = 0.0
        for f in faces:
            for i in range(1, len(f) - 1):
                a, b, c = (np.array(f[0]), np.array(f[i]), np.array(f[i + 1]))
                vol += np.dot(a, np.cross(b, c)) / 6
        assert vol == pytest.approx(12.0)

    def test_dxf_layers_and_audit(self, plan):
        doc = ezdxf.read(io.StringIO(to_dxf(plan).decode()))
        assert len(doc.audit().errors) == 0
        assert doc.header["$INSUNITS"] == 6
        layers = {e.dxf.layer for e in doc.modelspace()}
        assert {"PA_MURI", "PA_VANI", "PA_APERTURE_PORTE", "PA_APERTURE_FINESTRE",
                "PA_3D_MURI", "PA_3D_APERTURE", "PA_3D_PAVIMENTO"} <= layers
        assert layers <= set(LAYERS)
        texts = [e.text for e in doc.modelspace().query("MTEXT")]
        assert any("m²" in t for t in texts)

    def test_wall_height_in_3d(self, plan):
        zs = [v[2] for f in build_mesh(plan)["muri"] for v in f]
        assert max(zs) == pytest.approx(plan.wall_height_m)
        assert min(zs) == 0

    def test_obj(self, plan):
        obj = to_obj(plan).decode()
        assert "g muri" in obj and "g aperture" in obj
        n_v = sum(1 for line in obj.splitlines() if line.startswith("v "))
        faces = [line.split()[1:] for line in obj.splitlines() if line.startswith("f ")]
        assert faces and all(1 <= int(i) <= n_v for f in faces for i in f)


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
def _upload(client, headers, sid, data, kind="planimetria", filename="pianta.pdf"):
    response = client.post(
        f"/api/v1/surveys/{sid}/documents",
        json={"kind": kind, "filename": filename,
              "content_base64": base64.b64encode(data).decode()},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()["id"]


class TestApi:
    def test_extract_and_download(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid, plan_pdf())

        assert client.get(f"/api/v1/documents/{doc_id}/cad", headers=headers).status_code == 404
        assert client.get(f"/api/v1/documents/{doc_id}/cad.dxf", headers=headers).status_code == 404

        response = client.post(f"/api/v1/documents/{doc_id}/cad", headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["stats"]["rooms"] == 3
        assert body["scale_denominator"] == 200

        meta = client.get(f"/api/v1/surveys/{sid}/documents", headers=headers).json()[0]
        assert meta["cad_stats"]["rooms"] == 3

        stored = client.get(f"/api/v1/documents/{doc_id}/cad", headers=headers).json()
        assert stored["stats"] == body["stats"]

        dxf = client.get(f"/api/v1/documents/{doc_id}/cad.dxf", headers=headers)
        assert dxf.status_code == 200
        assert "pianta_cad.dxf" in dxf.headers["content-disposition"]
        assert ezdxf.read(io.StringIO(dxf.text)).modelspace().query("HATCH")

        obj = client.get(f"/api/v1/documents/{doc_id}/cad.obj", headers=headers)
        assert obj.status_code == 200 and obj.text.startswith("#")

    def test_re_extract_with_params(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid, plan_pdf())
        response = client.post(
            f"/api/v1/documents/{doc_id}/cad",
            json={"scale_denominator": 100, "wall_height_m": 3.1},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        assert response.json()["wall_height_m"] == 3.1
        assert response.json()["stats"]["gross_area_m2"] == pytest.approx(20, rel=0.02)
        bad = client.post(f"/api/v1/documents/{doc_id}/cad", json={"scala": 100}, headers=headers)
        assert bad.status_code == 422

    def test_only_planimetria(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid, plan_pdf(), kind="altro")
        response = client.post(f"/api/v1/documents/{doc_id}/cad", headers=headers)
        assert response.status_code == 422

    def test_no_walls_422(self, client, auth_a):
        from fpdf import FPDF

        headers, _ = auth_a
        sid = create_survey(client, headers)
        pdf = FPDF()
        pdf.add_page()
        doc_id = _upload(client, headers, sid, bytes(pdf.output()))
        response = client.post(f"/api/v1/documents/{doc_id}/cad", headers=headers)
        assert response.status_code == 422
        assert "muro" in response.json()["detail"]

    def test_other_user_404(self, client, auth_a, auth_b):
        headers, _ = auth_a
        headers_b, _ = auth_b
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid, plan_pdf())
        assert client.post(f"/api/v1/documents/{doc_id}/cad", headers=headers_b).status_code == 404
        assert client.post(f"/api/v1/documents/{doc_id}/cad", headers=headers).status_code == 200
        for suffix in ("cad", "cad.dxf", "cad.obj"):
            r = client.get(f"/api/v1/documents/{doc_id}/{suffix}", headers=headers_b)
            assert r.status_code == 404

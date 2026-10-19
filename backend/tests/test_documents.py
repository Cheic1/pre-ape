"""Documenti catastali: upload/elenco/download/cancellazione (app.api.v1.documents)."""
import base64
import uuid

from conftest import create_survey
from test_visura import VISURA_SINGOLA, _visura_pdf

from app.models.database import SessionLocal, SurveyDocument

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32
PDF = b"%PDF-1.4\n%fake\n"


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode()


def _upload(client, headers, survey_id, data=PNG, kind="planimetria", filename="pianta.png"):
    return client.post(
        f"/api/v1/surveys/{survey_id}/documents",
        json={"kind": kind, "filename": filename, "content_base64": _b64(data)},
        headers=headers,
    )


class TestUpload:
    def test_upload_png(self, client, auth_a):
        headers, user_id = auth_a
        sid = create_survey(client, headers)
        response = _upload(client, headers, sid)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["survey_id"] == sid
        assert body["kind"] == "planimetria"
        assert body["filename"] == "pianta.png"
        assert body["mime_type"] == "image/png"
        assert body["size_bytes"] == len(PNG)
        assert body["uploaded_by"]["id"] == user_id
        assert body["uploaded_by"]["email"].endswith("@example.test")
        assert body["extracted"] is None
        assert "content" not in body and "content_base64" not in body

    def test_mime_from_magic_bytes_not_name(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        body = _upload(client, headers, sid, data=JPEG, filename="foto.pdf").json()
        assert body["mime_type"] == "image/jpeg"
        body = _upload(client, headers, sid, data=PDF, kind="mappa", filename="x.png").json()
        assert body["mime_type"] == "application/pdf"

    def test_unsupported_type_415(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        gif = b"GIF89a" + b"\x00" * 16
        assert _upload(client, headers, sid, data=gif, filename="a.gif").status_code == 415
        text = b"Visura catastale (testo, non PDF)"
        assert _upload(client, headers, sid, data=text, filename="v.pdf").status_code == 415
        assert _upload(client, headers, sid, data=b"", filename="vuoto.pdf").status_code == 415

    def test_bad_base64_422(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        response = client.post(
            f"/api/v1/surveys/{sid}/documents",
            json={"kind": "altro", "filename": "a.pdf", "content_base64": "%%%non-base64%%%"},
            headers=headers,
        )
        assert response.status_code == 422

    def test_body_validation_422(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        url = f"/api/v1/surveys/{sid}/documents"
        good = {"kind": "altro", "filename": "a.png", "content_base64": _b64(PNG)}
        for bad in (
            {**good, "kind": "contratto"},
            {**good, "filename": ""},
            {**good, "filename": "x" * 256},
            {**good, "mime_type": "image/png"},  # extra="forbid"
        ):
            assert client.post(url, json=bad, headers=headers).status_code == 422, bad

    def test_too_large_413(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        big = b"%PDF-" + b"\x00" * (10 * 1024 * 1024)
        assert _upload(client, headers, sid, data=big, filename="big.pdf").status_code == 413

    def test_max_documents_409(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        for i in range(10):
            assert _upload(client, headers, sid, filename=f"{i}.png").status_code == 201
        assert _upload(client, headers, sid, filename="11.png").status_code == 409

    def test_requires_auth(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        assert _upload(client, {}, sid).status_code == 401

    def test_other_users_survey_404(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        sid = create_survey(client, headers_a)
        assert _upload(client, headers_b, sid).status_code == 404
        assert _upload(client, headers_a, str(uuid.uuid4())).status_code == 404


class TestVisuraExtraction:
    def test_visura_pdf_is_parsed(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        pdf = _visura_pdf(VISURA_SINGOLA)
        response = _upload(client, headers, sid, data=pdf, kind="visura", filename="visura.pdf")
        assert response.status_code == 201, response.text
        extracted = response.json()["extracted"]
        assert len(extracted) == 1
        unit = extracted[0]
        assert unit["foglio"] == "351" and unit["particella"] == "125"
        assert unit["subalterno"] == "12" and unit["categoria"] == "A/2"
        assert unit["rendita_euro"] == 1032.91
        # persisted: visible in the listing too
        listed = client.get(f"/api/v1/surveys/{sid}/documents", headers=headers).json()
        assert listed[0]["extracted"] == extracted

    def test_visura_unreadable_pdf_gives_empty_list(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        response = _upload(client, headers, sid, data=PDF, kind="visura", filename="v.pdf")
        assert response.status_code == 201
        assert response.json()["extracted"] == []

    def test_visura_image_not_parsed(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        response = _upload(client, headers, sid, data=JPEG, kind="visura", filename="v.jpg")
        assert response.status_code == 201
        assert response.json()["extracted"] is None

    def test_non_visura_pdf_not_parsed(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        pdf = _visura_pdf(VISURA_SINGOLA)
        response = _upload(client, headers, sid, data=pdf, kind="planimetria", filename="p.pdf")
        assert response.json()["extracted"] is None


class TestListDownloadDelete:
    def test_list_oldest_first(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        first = _upload(client, headers, sid, filename="a.png").json()["id"]
        second = _upload(client, headers, sid, data=PDF, kind="mappa", filename="b.pdf").json()["id"]
        rows = client.get(f"/api/v1/surveys/{sid}/documents", headers=headers)
        assert rows.status_code == 200
        assert [r["id"] for r in rows.json()] == [first, second]
        assert rows.json()[0]["uploaded_by"]["name"] == "Test user_a"

    def test_list_empty_and_404(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        sid = create_survey(client, headers_a)
        assert client.get(f"/api/v1/surveys/{sid}/documents", headers=headers_a).json() == []
        assert client.get(f"/api/v1/surveys/{sid}/documents", headers=headers_b).status_code == 404
        assert client.get(f"/api/v1/surveys/{sid}/documents").status_code == 401

    def test_download(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid, data=PDF, kind="mappa", filename="mappa è.pdf").json()["id"]
        response = client.get(f"/api/v1/documents/{doc_id}/content", headers=headers)
        assert response.status_code == 200
        assert response.content == PDF
        assert response.headers["content-type"] == "application/pdf"
        assert response.headers["content-disposition"].startswith("attachment;")
        assert "mappa%20%C3%A8.pdf" in response.headers["content-disposition"]

    def test_download_delete_other_user_404(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        sid = create_survey(client, headers_a)
        doc_id = _upload(client, headers_a, sid).json()["id"]
        assert client.get(f"/api/v1/documents/{doc_id}/content", headers=headers_b).status_code == 404
        assert client.delete(f"/api/v1/documents/{doc_id}", headers=headers_b).status_code == 404
        assert client.get(f"/api/v1/documents/{uuid.uuid4()}/content", headers=headers_a).status_code == 404
        # still there for the owner
        assert client.get(f"/api/v1/documents/{doc_id}/content", headers=headers_a).status_code == 200

    def test_delete(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid).json()["id"]
        assert client.delete(f"/api/v1/documents/{doc_id}", headers=headers).status_code == 204
        assert client.get(f"/api/v1/surveys/{sid}/documents", headers=headers).json() == []
        assert client.delete(f"/api/v1/documents/{doc_id}", headers=headers).status_code == 404
        # a slot is freed after delete
        assert _upload(client, headers, sid).status_code == 201

    def test_survey_delete_cascades(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        doc_id = _upload(client, headers, sid).json()["id"]
        assert client.delete(f"/api/v1/surveys/{sid}", headers=headers).status_code == 204
        with SessionLocal() as db:
            assert db.get(SurveyDocument, uuid.UUID(doc_id)) is None
        assert client.get(f"/api/v1/documents/{doc_id}/content", headers=headers).status_code == 404

    def test_survey_payload_has_no_documents(self, client, auth_a):
        headers, _ = auth_a
        sid = create_survey(client, headers)
        _upload(client, headers, sid)
        body = client.get(f"/api/v1/surveys/{sid}", headers=headers).json()
        assert "documents" not in body

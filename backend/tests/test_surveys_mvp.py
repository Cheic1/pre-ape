"""SaaS MVP: survey list, inline photos, server-side scoring, status, delete."""
import base64

import pytest

from conftest import create_survey

API = "/api/v1/surveys"


def _jpeg(size: int = 64) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(b"\xff" * size).decode()


class TestSurveyList:
    def test_list_empty(self, client, auth_a):
        headers, _ = auth_a
        response = client.get(API, headers=headers)
        assert response.status_code == 200
        assert response.json() == []

    def test_list_requires_auth(self, client):
        assert client.get(API).status_code == 401

    def test_list_only_own_newest_first(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        first = create_survey(client, headers_a, title="Rossi")
        second = create_survey(client, headers_a, title="Bianchi")
        create_survey(client, headers_b, title="Altro utente")
        # touching the first one moves it to the top
        client.put(f"{API}/{first}", json={"notes": "aggiornato"}, headers=headers_a)

        rows = client.get(API, headers=headers_a).json()
        assert [r["id"] for r in rows] == [first, second]
        assert {r["title"] for r in rows} == {"Rossi", "Bianchi"}

    def test_list_has_no_photo_payload(self, client, auth_a):
        headers, _ = auth_a
        create_survey(client, headers, photos={"Facciata": _jpeg()}, additional_photos=[_jpeg()])
        row = client.get(API, headers=headers).json()[0]
        assert row["photo_count"] == 2
        assert "photos" not in row and "additional_photos" not in row


class TestSurveyFields:
    def test_roundtrip_header_notes_photos(self, client, auth_a):
        headers, _ = auth_a
        photo = _jpeg()
        survey_id = create_survey(
            client,
            headers,
            title="Pratica 12/2026",
            client_name="Mario Rossi",
            notes="Caldaia in cantina",
            photos={"Facciata": photo},
            additional_photos=[photo, photo],
        )
        data = client.get(f"{API}/{survey_id}", headers=headers).json()
        assert data["title"] == "Pratica 12/2026"
        assert data["client_name"] == "Mario Rossi"
        assert data["notes"] == "Caldaia in cantina"
        assert data["photos"] == {"Facciata": photo}
        assert data["additional_photos"] == [photo, photo]
        results = client.get(f"{API}/{survey_id}/results", headers=headers).json()
        assert results["photo_count"] == 3

    def test_score_computed_on_create_and_update(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers, square_meters=100.0)
        created = client.get(f"{API}/{survey_id}", headers=headers).json()
        assert created["estimated_class"] == created["energy_result"]["classe"]
        assert created["energy_score"] == created["energy_result"]["punteggio"]
        updated = client.put(
            f"{API}/{survey_id}",
            json={"building": {
                "comune": "Milano", "anno_costruzione": 2018, "tipologia": "appartamento",
                "piano": "intermedio", "telaio": "PVC", "vetro": "Triplo",
                "generatore": "pompa_calore_aria_acqua", "terminali": "pavimento",
            }},
            headers=headers,
        ).json()
        assert updated["climate_zone"] == "E"
        assert updated["energy_result"]["clima"]["comune"]["comune"] == "Milano"
        assert updated["energy_score"] > created["energy_score"]
        assert updated["building"]["generatore"] == "pompa_calore_aria_acqua"

    def test_status_complete_and_null_keeps_value(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        done = client.put(f"{API}/{survey_id}", json={"status": "completed"}, headers=headers)
        assert done.json()["status"] == "completed"
        kept = client.put(f"{API}/{survey_id}", json={"status": None}, headers=headers)
        assert kept.json()["status"] == "completed"

    def test_invalid_status_rejected(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(API, json={"status": "deleted"}, headers=headers)
        assert response.status_code == 422


class TestPhotoValidation:
    @pytest.mark.parametrize(
        "bad",
        [
            "data:text/html;base64,PGgxPng8L2gxPg==",
            "https://evil.example/x.jpg",
            "javascript:alert(1)",
            "data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=",  # SVG can carry scripts
        ],
    )
    def test_rejects_non_raster_images(self, client, auth_a, bad):
        headers, _ = auth_a
        r1 = client.post(API, json={"photos": {"Facciata": bad}}, headers=headers)
        r2 = client.post(API, json={"additional_photos": [bad]}, headers=headers)
        assert r1.status_code == 422
        assert r2.status_code == 422

    def test_rejects_oversized_photo(self, client, auth_a):
        headers, _ = auth_a
        huge = "data:image/jpeg;base64," + "A" * 1_000_001
        response = client.post(API, json={"photos": {"Facciata": huge}}, headers=headers)
        assert response.status_code == 422

    def test_rejects_too_many_additional(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(API, json={"additional_photos": [_jpeg()] * 7}, headers=headers)
        assert response.status_code == 422

    def test_body_size_limit(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(
            API,
            content=b"x" * (16 * 1024 * 1024 + 1),
            headers={**headers, "Content-Type": "application/json"},
        )
        assert response.status_code == 413


class TestDelete:
    def test_delete_survey_with_photo_analyses(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        analysis = client.post(
            "/api/v1/photo-analyses",
            json={"survey_id": survey_id, "photo_type": "caldaia", "file_path": "x.jpg"},
            headers=headers,
        )
        assert analysis.status_code == 201
        assert client.delete(f"{API}/{survey_id}", headers=headers).status_code == 204
        assert client.get(f"{API}/{survey_id}", headers=headers).status_code == 404

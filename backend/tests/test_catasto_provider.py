"""Accesso al Catasto via fornitore (app.core.catasto.provider + app.api.v1.catasto)."""
import json

import pytest

from conftest import create_survey
from test_visura import VISURA_SINGOLA, _visura_pdf

from app.core.catasto import provider as providers
from app.core.config import settings

PDF = b"%PDF-1.4\n%fake\n"


class FakeHttp:
    """Finto catasto.openapi.it: registra le chiamate e risponde da una tabella."""

    def __init__(self, pdf=PDF):
        self.calls = []
        self.stato = "in_erogazione"
        self.esito = None
        self.pdf = pdf
        self.fail_submit = None

    def __call__(self, method, url, body, headers):
        self.calls.append((method, url, body, headers))
        path = url.split(".openapi.it", 1)[1]
        if method == "POST":
            if self.fail_submit:
                return self.fail_submit, "application/json", json.dumps({"success": False, "message": "no"}).encode()
            return 200, "application/json", json.dumps(
                {"success": True, "data": {"id": "abc123", "stato": "in_erogazione"}}
            ).encode()
        if path.endswith("/documento"):
            return 200, "application/pdf", self.pdf
        return 200, "application/json", json.dumps(
            {"success": True, "data": {"id": "abc123", "stato": self.stato, "esito": self.esito}}
        ).encode()


@pytest.fixture
def fake(monkeypatch):
    http = FakeHttp()
    monkeypatch.setattr(settings, "CATASTO_PROVIDER", "openapi")
    monkeypatch.setattr(settings, "CATASTO_OPENAPI_TOKEN", "tok")
    monkeypatch.setattr(settings, "CATASTO_OPENAPI_SANDBOX", True)
    monkeypatch.setattr(settings, "CATASTO_MONTHLY_LIMIT", 2)
    monkeypatch.setattr(
        providers, "get_provider", lambda: providers.OpenapiCatasto("tok", sandbox=True, http=http)
    )
    return http


REQ = {
    "kind": "visura",
    "provincia": "mi",
    "comune": "MILANO",
    "foglio": "351",
    "particella": "125",
    "subalterno": "12",
    "confirm_cost": True,
}


def test_status_disabled_by_default(client, auth_a):
    headers, _ = auth_a
    body = client.get("/api/v1/catasto/status", headers=headers).json()
    assert body["enabled"] is False and body["prices"] == {}
    sid = create_survey(client, headers)
    r = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers)
    assert r.status_code == 409


def test_status_enabled(client, auth_a, fake):
    headers, _ = auth_a
    body = client.get("/api/v1/catasto/status", headers=headers).json()
    assert body["enabled"] is True and body["provider"] == "openapi" and body["sandbox"] is True
    assert body["prices"]["visura"] == 1.9 and body["used_this_month"] == 0


def test_visura_full_flow(client, auth_a, fake):
    fake.pdf = _visura_pdf(VISURA_SINGOLA)
    headers, _ = auth_a
    sid = create_survey(client, headers)
    r = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers)
    assert r.status_code == 201, r.text
    req = r.json()
    assert req["status"] == "pending" and req["price_eur"] == 1.9
    method, url, body, hdrs = fake.calls[0]
    assert url == "https://test.catasto.openapi.it/visura_catastale"
    assert hdrs["Authorization"] == "Bearer tok"
    assert body == {
        "provincia": "MI", "comune": "MILANO", "foglio": "351", "particella": "125",
        "entita": "immobile", "tipo_catasto": "F", "tipo_visura": "ordinaria",
        "tipo_formato": "pdf", "subalterno": "12",
    }

    # ancora in lavorazione
    r = client.post(f"/api/v1/catasto/requests/{req['id']}/refresh", headers=headers)
    assert r.json()["status"] == "pending"

    fake.stato, fake.esito = "evasa", "OK"
    r = client.post(f"/api/v1/catasto/requests/{req['id']}/refresh", headers=headers)
    done = r.json()
    assert done["status"] == "done" and done["document_id"]

    docs = client.get(f"/api/v1/surveys/{sid}/documents", headers=headers).json()
    assert len(docs) == 1 and docs[0]["kind"] == "visura"
    assert docs[0]["filename"] == "visura_351_125_12.pdf"
    assert docs[0]["extracted"][0]["foglio"] == "351"
    content = client.get(f"/api/v1/documents/{docs[0]['id']}/content", headers=headers)
    assert content.content == fake.pdf

    listed = client.get(f"/api/v1/surveys/{sid}/catasto/requests", headers=headers).json()
    assert [x["id"] for x in listed] == [req["id"]]
    # una richiesta conclusa non richiama il fornitore
    n = len(fake.calls)
    client.post(f"/api/v1/catasto/requests/{req['id']}/refresh", headers=headers)
    assert len(fake.calls) == n


def test_elaborato_planimetrico_body(client, auth_a, fake):
    headers, _ = auth_a
    sid = create_survey(client, headers)
    r = client.post(
        f"/api/v1/surveys/{sid}/catasto/requests",
        json={**REQ, "kind": "elaborato_planimetrico"},
        headers=headers,
    )
    assert r.status_code == 201 and r.json()["price_eur"] == 6.9
    _, url, body, _ = fake.calls[0]
    assert url.endswith("/elaborato_planimetrico")
    assert "subalterno" not in body and "entita" not in body


def test_failed_request(client, auth_a, fake):
    headers, _ = auth_a
    sid = create_survey(client, headers)
    rid = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers).json()["id"]
    fake.stato, fake.esito = "evasa", "IMMOBILE NON TROVATO"
    r = client.post(f"/api/v1/catasto/requests/{rid}/refresh", headers=headers).json()
    assert r["status"] == "failed" and "NON TROVATO" in r["error"]


def test_confirm_cost_required(client, auth_a, fake):
    headers, _ = auth_a
    sid = create_survey(client, headers)
    r = client.post(
        f"/api/v1/surveys/{sid}/catasto/requests", json={**REQ, "confirm_cost": False}, headers=headers
    )
    assert r.status_code == 422
    assert fake.calls == []


def test_monthly_limit(client, auth_a, fake):
    headers, _ = auth_a
    sid = create_survey(client, headers)
    for _ in range(2):
        assert client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers).status_code == 201
    r = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers)
    assert r.status_code == 429


def test_provider_error_502(client, auth_a, fake):
    fake.fail_submit = 402
    headers, _ = auth_a
    sid = create_survey(client, headers)
    r = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers)
    assert r.status_code == 502 and "Credito" in r.json()["detail"]
    listed = client.get(f"/api/v1/surveys/{sid}/catasto/requests", headers=headers).json()
    assert listed == []


def test_other_users_survey_and_request_404(client, auth_a, auth_b, fake):
    headers_a, _ = auth_a
    headers_b, _ = auth_b
    sid = create_survey(client, headers_a)
    assert client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers_b).status_code == 404
    rid = client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers_a).json()["id"]
    assert client.post(f"/api/v1/catasto/requests/{rid}/refresh", headers=headers_b).status_code == 404


def test_survey_delete_cascades(client, auth_a, fake):
    headers, _ = auth_a
    sid = create_survey(client, headers)
    client.post(f"/api/v1/surveys/{sid}/catasto/requests", json=REQ, headers=headers)
    assert client.delete(f"/api/v1/surveys/{sid}", headers=headers).status_code == 204


def test_download_json_base64():
    import base64

    class H(FakeHttp):
        def __call__(self, method, url, body, headers):
            return 200, "application/json", json.dumps({"data": {"file": base64.b64encode(PDF).decode()}}).encode()

    p = providers.OpenapiCatasto("t", http=H())
    assert p.download("visura", "x") == PDF


def test_get_provider_config(monkeypatch):
    monkeypatch.setattr(settings, "CATASTO_PROVIDER", "")
    assert providers.get_provider() is None
    monkeypatch.setattr(settings, "CATASTO_PROVIDER", "openapi")
    monkeypatch.setattr(settings, "CATASTO_OPENAPI_TOKEN", "t")
    monkeypatch.setattr(settings, "CATASTO_OPENAPI_SANDBOX", False)
    assert providers.get_provider().base_url == "https://catasto.openapi.it"
    monkeypatch.setattr(settings, "CATASTO_PROVIDER", "boh")
    with pytest.raises(providers.ProviderError):
        providers.get_provider()

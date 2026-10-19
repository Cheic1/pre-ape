"""Legal layer: accept_terms at registration, terms_accepted on login,
POST /auth/accept-terms and the public GET /legal/{doc} endpoint."""
import uuid

import pytest
from sqlalchemy import text

from app import legal
from app.core.config import settings
from app.models.database import engine
from conftest import TEST_EMAIL_DOMAIN, TEST_PASSWORD


def _email(prefix: str = "legal") -> str:
    return f"{prefix}_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"


def _terms_row(email: str):
    with engine.begin() as conn:
        return conn.execute(
            text("SELECT terms_version, terms_accepted_at FROM users WHERE email = :e"),
            {"e": email},
        ).one()


class TestRegisterAcceptTerms:
    def test_missing_accept_terms_422(self, client):
        response = client.post(
            "/api/v1/auth/register", json={"email": _email(), "password": TEST_PASSWORD}
        )
        assert response.status_code == 422

    @pytest.mark.parametrize("value", [False, "no", None])
    def test_not_true_accept_terms_422(self, client, value):
        email = _email()
        response = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": value},
        )
        assert response.status_code == 422
        with engine.begin() as conn:
            count = conn.execute(
                text("SELECT count(*) FROM users WHERE email = :e"), {"e": email}
            ).scalar()
        assert count == 0

    def test_accept_terms_true_stores_version_and_timestamp(self, client):
        email = _email()
        response = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True},
        )
        assert response.status_code == 201, response.text
        assert response.json()["terms_accepted"] is True
        version, accepted_at = _terms_row(email)
        assert version == legal.LEGAL_VERSION
        assert accepted_at is not None


class TestLoginTermsAccepted:
    def _register(self, client, email):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True},
        )
        assert response.status_code == 201
        return response.json()

    def _login(self, client, email):
        response = client.post(
            "/api/v1/auth/login", json={"email": email, "password": TEST_PASSWORD}
        )
        assert response.status_code == 200, response.text
        return response.json()

    def test_current_version_true(self, client):
        email = _email()
        self._register(client, email)
        assert self._login(client, email)["terms_accepted"] is True

    def test_old_user_without_acceptance_false(self, client):
        email = _email()
        self._register(client, email)
        with engine.begin() as conn:  # user created before the legal layer
            conn.execute(
                text("UPDATE users SET terms_version = NULL, terms_accepted_at = NULL WHERE email = :e"),
                {"e": email},
            )
        assert self._login(client, email)["terms_accepted"] is False

    def test_version_bump_requires_new_acceptance(self, client, monkeypatch):
        email = _email()
        self._register(client, email)
        monkeypatch.setattr(legal, "LEGAL_VERSION", "2099-01-01")
        body = self._login(client, email)
        assert body["terms_accepted"] is False

        headers = {"Authorization": f"Bearer {body['access_token']}"}
        accepted = client.post("/api/v1/auth/accept-terms", headers=headers)
        assert accepted.status_code == 200, accepted.text
        assert accepted.json() == {"terms_accepted": True, "version": "2099-01-01"}
        assert _terms_row(email)[0] == "2099-01-01"
        assert self._login(client, email)["terms_accepted"] is True


class TestAcceptTermsEndpoint:
    def test_requires_auth(self, client):
        assert client.post("/api/v1/auth/accept-terms").status_code == 401

    def test_sets_version_and_timestamp(self, client, auth_a):
        headers, user_id = auth_a
        with engine.begin() as conn:
            conn.execute(
                text("UPDATE users SET terms_version = NULL, terms_accepted_at = NULL WHERE id = :id"),
                {"id": user_id},
            )
        response = client.post("/api/v1/auth/accept-terms", headers=headers)
        assert response.status_code == 200
        assert response.json() == {"terms_accepted": True, "version": legal.LEGAL_VERSION}
        with engine.begin() as conn:
            version, accepted_at = conn.execute(
                text("SELECT terms_version, terms_accepted_at FROM users WHERE id = :id"),
                {"id": user_id},
            ).one()
        assert version == legal.LEGAL_VERSION
        assert accepted_at is not None


_ALL_VALUES = {
    "LEGAL_TITOLARE_NOME": "Studio Rossi S.r.l.",
    "LEGAL_TITOLARE_INDIRIZZO": "Via Roma 1, 20100 Milano",
    "LEGAL_TITOLARE_PIVA_CF": "01234567890",
    "LEGAL_TITOLARE_EMAIL_PRIVACY": "privacy@studiorossi.test",
    "LEGAL_SERVER_UBICAZIONE": "Italia",
    "LEGAL_FORO_COMPETENTE": "Milano",
    "LEGAL_DATA_EFFICACIA": "19/10/2026",
}


class TestLegalEndpoint:
    @pytest.fixture(autouse=True)
    def _empty_settings(self, monkeypatch):
        for setting in legal.PLACEHOLDERS.values():
            monkeypatch.setattr(settings, setting, "")

    @pytest.mark.parametrize("doc", ["privacy", "termini", "dpa"])
    def test_unfilled_placeholders_visible(self, client, doc):
        response = client.get(f"/api/v1/legal/{doc}")  # no auth needed
        assert response.status_code == 200
        body = response.json()
        assert body["doc"] == doc
        assert body["version"] == legal.LEGAL_VERSION
        assert body["title"]
        assert body["complete"] is False
        assert "[da completare: TITOLARE_NOME]" in body["markdown"]
        assert "{{" not in body["markdown"]
        assert legal.LEGAL_VERSION in body["markdown"]

    @pytest.mark.parametrize("doc", ["privacy", "termini", "dpa"])
    def test_filled_placeholders_complete(self, client, monkeypatch, doc):
        for setting, value in _ALL_VALUES.items():
            monkeypatch.setattr(settings, setting, value)
        body = client.get(f"/api/v1/legal/{doc}").json()
        assert body["complete"] is True
        assert "[da completare" not in body["markdown"]
        assert "{{" not in body["markdown"]
        assert "Studio Rossi S.r.l." in body["markdown"]
        assert "Bozza da far verificare" not in body["markdown"]

    def test_partially_filled_is_incomplete(self, client, monkeypatch):
        monkeypatch.setattr(settings, "LEGAL_TITOLARE_NOME", "Studio Rossi S.r.l.")
        body = client.get("/api/v1/legal/privacy").json()
        assert body["complete"] is False
        assert "Studio Rossi S.r.l." in body["markdown"]
        assert "[da completare: TITOLARE_EMAIL_PRIVACY]" in body["markdown"]

    def test_unknown_doc_rejected(self, client):
        assert client.get("/api/v1/legal/cookie").status_code == 422

    def test_documents_use_only_known_placeholders(self):
        import re

        for filename, _title in legal.DOCUMENTS.values():
            source = (legal.LEGAL_DIR / filename).read_text(encoding="utf-8")
            names = set(re.findall(r"\{\{([A-Z_]+)\}\}", source))
            assert names <= set(legal.PLACEHOLDERS) | {"LEGAL_VERSION"}, filename
            assert "Bozza da far verificare a un legale" in source

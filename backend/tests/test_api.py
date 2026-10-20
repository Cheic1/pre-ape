"""Test suite for Pre-APE API (P1-A1 + P1-A2).

Contract rules asserted here — tight, never `422 or 404` (AC-5):
  * path ids are UUIDs -> 422 when malformed, 404 when unknown or unowned;
  * all /surveys and /photo-analyses calls need a valid JWT -> 401 otherwise;
  * IDOR closed (AC-3): user B gets 404 on every operation against user A's survey.
Every test starts from purged state (autouse fixture in conftest.py), so the
suite is independent of execution order and repeatable (AC-4).
"""
import asyncio
import base64
import json
import time
import uuid

import pytest
from jose import jwt
from pydantic import ValidationError
from sqlalchemy import text

import app.core.rate_limit as rate_limit_module
from app.core.config import SECRET_KEY_PLACEHOLDER, Settings, settings
from app.core.security import dummy_verify_async, hash_password, verify_password_async
from app.models.database import engine
from conftest import TEST_EMAIL_DOMAIN, TEST_PASSWORD, create_survey


def _seed_completed_survey(user_id: str) -> str:
    """Insert a completed survey owned by a test user directly in the DB.

    The API cannot set computed fields yet (estimated_class/energy_score are
    read-only), so the results endpoint is tested against a seeded row.
    """
    survey_id = str(uuid.uuid4())
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO surveys (id, user_id, address, square_meters, "
                "estimated_class, energy_score, status, created_at, updated_at) "
                "VALUES (:id, :user_id, 'Via Milano 1', 100.0, 'A3', 95.0, "
                "'completed', now(), now())"
            ),
            {"id": survey_id, "user_id": user_id},
        )
    return survey_id


class TestHealth:
    """Health check tests"""

    def test_root_endpoint(self, client):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["app"] == "Pre-APE API"
        assert data["version"] == "1.0.0"
        assert data["status"] == "running"

    def test_health_endpoint(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data


class TestAuth:
    """JWT register/login endpoints (P1-A1)"""

    def test_register_returns_jwt(self, client):
        email = f"reg_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        response = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True, "name": "Reg User"},
        )
        assert response.status_code == 201, response.text
        data = response.json()
        assert data["token_type"] == "bearer"
        assert isinstance(data["access_token"], str) and data["access_token"]
        assert str(uuid.UUID(data["user_id"])) == data["user_id"]
        assert data["email"] == email
        assert data["name"] == "Reg User"

    def test_register_normalizes_email(self, client):
        email = f"norm_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        response = client.post(
            "/api/v1/auth/register",
            json={"email": f"  {email.upper()}  ", "password": TEST_PASSWORD, "accept_terms": True},
        )
        assert response.status_code == 201, response.text
        assert response.json()["email"] == email
        # name defaults to the email local part when omitted
        assert response.json()["name"] == email.split("@")[0]

    def test_register_duplicate_email_conflict(self, client):
        email = f"dup_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        payload = {"email": email, "password": TEST_PASSWORD, "accept_terms": True}
        first = client.post("/api/v1/auth/register", json=payload)
        assert first.status_code == 201
        second = client.post("/api/v1/auth/register", json=payload)
        assert second.status_code == 409
        assert second.json()["detail"] == "Email already registered"

    def test_register_short_password_rejected(self, client):
        response = client.post(
            "/api/v1/auth/register",
            json={"email": f"weak_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}", "password": "short", "accept_terms": True},
        )
        assert response.status_code == 422

    def test_login_success(self, client):
        email = f"login_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        register = client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True, "name": "Login User"},
        )
        assert register.status_code == 201
        login = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": TEST_PASSWORD},
        )
        assert login.status_code == 200, login.text
        data = login.json()
        assert data["token_type"] == "bearer"
        assert data["user_id"] == register.json()["user_id"]
        assert data["access_token"]

    def test_login_wrong_password(self, client):
        email = f"wrongpw_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        assert client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True},
        ).status_code == 201
        response = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "Definitely-Wrong-1"},
        )
        assert response.status_code == 401
        assert response.json()["detail"] == "Incorrect email or password"
        assert response.headers.get("www-authenticate") == "Bearer"

    def test_login_unknown_email_same_message(self, client):
        """Unknown account and wrong password must be indistinguishable."""
        known = f"known_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        assert client.post(
            "/api/v1/auth/register",
            json={"email": known, "password": TEST_PASSWORD, "accept_terms": True},
        ).status_code == 201
        wrong_pw = client.post(
            "/api/v1/auth/login", json={"email": known, "password": "Definitely-Wrong-1"}
        )
        unknown = client.post(
            "/api/v1/auth/login",
            json={"email": f"ghost_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}", "password": TEST_PASSWORD},
        )
        assert wrong_pw.status_code == 401
        assert unknown.status_code == 401
        assert wrong_pw.json()["detail"] == unknown.json()["detail"]

    def test_surveys_require_auth(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        # no token at all
        response = client.get(f"/api/v1/surveys/{survey_id}")
        assert response.status_code == 401
        assert response.headers.get("www-authenticate") == "Bearer"
        # garbage token
        response = client.get(
            f"/api/v1/surveys/{survey_id}",
            headers={"Authorization": "Bearer not.a.valid.jwt"},
        )
        assert response.status_code == 401

    def test_auth_rate_limit(self, client):
        """Sliding window: 10 requests/min allowed, 11th -> 429 (AC item 4)."""
        ghost = f"flood_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        statuses = []
        for _ in range(11):
            response = client.post(
                "/api/v1/auth/login",
                json={"email": ghost, "password": "Whatever-123"},
            )
            statuses.append(response.status_code)
        assert statuses[:10] == [401] * 10
        assert statuses[10] == 429
        assert response.headers.get("retry-after") == "60"
        # the limiter also blocks register on the same IP window
        blocked = client.post(
            "/api/v1/auth/register",
            json={"email": f"blocked_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}", "password": TEST_PASSWORD, "accept_terms": True},
        )
        assert blocked.status_code == 429


class TestSurveyEndpoints:
    """Survey CRUD endpoint tests (authenticated, owner-only)"""

    SURVEY_DATA = {
        "address": "Via Roma 1, 20100 Milano MI",
        "latitude": 45.4642,
        "longitude": 9.1900,
        "square_meters": 120.0,
        "avg_height": 2.7,
        "climate_zone": "A",
        "wall_thickness": "30-40cm",
        "window_frame": "PVC",
        "window_glass": "Doppio",
        "heating_type": "Pompa di Calore",
        "generator_type": "Caldaia a Condensazione",
        "generator_power_kw": 25.0,
        "generator_year": 2021,
    }

    def test_create_survey(self, client, auth_a):
        headers, user_id = auth_a
        response = client.post("/api/v1/surveys", json=self.SURVEY_DATA, headers=headers)
        assert response.status_code == 201, response.text
        data = response.json()
        assert data["address"] == self.SURVEY_DATA["address"]
        assert data["square_meters"] == self.SURVEY_DATA["square_meters"]
        assert data["generator_year"] == self.SURVEY_DATA["generator_year"]
        assert data["status"] == "draft"
        assert str(uuid.UUID(data["id"])) == data["id"]
        assert "created_at" in data
        assert "user_id" not in data  # owner id is never leaked in the payload

    def test_create_survey_requires_auth(self, client):
        response = client.post("/api/v1/surveys", json={"address": "No auth"})
        assert response.status_code == 401

    def test_get_survey(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        response = client.get(f"/api/v1/surveys/{survey_id}", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert data["id"] == survey_id
        assert data["address"] == "Via Roma 1, 20100 Milano MI"

    def test_get_survey_invalid_uuid(self, client, auth_a):
        headers, _ = auth_a
        response = client.get("/api/v1/surveys/non-existent-id", headers=headers)
        assert response.status_code == 422

    def test_get_survey_not_found(self, client, auth_a):
        headers, _ = auth_a
        response = client.get(f"/api/v1/surveys/{uuid.uuid4()}", headers=headers)
        assert response.status_code == 404
        assert response.json()["detail"] == "Survey not found"

    def test_update_survey(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers, address="Original address")
        response = client.put(
            f"/api/v1/surveys/{survey_id}",
            json={"address": "Updated address", "square_meters": 150.0},
            headers=headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["address"] == "Updated address"
        assert data["square_meters"] == 150.0

    def test_update_survey_invalid_uuid(self, client, auth_a):
        headers, _ = auth_a
        response = client.put(
            "/api/v1/surveys/non-existent-id",
            json={"address": "Test"},
            headers=headers,
        )
        assert response.status_code == 422

    def test_update_survey_not_found(self, client, auth_a):
        headers, _ = auth_a
        response = client.put(
            f"/api/v1/surveys/{uuid.uuid4()}",
            json={"address": "Test"},
            headers=headers,
        )
        assert response.status_code == 404
        assert response.json()["detail"] == "Survey not found"

    def test_delete_survey(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers, address="To be deleted")
        response = client.delete(f"/api/v1/surveys/{survey_id}", headers=headers)
        assert response.status_code == 204
        # verify it is gone for the owner too
        get_response = client.get(f"/api/v1/surveys/{survey_id}", headers=headers)
        assert get_response.status_code == 404
        # deleting twice -> 404
        repeat = client.delete(f"/api/v1/surveys/{survey_id}", headers=headers)
        assert repeat.status_code == 404

    def test_delete_survey_invalid_uuid(self, client, auth_a):
        headers, _ = auth_a
        response = client.delete("/api/v1/surveys/invalid-uuid", headers=headers)
        assert response.status_code == 422


class TestIDOR:
    """AC-3: user B must never read or mutate user A's surveys (404, no oracle)."""

    def test_idor_get_survey(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)

        as_b = client.get(f"/api/v1/surveys/{survey_id}", headers=headers_b)
        assert as_b.status_code == 404
        assert as_b.json()["detail"] == "Survey not found"

        as_a = client.get(f"/api/v1/surveys/{survey_id}", headers=headers_a)
        assert as_a.status_code == 200

    def test_idor_update_survey(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a, address="Original address")

        as_b = client.put(
            f"/api/v1/surveys/{survey_id}",
            json={"address": "HACKED by B"},
            headers=headers_b,
        )
        assert as_b.status_code == 404

        # A's data untouched
        as_a = client.get(f"/api/v1/surveys/{survey_id}", headers=headers_a)
        assert as_a.status_code == 200
        assert as_a.json()["address"] == "Original address"

    def test_idor_delete_survey(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)

        as_b = client.delete(f"/api/v1/surveys/{survey_id}", headers=headers_b)
        assert as_b.status_code == 404

        as_a = client.get(f"/api/v1/surveys/{survey_id}", headers=headers_a)
        assert as_a.status_code == 200  # still there

    def test_idor_survey_results(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)

        as_b = client.get(f"/api/v1/surveys/{survey_id}/results", headers=headers_b)
        assert as_b.status_code == 404
        assert as_b.json()["detail"] == "Survey not found"

    def test_idor_photo_analyses_list(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)

        as_b = client.get(f"/api/v1/surveys/{survey_id}/photo-analyses", headers=headers_b)
        assert as_b.status_code == 404


class TestPhotoAnalysisEndpoints:
    """Photo analysis endpoint tests (authenticated, owner-only)."""

    ANALYSIS_DATA = {
        "photo_type": "boiler",
        "file_path": "/tmp/test_boiler.jpg",
        "extracted_brand": "Baxi",
        "extracted_model": "Luna 24",
        "extracted_power_kw": 24.0,
        "extracted_year": 2021,
        "quality_score": 85.0,
        "is_readable": True,
    }

    def test_create_photo_analysis(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        payload = {"survey_id": survey_id, **self.ANALYSIS_DATA}
        response = client.post("/api/v1/photo-analyses", json=payload, headers=headers)
        assert response.status_code == 201, response.text
        data = response.json()
        assert str(uuid.UUID(data["id"])) == data["id"]
        assert data["survey_id"] == survey_id
        assert data["photo_type"] == "boiler"
        assert data["extracted_brand"] == "Baxi"
        assert data["is_readable"] is True

    def test_create_photo_analysis_requires_auth(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        response = client.post(
            "/api/v1/photo-analyses",
            json={"survey_id": survey_id, **self.ANALYSIS_DATA},
        )
        assert response.status_code == 401

    def test_create_photo_analysis_invalid_survey_id(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(
            "/api/v1/photo-analyses",
            json={"survey_id": "not-a-uuid", **self.ANALYSIS_DATA},
            headers=headers,
        )
        assert response.status_code == 422

    def test_create_photo_analysis_on_other_users_survey(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)
        response = client.post(
            "/api/v1/photo-analyses",
            json={"survey_id": survey_id, **self.ANALYSIS_DATA},
            headers=headers_b,
        )
        assert response.status_code == 404
        assert response.json()["detail"] == "Survey not found"

    def test_get_survey_photo_analyses(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        created = client.post(
            "/api/v1/photo-analyses",
            json={"survey_id": survey_id, **self.ANALYSIS_DATA},
            headers=headers,
        )
        assert created.status_code == 201

        response = client.get(f"/api/v1/surveys/{survey_id}/photo-analyses", headers=headers)
        assert response.status_code == 200
        items = response.json()
        assert isinstance(items, list)
        assert len(items) == 1
        assert items[0]["id"] == created.json()["id"]

    def test_get_survey_photo_analyses_invalid_uuid(self, client, auth_a):
        headers, _ = auth_a
        response = client.get("/api/v1/surveys/invalid-uuid/photo-analyses", headers=headers)
        assert response.status_code == 422

    def test_get_survey_photo_analyses_requires_auth(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        response = client.get(f"/api/v1/surveys/{survey_id}/photo-analyses")
        assert response.status_code == 401


class TestSurveyResults:
    """Survey results endpoint tests (authenticated, owner-only)."""

    def test_get_survey_results(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(
            client,
            headers,
            square_meters=100.0,
            avg_height=2.7,
            heating_type="Pompa di Calore",
        )
        response = client.get(f"/api/v1/surveys/{survey_id}/results", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert data["survey_id"] == survey_id
        assert data["status"] == "draft"
        # computed server-side by app.core.energy (legacy heating_type honoured)
        result = data["energy_result"]
        assert data["estimated_class"] == result["classe"]
        assert data["energy_score"] == result["punteggio"]
        assert data["final_score"] == result["punteggio"]
        assert result["impianto"]["generatore"] == "Pompa di calore aria-acqua"
        assert result["clima"]["comune"]["comune"] == "Milano"
        assert data["photo_count"] == 0
        assert data["geo_location"]["address"] == "Via Roma 1, 20100 Milano MI"
        assert data["building_data"]["square_meters"] == 100.0
        assert data["systems"]["heating_type"] == "Pompa di Calore"

    def test_get_survey_results_completed(self, client, auth_a):
        headers, user_id = auth_a
        survey_id = _seed_completed_survey(user_id)
        response = client.get(f"/api/v1/surveys/{survey_id}/results", headers=headers)
        assert response.status_code == 200
        data = response.json()
        assert data["survey_id"] == survey_id
        assert data["estimated_class"] == "A3"
        assert data["energy_score"] == 95.0
        assert data["final_score"] == 95.0  # same 0-100 scale as energy_score
        assert data["status"] == "completed"
        assert data["geo_location"]["address"] == "Via Milano 1"

    def test_get_survey_results_not_found(self, client, auth_a):
        """Valid UUID, no row -> strict 404 (not 422, not `422 or 404`)."""
        headers, _ = auth_a
        response = client.get(f"/api/v1/surveys/{uuid.uuid4()}/results", headers=headers)
        assert response.status_code == 404
        assert response.json()["detail"] == "Survey not found"

    def test_get_survey_results_invalid_uuid(self, client, auth_a):
        """Malformed id -> strict 422 (contratto UUID)."""
        headers, _ = auth_a
        response = client.get("/api/v1/surveys/non-existent-id/results", headers=headers)
        assert response.status_code == 422


class TestCORS:
    """CORS middleware tests on main:app (AC-1)."""

    def test_cors_headers(self, client):
        response = client.get(
            "/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert response.status_code == 200
        # exact match, not just presence
        assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"

    def test_cors_preflight(self, client):
        response = client.options(
            "/api/v1/surveys",
            headers={
                "Origin": "http://localhost:8080",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type,authorization",
            },
        )
        assert response.status_code == 200
        assert response.headers.get("access-control-allow-origin") == "http://localhost:8080"
        assert response.headers.get("access-control-allow-credentials") == "true"
        assert "POST" in response.headers.get("access-control-allow-methods", "")
        # preflight must expose/allow the JWT header for the A3 API client
        assert "authorization" in response.headers.get("access-control-allow-headers", "").lower()

    def test_cors_disallowed_origin(self, client):
        response = client.get("/", headers={"Origin": "http://evil.example"})
        assert response.status_code == 200
        assert "access-control-allow-origin" not in response.headers


class TestErrorHandling:
    """Error handling tests"""

    def test_invalid_json(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(
            "/api/v1/surveys",
            content="not json",
            headers={**headers, "content-type": "application/json"},
        )
        assert response.status_code == 422

    def test_missing_required_fields(self, client, auth_a):
        headers, _ = auth_a
        # all survey fields are optional
        response = client.post("/api/v1/surveys", json={"address": "Test"}, headers=headers)
        assert response.status_code == 201

    def test_invalid_survey_id(self, client, auth_a):
        """Strict contract: malformed path id is always 422 (AC-5)."""
        headers, _ = auth_a
        response = client.get("/api/v1/surveys/invalid-uuid", headers=headers)
        assert response.status_code == 422


class TestAPIDocs:
    """API documentation / contract exposure tests (input for P1-A3)."""

    def test_swagger_ui(self, client):
        response = client.get("/docs")
        assert response.status_code == 200

    def test_redoc(self, client):
        response = client.get("/redoc")
        assert response.status_code == 200

    def test_openapi_json_contract(self, client):
        response = client.get("/openapi.json")
        assert response.status_code == 200
        spec = response.json()
        assert spec["info"]["title"] == "Pre-APE API"
        # auth endpoints published for the API client
        assert "post" in spec["paths"].get("/api/v1/auth/login", {})
        assert "post" in spec["paths"].get("/api/v1/auth/register", {})
        # security scheme (JWT bearer) declared and applied to survey reads
        security_schemes = spec["components"].get("securitySchemes", {})
        assert security_schemes, "OpenAPI must declare a security scheme for JWT"
        get_survey = spec["paths"]["/api/v1/surveys/{survey_id}"]["get"]
        assert get_survey.get("security"), "protected operations must declare security"
        # path id typed as uuid so the client sends the right shape
        survey_param = next(
            p for p in get_survey["parameters"] if p["name"] == "survey_id"
        )
        assert survey_param["schema"]["format"] == "uuid"


# ---------------------------------------------------------------------------
# M1 fixes + M2 coverage (MACRO_TASKS.md): one test per acceptance criterion.
# ---------------------------------------------------------------------------

def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _raw_jwt(header: dict, payload: dict) -> str:
    """Manual, unsigned JWT — used to forge `alg: none` tokens."""
    return f"{_b64url(json.dumps(header).encode())}.{_b64url(json.dumps(payload).encode())}."


def _claims(user_id: str, exp_offset: int = 600) -> dict:
    now = int(time.time())
    return {"sub": user_id, "iat": now, "exp": now + exp_offset}


class TestCORSProductionOrigin:
    """M1: prod origin in the default CORS_ORIGINS, env-overridable as JSON."""

    PROD = "https://preape.cheic2.it"

    def test_default_allows_production_origin(self):
        assert self.PROD in settings.CORS_ORIGINS
        # dev origins keep working out of the box
        assert "http://localhost:3000" in settings.CORS_ORIGINS

    def test_preflight_production_origin(self, client):
        response = client.options(
            "/api/v1/surveys",
            headers={
                "Origin": self.PROD,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type,authorization",
            },
        )
        assert response.status_code == 200
        assert response.headers.get("access-control-allow-origin") == self.PROD
        assert response.headers.get("access-control-allow-credentials") == "true"
        assert "POST" in response.headers.get("access-control-allow-methods", "")
        assert "authorization" in response.headers.get("access-control-allow-headers", "").lower()

    def test_preflight_lookalike_origin_rejected(self, client):
        """Negative stretto: origin non whitelistata -> 400 e nessun ACAO.

        Starlette risponde 400 "Disallowed CORS origin" ai preflight negati
        (più informativo di un 200 senza header, vedi starlette.cors).
        """
        for evil in (
            f"{self.PROD}.evil.example",
            "https://evil.example/preape.cheic2.it",
            "http://preape.cheic2.it",  # scheme diverso -> non abbinato
        ):
            response = client.options(
                "/api/v1/surveys",
                headers={"Origin": evil, "Access-Control-Request-Method": "POST"},
            )
            assert response.status_code == 400, evil
            assert "access-control-allow-origin" not in response.headers, evil
            assert "origin" in response.text.lower(), evil

    def test_cors_origins_env_json_override(self, monkeypatch):
        monkeypatch.setenv("CORS_ORIGINS", '["https://env-override.example"]')
        overridden = Settings()
        assert overridden.CORS_ORIGINS == ["https://env-override.example"]


class TestRateLimitKeyProxyAware:
    """M1: CF-Connecting-IP trusted only when the peer is loopback."""

    @staticmethod
    def _login(client_, cf_ip: str):
        return client_.post(
            "/api/v1/auth/login",
            json={
                "email": f"flood_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}",
                "password": "Whatever-123",
            },
            headers={"CF-Connecting-IP": cf_ip},
        )

    def test_two_logical_ips_separate_buckets_same_ip_429_at_11th(self, client_from):
        trusted_proxy = client_from("127.0.0.1")
        # stesso IP logico: 10 consentite, 429 all'11° (AC: 429 al 11°)
        statuses = [
            self._login(trusted_proxy, "198.51.100.7").status_code
            for _ in range(11)
        ]
        assert statuses == [401] * 10 + [429]
        assert self._login(trusted_proxy, "198.51.100.7").status_code == 429
        # secondo IP logico dietro lo stesso proxy -> bucket separato, ancora libero
        assert self._login(trusted_proxy, "203.0.113.9").status_code == 401

    def test_cf_header_ignored_for_remote_peer(self, client_from):
        """Spoofing: peer non-loopback -> header non fidato, key = client.host."""
        remote = client_from("203.0.113.50")
        # 11 header diversi, stesso peer -> un solo bucket -> 429 all'11°
        statuses = [
            self._login(remote, f"198.51.100.{i}").status_code
            for i in range(1, 12)
        ]
        assert statuses == [401] * 10 + [429]
        # peer diverso -> bucket separato anche con lo stesso CF header
        other = client_from("203.0.113.51")
        assert self._login(other, "198.51.100.1").status_code == 401


class TestSecretKeyFailFast:
    """M1: placeholder SECRET_KEY is refused outside development."""

    def test_placeholder_rejected_outside_development(self, monkeypatch):
        monkeypatch.setenv("APP_ENV", "staging")
        monkeypatch.setenv("SECRET_KEY", SECRET_KEY_PLACEHOLDER)
        with pytest.raises(ValidationError, match="SECRET_KEY"):
            Settings()

    def test_placeholder_allowed_in_development(self, monkeypatch):
        monkeypatch.setenv("APP_ENV", "development")
        monkeypatch.setenv("SECRET_KEY", SECRET_KEY_PLACEHOLDER)
        assert Settings().SECRET_KEY == SECRET_KEY_PLACEHOLDER

    def test_strong_secret_allowed_in_production(self, monkeypatch):
        monkeypatch.setenv("APP_ENV", "production")
        monkeypatch.setenv("SECRET_KEY", "not-a-placeholder-" + uuid.uuid4().hex * 2)
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", base64.urlsafe_b64encode(b"k" * 32).decode())
        assert Settings().APP_ENV == "production"


class TestPBKDF2OffEventLoop:
    """M1: verify/dummy_verify run in asyncio.to_thread (no event-loop stall)."""

    async def test_verify_and_dummy_do_not_block_loop(self):
        stored = hash_password(TEST_PASSWORD)
        ticks = 0
        stop = False

        async def ticker():
            nonlocal ticks
            while not stop:
                ticks += 1
                await asyncio.sleep(0)

        task = asyncio.create_task(ticker())
        try:
            assert await verify_password_async(TEST_PASSWORD, stored) is True
            assert await verify_password_async("Definitely-Wrong-1", stored) is False
            assert await dummy_verify_async("anything") is False
        finally:
            stop = True
            await task
        # the loop kept turning during the 600k PBKDF2 iterations
        assert ticks > 0


class TestInputSchemaStrictness:
    """M1: extra="forbid" on create/update inputs — computed fields -> 422."""

    def test_create_rejects_estimated_class(self, client, auth_a):
        headers, _ = auth_a
        response = client.post(
            "/api/v1/surveys",
            json={"address": "Via Roma 1, 20100 Milano MI", "estimated_class": "A3"},
            headers=headers,
        )
        assert response.status_code == 422
        assert "estimated_class" in str(response.json()["detail"])

    def test_update_rejects_energy_score(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        response = client.put(
            f"/api/v1/surveys/{survey_id}",
            json={"energy_score": 95.0},
            headers=headers,
        )
        assert response.status_code == 422
        assert "energy_score" in str(response.json()["detail"])
        # no silent write: the stored score is the server-computed one, not 95
        stored = client.get(f"/api/v1/surveys/{survey_id}", headers=headers)
        assert stored.json()["energy_score"] != 95.0


class TestTokenSecurity:
    """M2: expired/forged/alg:none/alg-confusion -> 401; scheme strict -> 401."""

    def test_expired_token_rejected(self, client, auth_a):
        _, user_id = auth_a
        token = jwt.encode(
            _claims(user_id, exp_offset=-60), settings.SECRET_KEY, algorithm="HS256"
        )
        response = client.get(
            f"/api/v1/surveys/{uuid.uuid4()}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401
        assert response.headers.get("www-authenticate") == "Bearer"

    def test_forged_signature_rejected(self, client, auth_a):
        _, user_id = auth_a
        token = jwt.encode(
            _claims(user_id), "attacker-controlled-secret", algorithm="HS256"
        )
        response = client.get(
            f"/api/v1/surveys/{uuid.uuid4()}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401

    def test_alg_none_rejected(self, client, auth_a):
        _, user_id = auth_a
        token = _raw_jwt({"alg": "none", "typ": "JWT"}, _claims(user_id))
        response = client.get(
            f"/api/v1/surveys/{uuid.uuid4()}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401

    def test_alg_confusion_rejected(self, client, auth_a):
        """HS512 header with the real secret: decode is pinned to HS256."""
        _, user_id = auth_a
        token = jwt.encode(_claims(user_id), settings.SECRET_KEY, algorithm="HS512")
        response = client.get(
            f"/api/v1/surveys/{uuid.uuid4()}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401

    def test_authorization_scheme_must_be_bearer(self, client, auth_a):
        headers, _ = auth_a
        token = headers["Authorization"].split(" ", 1)[1]
        survey_id = create_survey(client, headers)
        ok = client.get(
            f"/api/v1/surveys/{survey_id}",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert ok.status_code == 200  # positive control
        for bad in (token, f"Token {token}", f"bearer {token}", f"BEARER {token}"):
            response = client.get(
                f"/api/v1/surveys/{survey_id}", headers={"Authorization": bad}
            )
            assert response.status_code == 401, bad
            assert response.headers.get("www-authenticate") == "Bearer"


class TestValidationContracts:
    """M2: malformed email -> 422; wrong password -> uniform 401."""

    def test_register_malformed_email_422(self, client):
        for bad in ("not-an-email", "missing-at.example", "trailing@", "@leading.test"):
            response = client.post(
                "/api/v1/auth/register",
                json={"email": bad, "password": TEST_PASSWORD, "accept_terms": True},
            )
            assert response.status_code == 422, bad
            assert response.json()["detail"] == "Invalid email format"

    def test_wrong_password_uniform_401(self, client):
        known = f"uniform_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        assert client.post(
            "/api/v1/auth/register",
            json={"email": known, "password": TEST_PASSWORD, "accept_terms": True},
        ).status_code == 201
        wrong_pw = client.post(
            "/api/v1/auth/login",
            json={"email": known, "password": "Definitely-Wrong-1"},
        )
        unknown = client.post(
            "/api/v1/auth/login",
            json={
                "email": f"ghost_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}",
                "password": TEST_PASSWORD,
            },
        )
        # uniform 401: same status, same body, same header (no user enumeration)
        assert wrong_pw.status_code == unknown.status_code == 401
        assert wrong_pw.json() == unknown.json()
        assert (
            wrong_pw.headers.get("www-authenticate")
            == unknown.headers.get("www-authenticate")
            == "Bearer"
        )


class TestRateLimitWindowReset:
    """M2: asserted reset — outside the sliding window a request gets 200 again
    (asserted here, not just via the fixture purge)."""

    def test_request_allowed_outside_window(self, client, monkeypatch):
        email = f"window_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
        # hit 1: register
        assert client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": TEST_PASSWORD, "accept_terms": True},
        ).status_code == 201
        # hits 2-10: wrong logins -> 401
        for _ in range(9):
            assert client.post(
                "/api/v1/auth/login",
                json={"email": email, "password": "Definitely-Wrong-1"},
            ).status_code == 401
        # hit 11 -> 429
        blocked = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "Definitely-Wrong-1"},
        )
        assert blocked.status_code == 429

        # simulate the window (60 s) elapsing — only for the limiter's clock
        real_monotonic = time.monotonic
        shift = rate_limit_module.auth_rate_limiter.window_seconds + 1.0

        class _ShiftedTime:
            @staticmethod
            def monotonic():
                return real_monotonic() + shift

        monkeypatch.setattr(rate_limit_module, "time", _ShiftedTime)

        # outside the window: a successful login is allowed again -> 200
        allowed = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": TEST_PASSWORD},
        )
        assert allowed.status_code == 200, allowed.text
        assert allowed.json()["email"] == email

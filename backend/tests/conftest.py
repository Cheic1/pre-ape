"""Shared test fixtures.

Guarantees for AC-4/AC-5 (green + deterministic suite):
  * explicit APP_ENV=development before importing the app, so the SECRET_KEY
    fail-fast (placeholder rejected outside development) never depends on the
    host environment (M1);
  * schema is initialised once per session (init_db -> shared engine, AC-6);
  * every test starts and ends with a purged test dataset (no order dependence);
  * the /auth rate limiter is reset around every test;
  * helpers register throwaway users (RFC 2606 domain example.test) with JWTs;
  * ``client_from`` builds TestClients with a chosen logical client IP
    (trusted-proxy / multi-IP rate-limit tests).
"""
import os

# M1: must be set BEFORE `main` (and app.core.config) is imported below.
os.environ["APP_ENV"] = "development"

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from main import app, init_db
from app.core.rate_limit import auth_rate_limiter
from app.models.database import engine

TEST_EMAIL_DOMAIN = "example.test"  # reserved domain, never a real mailbox
TEST_PASSWORD = "S3cure-Pass!"


def _purge_test_data() -> None:
    """Remove every row owned by a test user (children first, FK order)."""
    like = f"%@{TEST_EMAIL_DOMAIN}"
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                DELETE FROM photo_analyses
                WHERE survey_id IN (
                    SELECT s.id FROM surveys s
                    JOIN users u ON u.id = s.user_id
                    WHERE u.email LIKE :like
                )
                """
            ),
            {"like": like},
        )
        conn.execute(
            text(
                "DELETE FROM surveys WHERE user_id IN "
                "(SELECT id FROM users WHERE email LIKE :like)"
            ),
            {"like": like},
        )
        conn.execute(text("DELETE FROM users WHERE email LIKE :like"), {"like": like})


@pytest.fixture(scope="session", autouse=True)
def db_schema():
    """Create tables + additive migrations once (shared engine, no second one)."""
    init_db()


@pytest.fixture(autouse=True)
def clean_state(db_schema):
    """Fresh state around every test: purged DB rows + reset rate limiter."""
    _purge_test_data()
    auth_rate_limiter.reset()
    yield
    _purge_test_data()
    auth_rate_limiter.reset()


@pytest.fixture
def client(clean_state):
    return TestClient(app)


class _ForceClientHost:
    """ASGI wrapper that forces scope["client"] = (host, port).

    starlette 0.36's TestClient hardcodes ("testclient", 50000) and exposes no
    override, so logical-IP tests (trusted proxy / spoofing) rewrite the scope
    here — before FastAPI builds the Request.
    """

    def __init__(self, app_, host: str):
        self._app = app_
        self._host = host

    async def __call__(self, scope, receive, send):
        if scope["type"] in ("http", "websocket"):
            scope["client"] = (self._host, 54321)
        await self._app(scope, receive, send)


@pytest.fixture
def client_from(clean_state):
    """Factory: TestClient whose logical client IP is ``host``."""
    created = []

    def _make(host: str) -> TestClient:
        test_client = TestClient(_ForceClientHost(app, host))
        created.append(test_client)
        return test_client

    yield _make
    for test_client in created:
        test_client.close()


def register_user(client: TestClient, prefix: str = "user") -> tuple[dict, str]:
    """Register a throwaway user; return (auth headers, user_id)."""
    email = f"{prefix}_{uuid.uuid4().hex}@{TEST_EMAIL_DOMAIN}"
    response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": TEST_PASSWORD, "name": f"Test {prefix}"},
    )
    assert response.status_code == 201, response.text
    body = response.json()
    return {"Authorization": f"Bearer {body['access_token']}"}, body["user_id"]


def create_survey(client: TestClient, headers: dict, **fields) -> str:
    """Create a survey for the authenticated user; return its id."""
    payload = {"address": "Via Roma 1, 20100 Milano MI", **fields}
    response = client.post("/api/v1/surveys", json=payload, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()["id"]


@pytest.fixture
def auth_a(client):
    """User A: (headers, user_id)."""
    return register_user(client, "user_a")


@pytest.fixture
def auth_b(client):
    """User B (distinct account): (headers, user_id)."""
    return register_user(client, "user_b")

"""Abbonamenti: prova gratuita, blocco 402, attivazione manuale, webhook Stripe."""
import hashlib
import hmac
import json
import time
from datetime import datetime, timedelta

import pytest
from sqlalchemy import text

from app.core import billing
from app.core.config import settings
from app.models.database import engine
from conftest import create_survey, register_user

WEBHOOK_SECRET = "whsec_test"


@pytest.fixture
def billing_on(monkeypatch):
    monkeypatch.setattr(settings, "BILLING_ENABLED", True)
    monkeypatch.setattr(settings, "TRIAL_DAYS", 30)
    monkeypatch.setattr(settings, "TRIAL_MAX_SURVEYS", 2)
    monkeypatch.setattr(settings, "STRIPE_WEBHOOK_SECRET", WEBHOOK_SECRET)


def _set_user(user_id, **cols):
    sets = ", ".join(f"{k} = :{k}" for k in cols)
    with engine.begin() as conn:
        conn.execute(text(f"UPDATE users SET {sets} WHERE id = :id"), {"id": user_id, **cols})


def _get_user(user_id):
    with engine.begin() as conn:
        return conn.execute(text("SELECT * FROM users WHERE id = :id"), {"id": user_id}).mappings().one()


def _signed(payload: dict, secret=WEBHOOK_SECRET, ts=None):
    raw = json.dumps(payload).encode()
    ts = ts or int(time.time())
    sig = hmac.new(secret.encode(), f"{ts}.".encode() + raw, hashlib.sha256).hexdigest()
    return raw, {"Stripe-Signature": f"t={ts},v1={sig}", "Content-Type": "application/json"}


class TestBillingOff:
    def test_default_is_unlimited(self, client, auth_a):
        headers, _ = auth_a
        body = client.get("/api/v1/billing/me", headers=headers).json()
        assert body["billing_enabled"] is False
        assert body["status"] == "unlimited" and body["can_create"] is True
        for _ in range(3):
            create_survey(client, headers)

    def test_checkout_unavailable(self, client, auth_a):
        headers, _ = auth_a
        r = client.post("/api/v1/billing/checkout", json={"interval": "month"}, headers=headers)
        assert r.status_code == 503


class TestTrial:
    def test_trial_then_quota_402(self, client, billing_on):
        headers, _ = register_user(client, "trial")
        me = client.get("/api/v1/billing/me", headers=headers).json()
        assert me["status"] == "trial" and me["trial_surveys_max"] == 2
        survey_id = create_survey(client, headers)
        create_survey(client, headers)
        r = client.post("/api/v1/surveys", json={"address": "x"}, headers=headers)
        assert r.status_code == 402
        assert "prova" in r.json()["detail"]
        # i dati restano utilizzabili
        assert client.get(f"/api/v1/surveys/{survey_id}", headers=headers).status_code == 200
        r = client.put(f"/api/v1/surveys/{survey_id}", json={"notes": "ok"}, headers=headers)
        assert r.status_code == 200
        assert client.get(f"/api/v1/surveys/{survey_id}/cened-sheet", headers=headers).status_code == 200
        # export CENED bloccato
        assert client.get(f"/api/v1/surveys/{survey_id}/cened-xml", headers=headers).status_code == 402

    def test_trial_expired_by_date(self, client, billing_on):
        headers, user_id = register_user(client, "old")
        _set_user(user_id, created_at=datetime.utcnow() - timedelta(days=31))
        me = client.get("/api/v1/billing/me", headers=headers).json()
        assert me["status"] == "expired" and me["can_create"] is False
        assert "scaduta" in me["reason"]

    def test_paid_until_active(self, client, billing_on):
        headers, user_id = register_user(client, "paid")
        _set_user(user_id, created_at=datetime.utcnow() - timedelta(days=90),
                  paid_until=datetime.utcnow() + timedelta(days=10), plan="pro")
        me = client.get("/api/v1/billing/me", headers=headers).json()
        assert me["status"] == "active" and me["plan"] == "pro"
        create_survey(client, headers)

    def test_admin_always_unlimited(self, client, billing_on, monkeypatch):
        headers, user_id = register_user(client, "boss")
        email = _get_user(user_id)["email"]
        monkeypatch.setattr(settings, "ADMIN_EMAILS", email)
        _set_user(user_id, created_at=datetime.utcnow() - timedelta(days=90))
        assert client.get("/api/v1/billing/me", headers=headers).json()["status"] == "unlimited"


class TestAdminActivation:
    def test_manual_activation_and_revoke(self, client, billing_on, monkeypatch):
        admin_headers, admin_id = register_user(client, "admin")
        monkeypatch.setattr(settings, "ADMIN_EMAILS", _get_user(admin_id)["email"])
        headers, user_id = register_user(client, "cliente")
        _set_user(user_id, created_at=datetime.utcnow() - timedelta(days=90))

        until = (datetime.utcnow() + timedelta(days=365)).isoformat() + "Z"
        r = client.post(f"/api/v1/admin/users/{user_id}/subscription",
                        json={"paid_until": until, "plan": "studio"}, headers=admin_headers)
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "active" and r.json()["plan"] == "studio"
        create_survey(client, headers)

        users = client.get("/api/v1/admin/users", headers=admin_headers).json()
        row = next(u for u in users if u["id"] == user_id)
        assert row["plan"] == "studio" and row["paid_until"]

        r = client.post(f"/api/v1/admin/users/{user_id}/subscription",
                        json={"paid_until": None}, headers=admin_headers)
        assert r.json()["status"] == "expired"

        audit = client.get("/api/v1/admin/audit", headers=admin_headers).json()
        assert any(a["action"] == "set_subscription" for a in audit)

    def test_non_admin_403(self, client, auth_a, auth_b):
        headers, _ = auth_a
        _, other = auth_b
        r = client.post(f"/api/v1/admin/users/{other}/subscription",
                        json={"paid_until": None}, headers=headers)
        assert r.status_code == 403


class TestWebhook:
    def test_bad_signature_400(self, client, billing_on):
        raw, headers = _signed({"type": "x"}, secret="wrong")
        assert client.post("/api/v1/billing/webhook", content=raw, headers=headers).status_code == 400

    def test_old_timestamp_400(self, client, billing_on):
        raw, headers = _signed({"type": "x"}, ts=int(time.time()) - 3600)
        assert client.post("/api/v1/billing/webhook", content=raw, headers=headers).status_code == 400

    def test_subscription_updated_activates_user(self, client, billing_on):
        headers, user_id = register_user(client, "stripe")
        _set_user(user_id, created_at=datetime.utcnow() - timedelta(days=90),
                  stripe_customer_id="cus_TEST123")
        period_end = int(time.time()) + 30 * 86400
        event = {
            "type": "customer.subscription.updated",
            "data": {"object": {"id": "sub_1", "customer": "cus_TEST123", "status": "active",
                                "items": {"data": [{"current_period_end": period_end}]}}},
        }
        raw, h = _signed(event)
        r = client.post("/api/v1/billing/webhook", content=raw, headers=h)
        assert r.status_code == 200
        row = _get_user(user_id)
        assert row["subscription_status"] == "active" and row["stripe_subscription_id"] == "sub_1"
        assert row["paid_until"] > datetime.utcnow() + timedelta(days=29)
        assert client.get("/api/v1/billing/me", headers=headers).json()["status"] == "active"

    def test_checkout_completed_fetches_subscription(self, client, billing_on, monkeypatch):
        headers, user_id = register_user(client, "checkout")
        period_end = int(time.time()) + 365 * 86400
        calls = []

        def fake_stripe(method, path, data=None):
            calls.append((method, path))
            return {"id": "sub_9", "customer": "cus_9", "status": "active", "current_period_end": period_end}

        monkeypatch.setattr(billing, "stripe_request", fake_stripe)
        event = {"type": "checkout.session.completed",
                 "data": {"object": {"client_reference_id": user_id, "customer": "cus_9",
                                     "subscription": "sub_9"}}}
        raw, h = _signed(event)
        assert client.post("/api/v1/billing/webhook", content=raw, headers=h).status_code == 200
        assert calls == [("GET", "/subscriptions/sub_9")]
        row = _get_user(user_id)
        assert row["stripe_customer_id"] == "cus_9" and row["plan"] == "pro"

    def test_canceled_keeps_paid_period(self):
        class U:
            stripe_subscription_id = None
            stripe_customer_id = "cus"
            subscription_status = "active"
            plan = "pro"
            paid_until = datetime(2030, 1, 1)

        u = U()
        billing.apply_subscription(u, {"id": "sub", "status": "canceled", "current_period_end": 1})
        assert u.paid_until == datetime(2030, 1, 1) and u.subscription_status == "canceled"


class TestCheckout:
    def test_checkout_creates_customer_and_session(self, client, billing_on, monkeypatch):
        monkeypatch.setattr(settings, "STRIPE_SECRET_KEY", "sk_test_x")
        monkeypatch.setattr(settings, "STRIPE_PRICE_MONTHLY", "price_m")
        headers, user_id = register_user(client, "buyer")
        calls = []

        def fake_stripe(method, path, data=None):
            calls.append((path, data))
            if path == "/customers":
                return {"id": "cus_new"}
            return {"url": "https://checkout.stripe.test/s"}

        monkeypatch.setattr(billing, "stripe_request", fake_stripe)
        r = client.post("/api/v1/billing/checkout", json={"interval": "month"}, headers=headers)
        assert r.status_code == 200 and r.json()["url"].startswith("https://checkout")
        session = calls[1][1]
        assert session["customer"] == "cus_new" and session["client_reference_id"] == user_id
        assert session["line_items"] == [{"price": "price_m", "quantity": 1}]
        assert _get_user(user_id)["stripe_customer_id"] == "cus_new"
        # annuale non configurato
        r = client.post("/api/v1/billing/checkout", json={"interval": "year"}, headers=headers)
        assert r.status_code == 422


def test_flatten_stripe_encoding():
    flat = billing._flatten({"a": {"b": 1}, "c": [{"price": "p", "quantity": 1}], "d": True, "e": None})
    assert flat == [("a[b]", "1"), ("c[0][price]", "p"), ("c[0][quantity]", "1"), ("d", "true")]

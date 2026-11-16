"""Abbonamenti: chi può creare sopralluoghi ed esportare in CENED.

Tutto passa da ``entitlement(user, db)``. Con ``BILLING_ENABLED=false`` (default)
ogni utente è illimitato, come prima di questo modulo.

Regole con billing acceso:
  * admin (``ADMIN_EMAILS``) → sempre attivo;
  * ``paid_until`` nel futuro → attivo (Stripe aggiorna il campo a ogni
    rinnovo; l'admin lo imposta a mano per chi paga con bonifico);
  * altrimenti prova gratuita fino a ``trial_ends_at`` (default
    ``created_at + TRIAL_DAYS``) e al massimo ``TRIAL_MAX_SURVEYS`` sopralluoghi;
  * finita la prova: niente nuovi sopralluoghi né export CENED (HTTP 402), ma
    i dati restano leggibili, modificabili ed esportabili in altri modi
    (portabilità, art. 20 GDPR).

Stripe è chiamato via REST con la libreria standard (nessuna dipendenza in
più); il webhook è verificato con la firma HMAC ``Stripe-Signature``.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

from app.core.config import settings

STRIPE_API = "https://api.stripe.com/v1"
# Tolleranza sul timestamp della firma webhook (come le librerie ufficiali)
WEBHOOK_TOLERANCE_SECONDS = 300
# Stati Stripe che danno accesso (past_due: Stripe sta ritentando l'addebito)
ACTIVE_STRIPE_STATUSES = frozenset({"active", "trialing", "past_due"})


@dataclass
class Entitlement:
    billing_enabled: bool
    status: str  # unlimited | active | trial | expired
    can_create: bool
    plan: Optional[str] = None
    paid_until: Optional[datetime] = None
    trial_ends_at: Optional[datetime] = None
    trial_surveys_used: int = 0
    trial_surveys_max: int = 0
    reason: Optional[str] = None

    def as_dict(self) -> Dict[str, Any]:
        return {
            "billing_enabled": self.billing_enabled,
            "status": self.status,
            "can_create": self.can_create,
            "plan": self.plan,
            "paid_until": self.paid_until,
            "trial_ends_at": self.trial_ends_at,
            "trial_surveys_used": self.trial_surveys_used,
            "trial_surveys_max": self.trial_surveys_max,
            "reason": self.reason,
            "online_payment": stripe_configured(),
        }


def trial_end(user) -> datetime:
    if user.trial_ends_at is not None:
        return user.trial_ends_at
    start = user.created_at or datetime.utcnow()
    return start + timedelta(days=settings.TRIAL_DAYS)


def entitlement(user, survey_count: int, admin: bool = False, now: Optional[datetime] = None) -> Entitlement:
    """Stato dell'abbonamento. ``survey_count``: sopralluoghi dell'utente."""
    now = now or datetime.utcnow()
    if not settings.BILLING_ENABLED:
        return Entitlement(billing_enabled=False, status="unlimited", can_create=True)
    if admin:
        return Entitlement(billing_enabled=True, status="unlimited", can_create=True, plan="admin")
    if user.paid_until is not None and user.paid_until > now:
        return Entitlement(
            billing_enabled=True,
            status="active",
            can_create=True,
            plan=user.plan or "pro",
            paid_until=user.paid_until,
        )
    ends = trial_end(user)
    used = survey_count
    limit = settings.TRIAL_MAX_SURVEYS
    if now < ends and used < limit:
        return Entitlement(
            billing_enabled=True,
            status="trial",
            can_create=True,
            trial_ends_at=ends,
            trial_surveys_used=used,
            trial_surveys_max=limit,
        )
    if now >= ends:
        reason = "Prova gratuita scaduta: attiva l'abbonamento per creare nuovi sopralluoghi."
    else:
        reason = f"Hai usato i {limit} sopralluoghi della prova gratuita: attiva l'abbonamento."
    return Entitlement(
        billing_enabled=True,
        status="expired",
        can_create=False,
        plan=user.plan,
        paid_until=user.paid_until,
        trial_ends_at=ends,
        trial_surveys_used=used,
        trial_surveys_max=limit,
        reason=reason,
    )


# ---------------------------------------------------------------------------
# Stripe (REST, form-encoded)
# ---------------------------------------------------------------------------
class StripeError(Exception):
    pass


def stripe_configured() -> bool:
    return bool(settings.STRIPE_SECRET_KEY and (settings.STRIPE_PRICE_MONTHLY or settings.STRIPE_PRICE_YEARLY))


def _flatten(data: Dict[str, Any], prefix: str = "") -> list[tuple[str, str]]:
    """{"a": {"b": 1}, "c": [x]} → a[b]=1, c[0]=x (encoding di Stripe)."""
    out: list[tuple[str, str]] = []
    for key, value in data.items():
        name = f"{prefix}[{key}]" if prefix else str(key)
        if isinstance(value, dict):
            out.extend(_flatten(value, name))
        elif isinstance(value, list):
            for i, item in enumerate(value):
                if isinstance(item, dict):
                    out.extend(_flatten(item, f"{name}[{i}]"))
                else:
                    out.append((f"{name}[{i}]", str(item)))
        elif value is not None:
            out.append((name, "true" if value is True else "false" if value is False else str(value)))
    return out


def stripe_request(method: str, path: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Chiamata all'API Stripe; solleva StripeError con il messaggio di Stripe."""
    body = urllib.parse.urlencode(_flatten(data or {})).encode() if data else None
    req = urllib.request.Request(
        f"{STRIPE_API}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {settings.STRIPE_SECRET_KEY}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        try:
            message = json.loads(exc.read().decode())["error"]["message"]
        except Exception:  # noqa: BLE001
            message = f"HTTP {exc.code}"
        raise StripeError(message) from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise StripeError(f"Stripe non raggiungibile: {exc}") from exc


def verify_webhook(payload: bytes, signature_header: str, secret: str, now: Optional[float] = None) -> Dict[str, Any]:
    """Verifica ``Stripe-Signature`` (t=…,v1=…) e restituisce l'evento.

    Solleva ValueError se la firma manca, è sbagliata o troppo vecchia.
    """
    if not secret:
        raise ValueError("STRIPE_WEBHOOK_SECRET non configurato")
    parts: Dict[str, list[str]] = {}
    for item in (signature_header or "").split(","):
        key, _, value = item.strip().partition("=")
        parts.setdefault(key, []).append(value)
    try:
        timestamp = int(parts["t"][0])
    except (KeyError, ValueError, IndexError):
        raise ValueError("firma senza timestamp")
    expected = hmac.new(
        secret.encode(), f"{timestamp}.".encode() + payload, hashlib.sha256
    ).hexdigest()
    if not any(hmac.compare_digest(expected, sig) for sig in parts.get("v1", [])):
        raise ValueError("firma non valida")
    if abs((now or time.time()) - timestamp) > WEBHOOK_TOLERANCE_SECONDS:
        raise ValueError("firma scaduta")
    return json.loads(payload.decode())


def apply_subscription(user, subscription: Dict[str, Any]) -> None:
    """Copia lo stato di un oggetto Subscription Stripe sull'utente."""
    status = subscription.get("status")
    user.stripe_subscription_id = subscription.get("id") or user.stripe_subscription_id
    if subscription.get("customer"):
        user.stripe_customer_id = subscription["customer"]
    user.subscription_status = status
    period_end = subscription.get("current_period_end")
    if period_end is None:
        # API Stripe recenti: il periodo sta sugli item
        items = (subscription.get("items") or {}).get("data") or []
        ends = [i.get("current_period_end") for i in items if i.get("current_period_end")]
        period_end = max(ends) if ends else None
    if status in ACTIVE_STRIPE_STATUSES and period_end:
        # +1 giorno di margine: il rinnovo arriva via webhook qualche minuto dopo
        user.paid_until = datetime.utcfromtimestamp(int(period_end)) + timedelta(days=1)
        user.plan = user.plan or "pro"
    # canceled / unpaid: paid_until resta com'è, quindi l'accesso dura fino
    # alla fine del periodo già pagato e poi scade da solo.

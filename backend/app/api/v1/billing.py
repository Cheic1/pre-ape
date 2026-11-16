"""Abbonamento dell'utente: stato, Stripe Checkout / Customer Portal, webhook.

Contratto nel docstring di ``app.api.v1``; regole in ``app.core.billing``.
"""
import logging
from datetime import datetime
from typing import Literal, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from app.api.v1 import get_current_user, get_db, user_entitlement
from app.core import billing
from app.core.config import settings
from app.models.database import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/billing", tags=["billing"])


class EntitlementOut(BaseModel):
    billing_enabled: bool
    status: str
    can_create: bool
    plan: Optional[str] = None
    paid_until: Optional[datetime] = None
    trial_ends_at: Optional[datetime] = None
    trial_surveys_used: int = 0
    trial_surveys_max: int = 0
    reason: Optional[str] = None
    online_payment: bool = False


class CheckoutRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    interval: Literal["month", "year"] = "month"


class RedirectUrl(BaseModel):
    url: str


@router.get("/me", response_model=EntitlementOut)
async def my_subscription(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return user_entitlement(db, current_user).as_dict()


def _require_stripe() -> None:
    if not settings.BILLING_ENABLED or not billing.stripe_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Pagamento online non disponibile: contatta l'assistenza.",
        )


def _ensure_customer(db: Session, user: User) -> str:
    if user.stripe_customer_id:
        return user.stripe_customer_id
    customer = billing.stripe_request(
        "POST",
        "/customers",
        {"email": user.email, "name": user.name, "metadata": {"user_id": str(user.id)}},
    )
    user.stripe_customer_id = customer["id"]
    db.commit()
    return user.stripe_customer_id


@router.post("/checkout", response_model=RedirectUrl)
async def create_checkout(
    body: CheckoutRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    _require_stripe()
    price = settings.STRIPE_PRICE_YEARLY if body.interval == "year" else settings.STRIPE_PRICE_MONTHLY
    if not price:
        raise HTTPException(status_code=422, detail=f"Piano '{body.interval}' non disponibile")
    base = settings.PUBLIC_BASE_URL.rstrip("/")
    try:
        customer = _ensure_customer(db, current_user)
        session = billing.stripe_request(
            "POST",
            "/checkout/sessions",
            {
                "mode": "subscription",
                "customer": customer,
                "client_reference_id": str(current_user.id),
                "line_items": [{"price": price, "quantity": 1}],
                "success_url": f"{base}/?billing=ok",
                "cancel_url": f"{base}/?billing=annullato",
                "allow_promotion_codes": True,
                # Fattura italiana: indirizzo + P.IVA del cliente
                "billing_address_collection": "required",
                "tax_id_collection": {"enabled": True},
                "customer_update": {"address": "auto", "name": "auto"},
                "locale": "it",
                "subscription_data": {"metadata": {"user_id": str(current_user.id)}},
            },
        )
    except billing.StripeError as exc:
        logger.error("Stripe checkout: %s", exc)
        raise HTTPException(status_code=502, detail="Errore del sistema di pagamento")
    return RedirectUrl(url=session["url"])


@router.post("/portal", response_model=RedirectUrl)
async def create_portal(current_user: User = Depends(get_current_user)):
    _require_stripe()
    if not current_user.stripe_customer_id:
        raise HTTPException(status_code=404, detail="Nessun abbonamento online")
    try:
        portal = billing.stripe_request(
            "POST",
            "/billing_portal/sessions",
            {
                "customer": current_user.stripe_customer_id,
                "return_url": settings.PUBLIC_BASE_URL.rstrip("/") + "/",
            },
        )
    except billing.StripeError as exc:
        logger.error("Stripe portal: %s", exc)
        raise HTTPException(status_code=502, detail="Errore del sistema di pagamento")
    return RedirectUrl(url=portal["url"])


@router.post("/webhook", include_in_schema=False)
async def stripe_webhook(request: Request, db: Session = Depends(get_db)):
    payload = await request.body()
    try:
        event = billing.verify_webhook(
            payload, request.headers.get("Stripe-Signature", ""), settings.STRIPE_WEBHOOK_SECRET
        )
    except ValueError as exc:
        logger.warning("Webhook Stripe rifiutato: %s", exc)
        raise HTTPException(status_code=400, detail="Firma non valida")

    kind = event.get("type", "")
    obj = (event.get("data") or {}).get("object") or {}
    user: Optional[User] = None
    subscription = None

    if kind == "checkout.session.completed":
        ref = obj.get("client_reference_id")
        if ref:
            try:
                user = db.get(User, ref)
            except Exception:  # noqa: BLE001 - riferimento non UUID
                user = None
        if user is not None and obj.get("subscription"):
            if obj.get("customer"):
                user.stripe_customer_id = obj["customer"]
            try:
                subscription = billing.stripe_request("GET", f"/subscriptions/{obj['subscription']}")
            except billing.StripeError as exc:
                # Stripe ritenta il webhook se rispondiamo con errore
                logger.error("Stripe subscription fetch: %s", exc)
                raise HTTPException(status_code=502, detail="Stripe non raggiungibile")
    elif kind.startswith("customer.subscription."):
        subscription = obj
        customer = obj.get("customer")
        if customer:
            user = db.query(User).filter(User.stripe_customer_id == customer).first()

    if user is not None and subscription is not None:
        billing.apply_subscription(user, subscription)
        db.commit()
        logger.info("Abbonamento aggiornato user=%s status=%s", user.id, user.subscription_status)
    return {"received": True}

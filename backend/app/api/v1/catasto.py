"""Richieste al Catasto tramite fornitore a pagamento (app.core.catasto.provider).

Solo sui propri sopralluoghi (altrimenti 404). Contratto nel docstring di
``app.api.v1``. Ogni richiesta costa: il client deve mandare
``confirm_cost: true`` dopo aver mostrato il prezzo, e c'è un tetto mensile per
utente (``CATASTO_MONTHLY_LIMIT``).
"""
import logging
import uuid
from datetime import datetime
from typing import Any, Dict, List, Literal, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy.orm import Session

from app.api.v1 import get_current_user, get_db, require_active_plan
from app.api.v1.documents import MAX_DOCUMENTS_PER_SURVEY, _extract, _owned_survey
from app.core.catasto import provider as providers
from app.core.config import settings
from app.core.crypto import encrypt_document
from app.models.database import CatastoRequest, SurveyDocument, User

logger = logging.getLogger(__name__)

router = APIRouter(tags=["catasto"])

CatastoKind = Literal["visura", "elaborato_planimetrico", "estratto_mappa"]
_FILENAMES = {
    "visura": "visura",
    "elaborato_planimetrico": "elaborato_planimetrico",
    "estratto_mappa": "estratto_mappa",
}


class CatastoStatus(BaseModel):
    enabled: bool
    provider: Optional[str] = None
    sandbox: bool = False
    monthly_limit: int
    used_this_month: int
    prices: Dict[str, float] = {}


class CatastoRequestIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: CatastoKind
    tipo_catasto: Literal["F", "T"] = "F"
    provincia: str = Field(min_length=2, max_length=2)
    comune: str = Field(min_length=1, max_length=120)
    foglio: str = Field(min_length=1, max_length=10)
    particella: str = Field(min_length=1, max_length=20)
    sezione: Optional[str] = Field(default=None, max_length=10)
    sezione_urbana: Optional[str] = Field(default=None, max_length=10)
    subalterno: Optional[str] = Field(default=None, max_length=10)
    confirm_cost: bool

    @field_validator("provincia")
    @classmethod
    def _upper(cls, value: str) -> str:
        return value.strip().upper()

    @field_validator("confirm_cost")
    @classmethod
    def _must_confirm(cls, value: bool) -> bool:
        if value is not True:
            raise ValueError("la richiesta è a pagamento: confermare il costo")
        return value


class CatastoRequestOut(BaseModel):
    id: UUID
    survey_id: UUID
    kind: str
    status: str
    params: Optional[Dict[str, Any]] = None
    price_eur: Optional[float] = None
    error: Optional[str] = None
    document_id: Optional[UUID] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


def _month_start(now: datetime) -> datetime:
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def _used_this_month(db: Session, user: User) -> int:
    return (
        db.query(CatastoRequest)
        .filter(
            CatastoRequest.user_id == user.id,
            CatastoRequest.created_at >= _month_start(datetime.utcnow()),
            CatastoRequest.status != "failed",
        )
        .count()
    )


def _provider_or_409() -> providers.CatastoProvider:
    try:
        provider = providers.get_provider()
    except providers.ProviderError as exc:
        logger.error("Catasto: %s", exc)
        provider = None
    if provider is None:
        raise HTTPException(status_code=409, detail="Accesso al Catasto non attivo su questo server")
    return provider


@router.get("/catasto/status", response_model=CatastoStatus)
async def catasto_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        provider = providers.get_provider()
    except providers.ProviderError:
        provider = None
    return CatastoStatus(
        enabled=provider is not None,
        provider=provider.name if provider else None,
        sandbox=bool(provider) and settings.CATASTO_OPENAPI_SANDBOX,
        monthly_limit=settings.CATASTO_MONTHLY_LIMIT,
        used_this_month=_used_this_month(db, current_user),
        prices=provider.prices if provider else {},
    )


@router.post(
    "/surveys/{survey_id}/catasto/requests",
    response_model=CatastoRequestOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_catasto_request(
    survey_id: UUID,
    body: CatastoRequestIn,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    survey = _owned_survey(db, survey_id, current_user)
    require_active_plan(db, current_user)
    provider = _provider_or_409()
    if _used_this_month(db, current_user) >= settings.CATASTO_MONTHLY_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=f"Raggiunto il limite di {settings.CATASTO_MONTHLY_LIMIT} richieste catastali questo mese",
        )
    docs = db.query(SurveyDocument).filter(SurveyDocument.survey_id == survey.id).count()
    if docs >= MAX_DOCUMENTS_PER_SURVEY:
        raise HTTPException(
            status_code=409, detail=f"Massimo {MAX_DOCUMENTS_PER_SURVEY} documenti per sopralluogo"
        )

    params = body.model_dump(exclude={"kind", "confirm_cost"}, exclude_none=True)
    try:
        request_id = provider.submit(body.kind, params)
    except providers.ProviderError as exc:
        logger.warning("Catasto submit fallito: %s", exc)
        raise HTTPException(status_code=502, detail=str(exc))

    row = CatastoRequest(
        id=uuid.uuid4(),
        survey_id=survey.id,
        user_id=current_user.id,
        provider=provider.name,
        kind=body.kind,
        provider_request_id=request_id,
        status="pending",
        params=params,
        price_eur=provider.prices.get(body.kind),
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


@router.get("/surveys/{survey_id}/catasto/requests", response_model=List[CatastoRequestOut])
async def list_catasto_requests(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    survey = _owned_survey(db, survey_id, current_user)
    return (
        db.query(CatastoRequest)
        .filter(CatastoRequest.survey_id == survey.id)
        .order_by(CatastoRequest.created_at.desc())
        .all()
    )


@router.post("/catasto/requests/{request_id}/refresh", response_model=CatastoRequestOut)
async def refresh_catasto_request(
    request_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = (
        db.query(CatastoRequest)
        .filter(CatastoRequest.id == request_id, CatastoRequest.user_id == current_user.id)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Richiesta non trovata")
    if row.status != "pending":
        return row
    provider = _provider_or_409()
    try:
        result = provider.poll(row.kind, row.provider_request_id)
        if result.status == "done":
            pdf = provider.download(row.kind, row.provider_request_id)
            kind = providers.KIND_TO_DOCUMENT[row.kind]
            p = row.params or {}
            name = "_".join(
                str(x) for x in (_FILENAMES[row.kind], p.get("foglio"), p.get("particella"), p.get("subalterno")) if x
            )
            doc = SurveyDocument(
                id=uuid.uuid4(),
                survey_id=row.survey_id,
                uploaded_by=current_user.id,
                kind=kind,
                filename=f"{name}.pdf",
                mime_type="application/pdf",
                size_bytes=len(pdf),
                extracted=_extract(kind, "application/pdf", pdf),
                content=encrypt_document(pdf),
            )
            db.add(doc)
            db.flush()
            row.document_id = doc.id
            row.status = "done"
        elif result.status == "failed":
            row.status = "failed"
            row.error = (result.error or "Richiesta non evasa")[:255]
    except providers.ProviderError as exc:
        # errore transitorio: la richiesta resta pending, si può riprovare
        logger.warning("Catasto refresh %s: %s", row.id, exc)
        raise HTTPException(status_code=502, detail=str(exc))
    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return row

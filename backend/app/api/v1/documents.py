"""Documenti catastali allegati ai sopralluoghi + estrazione dalla visura.

Shared pieces (also used by app.api.v1.admin): ``DocumentMeta``,
``document_meta()`` and ``document_content_response()``. Endpoints: see the
spec docs/superpowers/specs/2026-10-18-catasto-admin-cened-design.md.
"""
import base64
import binascii
import logging
import uuid
from datetime import datetime
from typing import List, Literal, Optional
from urllib.parse import quote
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.api.v1 import get_current_user, get_db
from app.core.catasto import CadastralUnit
from app.core.catasto.visura import parse_visura_pdf
from app.models.database import Survey, SurveyDocument, User

logger = logging.getLogger(__name__)

router = APIRouter()

DocumentKind = Literal["visura", "planimetria", "mappa", "altro"]
MAX_DOCUMENT_BYTES = 10 * 1024 * 1024
MAX_DOCUMENTS_PER_SURVEY = 10


class UploaderInfo(BaseModel):
    id: UUID
    email: str
    name: str


class DocumentMeta(BaseModel):
    id: UUID
    survey_id: UUID
    kind: DocumentKind
    filename: str
    mime_type: str
    size_bytes: int
    uploaded_by: Optional[UploaderInfo] = None
    extracted: Optional[List[CadastralUnit]] = None
    created_at: datetime


def document_meta(doc: SurveyDocument, uploader=None) -> DocumentMeta:
    """Serialize a document row (never the content). ``uploader``: User or None."""
    return DocumentMeta(
        id=doc.id,
        survey_id=doc.survey_id,
        kind=doc.kind,
        filename=doc.filename,
        mime_type=doc.mime_type,
        size_bytes=doc.size_bytes,
        uploaded_by=(
            UploaderInfo(id=uploader.id, email=uploader.email, name=uploader.name)
            if uploader is not None
            else None
        ),
        extracted=doc.extracted,
        created_at=doc.created_at,
    )


def document_content_response(doc: SurveyDocument) -> Response:
    """Raw bytes as an attachment (RFC 5987 filename for non-ASCII names)."""
    return Response(
        content=doc.content,
        media_type=doc.mime_type,
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(doc.filename)}",
            "X-Content-Type-Options": "nosniff",
        },
    )


# ---------------------------------------------------------------------------
# Endpoints del tecnico (solo sui propri sopralluoghi: altrimenti 404)
# ---------------------------------------------------------------------------
class DocumentUpload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: DocumentKind
    filename: str = Field(min_length=1, max_length=255)
    content_base64: str


_MAGIC = (
    (b"%PDF-", "application/pdf"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG", "image/png"),
)


def sniff_mime(data: bytes) -> Optional[str]:
    """Tipo dai magic bytes (mai dal nome del file); None se non ammesso."""
    for magic, mime in _MAGIC:
        if data.startswith(magic):
            return mime
    return None


def _owned_survey(db: Session, survey_id: UUID, user: User) -> Survey:
    survey = (
        db.query(Survey)
        .filter(Survey.id == survey_id, Survey.user_id == user.id)
        .first()
    )
    if survey is None:
        raise HTTPException(status_code=404, detail="Survey not found")
    return survey


def _owned_document(db: Session, doc_id: UUID, user: User) -> SurveyDocument:
    doc = (
        db.query(SurveyDocument)
        .join(Survey, Survey.id == SurveyDocument.survey_id)
        .filter(SurveyDocument.id == doc_id, Survey.user_id == user.id)
        .first()
    )
    if doc is None:
        raise HTTPException(status_code=404, detail="Document not found")
    return doc


def _extract(kind: str, mime: str, data: bytes) -> Optional[list]:
    """Proposta di dati catastali: solo per visure PDF; errore del parser → []."""
    if kind != "visura" or mime != "application/pdf":
        return None
    try:
        return [u.model_dump(exclude_none=True) for u in parse_visura_pdf(data)]
    except Exception:  # noqa: BLE001 - il parser non deve far fallire l'upload
        logger.exception("Estrazione visura fallita")
        return []


@router.post(
    "/surveys/{survey_id}/documents",
    response_model=DocumentMeta,
    status_code=status.HTTP_201_CREATED,
)
async def upload_document(
    survey_id: UUID,
    body: DocumentUpload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    survey = _owned_survey(db, survey_id, current_user)
    try:
        data = base64.b64decode("".join(body.content_base64.split()), validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="content_base64 non valido")
    if len(data) > MAX_DOCUMENT_BYTES:
        raise HTTPException(status_code=413, detail="Documento oltre 10 MB")
    mime = sniff_mime(data)
    if mime is None:
        raise HTTPException(
            status_code=415, detail="Formato non supportato (solo PDF, JPEG, PNG)"
        )
    count = db.query(SurveyDocument).filter(SurveyDocument.survey_id == survey.id).count()
    if count >= MAX_DOCUMENTS_PER_SURVEY:
        raise HTTPException(
            status_code=409,
            detail=f"Massimo {MAX_DOCUMENTS_PER_SURVEY} documenti per sopralluogo",
        )

    doc = SurveyDocument(
        id=uuid.uuid4(),
        survey_id=survey.id,
        uploaded_by=current_user.id,
        kind=body.kind,
        filename=body.filename,
        mime_type=mime,
        size_bytes=len(data),
        content=data,
        extracted=_extract(body.kind, mime, data),
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return document_meta(doc, current_user)


@router.get("/surveys/{survey_id}/documents", response_model=List[DocumentMeta])
async def list_documents(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Documenti del sopralluogo, dal più vecchio (senza contenuto)."""
    survey = _owned_survey(db, survey_id, current_user)
    rows = (
        db.query(SurveyDocument, User)
        .outerjoin(User, User.id == SurveyDocument.uploaded_by)
        .filter(SurveyDocument.survey_id == survey.id)
        .order_by(SurveyDocument.created_at.asc(), SurveyDocument.id.asc())
        .all()
    )
    return [document_meta(doc, uploader) for doc, uploader in rows]


@router.get(
    "/documents/{doc_id}/content",
    response_class=Response,
    responses={200: {"content": {"application/pdf": {}, "image/jpeg": {}, "image/png": {}}}},
)
async def download_document(
    doc_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return document_content_response(_owned_document(db, doc_id, current_user))


@router.delete("/documents/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    doc_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.delete(_owned_document(db, doc_id, current_user))
    db.commit()
    return None

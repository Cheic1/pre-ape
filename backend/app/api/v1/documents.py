"""Documenti catastali allegati ai sopralluoghi + estrazione dalla visura.

Shared pieces (also used by app.api.v1.admin): ``DocumentMeta``,
``document_meta()`` and ``document_content_response()``. Endpoints: see the
spec docs/superpowers/specs/2026-10-18-catasto-admin-cened-design.md.
"""
from datetime import datetime
from typing import List, Literal, Optional
from urllib.parse import quote
from uuid import UUID

from fastapi import APIRouter, Response
from pydantic import BaseModel

from app.core.catasto import CadastralUnit
from app.models.database import SurveyDocument

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

"""CENED+2.0: GET /surveys/{id}/cened-sheet e GET /surveys/{id}/cened-xml.

Le stesse risposte per l'amministratore (sopralluoghi di altri utenti) sono in
``app.api.v1.admin`` e riusano :func:`cened_sheet_for` / :func:`cened_xml_response`.
"""
import io
import logging
import zipfile
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy.orm import Session, defer

from app.api.v1 import get_current_user, get_db
from app.api.v1.documents import document_meta
from app.core.cened.sheet import CenedSheet, build_cened_sheet
from app.core.cened.xml_export import build_calcolo_xml_20, build_cened_xml_12
from app.models.database import Survey, SurveyDocument, User

router = APIRouter()
logger = logging.getLogger(__name__)

CenedFormat = Literal["2.0", "1.2"]
FORMAT_QUERY = Query("2.0", description="2.0 = calcolo.xml, 1.2 = CENED+ 1.2")


def _owned_survey(db: Session, survey_id: UUID, user: User) -> Survey:
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    return survey


@router.get("/surveys/{survey_id}/cened-sheet", response_model=CenedSheet)
async def get_cened_sheet(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return cened_sheet_for(db, _owned_survey(db, survey_id, current_user))


def cened_sheet_for(db: Session, survey: Survey) -> CenedSheet:
    """Scheda CENED del sopralluogo, con l'elenco dei documenti caricati."""
    rows = (
        db.query(SurveyDocument, User)
        .outerjoin(User, User.id == SurveyDocument.uploaded_by)
        .options(defer(SurveyDocument.content))
        .filter(SurveyDocument.survey_id == survey.id)
        .order_by(SurveyDocument.created_at, SurveyDocument.id)
        .all()
    )
    documents = [document_meta(doc, uploader) for doc, uploader in rows]
    return build_cened_sheet(survey, documents)


@router.get("/surveys/{survey_id}/cened-xml")
async def get_cened_xml(
    survey_id: UUID,
    format: CenedFormat = FORMAT_QUERY,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """XML del sopralluogo dentro uno .zip, pronto per CENED+2.0 (stima preliminare).

    CENED importa solo archivi .zip: «File → Importa file XML 1.2» (format=1.2)
    o «File → Importa file XML» (format=2.0) estraggono l'unico XML contenuto.
    """
    return cened_xml_response(_owned_survey(db, survey_id, current_user), format)


def cened_xml_response(survey: Survey, format: CenedFormat) -> Response:
    """Lo .zip con l'XML CENED del sopralluogo (unico file dentro l'archivio)."""
    build = build_calcolo_xml_20 if format == "2.0" else build_cened_xml_12
    xml = build(survey)
    logger.info("cened-xml %s survey=%s defaults=%d missing=%d",
                format, survey.id, len(xml.defaults), len(xml.missing))
    suffix = "cened20" if format == "2.0" else "cened12"
    name = f"preape_{survey.id.hex[:8]}_{suffix}"
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(f"{name}.xml", xml.content)
    return Response(
        content=buffer.getvalue(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{name}.zip"'},
    )

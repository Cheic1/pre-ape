"""CENED+2.0: GET /surveys/{id}/cened-sheet e GET /surveys/{id}/cened-xml."""
import logging
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
    survey = _owned_survey(db, survey_id, current_user)
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
    format: Literal["2.0", "1.2"] = Query("2.0", description="2.0 = calcolo.xml, 1.2 = CENED+ 1.2"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """XML del sopralluogo da provare a importare in CENED+2.0 (stima preliminare)."""
    survey = _owned_survey(db, survey_id, current_user)
    build = build_calcolo_xml_20 if format == "2.0" else build_cened_xml_12
    xml = build(survey)
    logger.info("cened-xml %s survey=%s defaults=%d missing=%d",
                format, survey.id, len(xml.defaults), len(xml.missing))
    suffix = "cened20" if format == "2.0" else "cened12"
    filename = f"preape_{survey.id.hex[:8]}_{suffix}.xml"
    return Response(
        content=xml.content,
        media_type="application/xml",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )

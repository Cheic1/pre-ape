"""Scheda dati CENED+2.0: GET /surveys/{id}/cened-sheet."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, defer

from app.api.v1 import get_current_user, get_db
from app.api.v1.documents import document_meta
from app.core.cened.sheet import CenedSheet, build_cened_sheet
from app.models.database import Survey, SurveyDocument, User

router = APIRouter()


@router.get("/surveys/{survey_id}/cened-sheet", response_model=CenedSheet)
async def get_cened_sheet(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
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

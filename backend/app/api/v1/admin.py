"""Pannello amministratore: /admin/* (403 per i non admin), ogni azione nel registro.

Admin = email in ``settings.ADMIN_EMAILS`` (``app.api.v1.is_admin``). Every
endpoint except ``GET /admin/audit`` writes one ``AdminAuditLog`` row in the
same transaction as the action itself (reads included). Contract: spec
docs/superpowers/specs/2026-10-18-catasto-admin-cened-design.md, section 2.
"""
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func
from sqlalchemy.orm import Session, defer

from app.api.v1 import (
    SurveyResponse,
    SurveySummary,
    SurveyUpdate,
    _apply_score,
    _comune_name,
    _photo_count,
    get_current_user,
    get_db,
    is_admin,
)
from app.api.v1.documents import DocumentMeta, document_content_response, document_meta
from app.models.database import AdminAuditLog, PhotoAnalysis, Survey, SurveyDocument, User

router = APIRouter(prefix="/admin", tags=["admin"])


class AdminUser(BaseModel):
    id: UUID
    email: str
    name: str
    created_at: Optional[datetime] = None
    last_login: Optional[datetime] = None
    survey_count: int
    document_count: int
    is_admin: bool


class AuditEntry(BaseModel):
    id: UUID
    admin_email: str
    action: str
    target_type: Optional[str] = None
    target_id: Optional[str] = None
    detail: Optional[Dict[str, Any]] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    """401 without a valid token (get_current_user), 403 for non-admins."""
    if not is_admin(current_user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")
    return current_user


def _audit(
    db: Session,
    admin: User,
    action: str,
    target_type: Optional[str] = None,
    target_id: Any = None,
    detail: Optional[Dict[str, Any]] = None,
) -> None:
    """Stage an audit row; the caller commits it together with the action."""
    db.add(
        AdminAuditLog(
            id=uuid.uuid4(),
            admin_id=admin.id,
            admin_email=admin.email,
            action=action,
            target_type=target_type,
            target_id=str(target_id) if target_id is not None else None,
            detail=detail,
        )
    )


def _get_survey(db: Session, survey_id: UUID) -> Survey:
    survey = db.query(Survey).filter(Survey.id == survey_id).first()
    if survey is None:
        raise HTTPException(status_code=404, detail="Survey not found")
    return survey


def _get_document(db: Session, doc_id: UUID) -> SurveyDocument:
    doc = db.query(SurveyDocument).filter(SurveyDocument.id == doc_id).first()
    if doc is None:
        raise HTTPException(status_code=404, detail="Document not found")
    return doc


def _owner_email(db: Session, survey: Survey) -> Optional[str]:
    owner = db.get(User, survey.user_id) if survey.user_id else None
    return owner.email if owner else None


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
@router.get("/users", response_model=List[AdminUser])
async def list_users(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    survey_counts = dict(
        db.query(Survey.user_id, func.count(Survey.id)).group_by(Survey.user_id).all()
    )
    document_counts = dict(
        db.query(Survey.user_id, func.count(SurveyDocument.id))
        .join(SurveyDocument, SurveyDocument.survey_id == Survey.id)
        .group_by(Survey.user_id)
        .all()
    )
    users = db.query(User).order_by(User.email).all()
    result = [
        AdminUser(
            id=u.id,
            email=u.email,
            name=u.name,
            created_at=u.created_at,
            last_login=u.last_login,
            survey_count=survey_counts.get(u.id, 0),
            document_count=document_counts.get(u.id, 0),
            is_admin=is_admin(u),
        )
        for u in users
    ]
    _audit(db, admin, "list_users", detail={"count": len(result)})
    db.commit()
    return result


@router.get("/users/{user_id}/surveys", response_model=List[SurveySummary])
async def list_user_surveys(
    user_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    surveys = (
        db.query(Survey)
        .filter(Survey.user_id == user_id)
        .order_by(Survey.updated_at.desc())
        .all()
    )
    result = [
        SurveySummary(
            id=s.id,
            title=s.title,
            client_name=s.client_name,
            address=s.address,
            square_meters=s.square_meters,
            estimated_class=s.estimated_class,
            energy_score=s.energy_score,
            status=s.status or "draft",
            photo_count=_photo_count(s),
            comune=_comune_name(s),
            created_at=s.created_at,
            updated_at=s.updated_at,
        )
        for s in surveys
    ]
    _audit(db, admin, "list_user_surveys", "user", user.id, {"email": user.email})
    db.commit()
    return result


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: UUID,
    confirm_email: Optional[str] = Query(default=None, max_length=255),
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Delete a user with surveys, photo analyses and documents (cascade).

    Documents the user uploaded to other surveys stay (``uploaded_by`` -> NULL).
    """
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    if user.id == admin.id:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Cannot delete yourself")
    if (confirm_email or "").strip().lower() != user.email.lower():
        raise HTTPException(status_code=422, detail="confirm_email does not match the user's email")

    survey_ids = [sid for (sid,) in db.query(Survey.id).filter(Survey.user_id == user.id).all()]
    if survey_ids:
        # no DB cascade on photo_analyses; survey_documents cascade in the DB
        db.query(PhotoAnalysis).filter(PhotoAnalysis.survey_id.in_(survey_ids)).delete(
            synchronize_session=False
        )
        db.query(Survey).filter(Survey.id.in_(survey_ids)).delete(synchronize_session=False)
    _audit(
        db,
        admin,
        "delete_user",
        "user",
        user.id,
        {"email": user.email, "survey_count": len(survey_ids)},
    )
    db.query(User).filter(User.id == user.id).delete(synchronize_session=False)
    db.commit()
    return None


# ---------------------------------------------------------------------------
# Surveys
# ---------------------------------------------------------------------------
@router.get("/surveys/{survey_id}", response_model=SurveyResponse)
async def view_survey(
    survey_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    survey = _get_survey(db, survey_id)
    _audit(db, admin, "view_survey", "survey", survey.id, {"owner_email": _owner_email(db, survey)})
    db.commit()
    db.refresh(survey)
    return survey


@router.put("/surveys/{survey_id}", response_model=SurveyResponse)
async def update_survey(
    survey_id: UUID,
    survey_update: SurveyUpdate,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    survey = _get_survey(db, survey_id)
    update_data = survey_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        if key == "status" and value is None:
            continue  # same rule as PUT /surveys/{id}: null status = unchanged
        setattr(survey, key, value)
    _apply_score(survey)
    survey.updated_at = datetime.utcnow()
    _audit(
        db,
        admin,
        "update_survey",
        "survey",
        survey.id,
        {"owner_email": _owner_email(db, survey), "fields": sorted(update_data)},
    )
    db.commit()
    db.refresh(survey)
    return survey


@router.delete("/surveys/{survey_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_survey(
    survey_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    survey = _get_survey(db, survey_id)
    _audit(
        db,
        admin,
        "delete_survey",
        "survey",
        survey.id,
        {"owner_email": _owner_email(db, survey), "title": survey.title, "address": survey.address},
    )
    db.query(PhotoAnalysis).filter(PhotoAnalysis.survey_id == survey.id).delete()
    db.delete(survey)
    db.commit()
    return None


# ---------------------------------------------------------------------------
# Documents
# ---------------------------------------------------------------------------
@router.get("/surveys/{survey_id}/documents", response_model=List[DocumentMeta])
async def list_documents(
    survey_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    survey = _get_survey(db, survey_id)
    rows = (
        db.query(SurveyDocument, User)
        .options(defer(SurveyDocument.content))
        .outerjoin(User, User.id == SurveyDocument.uploaded_by)
        .filter(SurveyDocument.survey_id == survey.id)
        .order_by(SurveyDocument.created_at, SurveyDocument.id)
        .all()
    )
    result = [document_meta(doc, uploader) for doc, uploader in rows]
    _audit(db, admin, "list_documents", "survey", survey.id, {"count": len(result)})
    db.commit()
    return result


@router.get("/documents/{doc_id}/content")
async def download_document(
    doc_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    doc = _get_document(db, doc_id)
    response = document_content_response(doc)
    _audit(
        db,
        admin,
        "download_document",
        "document",
        doc.id,
        {"survey_id": str(doc.survey_id), "filename": doc.filename, "kind": doc.kind},
    )
    db.commit()
    return response


@router.delete("/documents/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    doc_id: UUID, admin: User = Depends(require_admin), db: Session = Depends(get_db)
):
    doc = _get_document(db, doc_id)
    _audit(
        db,
        admin,
        "delete_document",
        "document",
        doc.id,
        {"survey_id": str(doc.survey_id), "filename": doc.filename, "kind": doc.kind},
    )
    db.delete(doc)
    db.commit()
    return None


# ---------------------------------------------------------------------------
# Audit log (reading it is not logged)
# ---------------------------------------------------------------------------
@router.get("/audit", response_model=List[AuditEntry])
async def list_audit(
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    return (
        db.query(AdminAuditLog)
        .order_by(AdminAuditLog.created_at.desc(), AdminAuditLog.id)
        .offset(offset)
        .limit(limit)
        .all()
    )

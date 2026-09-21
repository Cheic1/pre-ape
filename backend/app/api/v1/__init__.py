"""Pre-APE API v1 Router"""
from fastapi import APIRouter, HTTPException, Depends, status, BackgroundTasks
from fastapi.security import OAuth2PasswordBearer
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
import uuid
import os
import asyncio
import logging
from datetime import datetime
from pydantic import BaseModel

from app.core.config import settings
from app.models.database import User, Survey, PhotoAnalysis

# Create router
router = APIRouter(prefix="/api/v1")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# OAuth2 scheme (placeholder for future auth)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

# Database dependency
def get_db():
    from app.models.database import SessionLocal
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Helper functions
def create_or_get_user(db: Session, user_info: Dict[str, Any]):
    email = user_info["email"]
    existing_user = db.query(User).filter(User.email == email).first()
    
    if existing_user:
        existing_user.name = user_info["name"]
        existing_user.picture = user_info.get("picture", existing_user.picture)
        existing_user.last_login = datetime.utcnow()
        db.commit()
        return existing_user
    
    new_user = User(
        id=uuid.uuid4(),
        email=email,
        name=user_info["name"],
        picture=user_info.get("picture", ""),
        google_id=user_info.get("sub")
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

# API Schemas
class SurveyBase(BaseModel):
    address: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    square_meters: Optional[float] = None
    avg_height: Optional[float] = None
    climate_zone: Optional[str] = None
    wall_thickness: Optional[str] = None
    window_frame: Optional[str] = None
    window_glass: Optional[str] = None
    heating_type: Optional[str] = None
    generator_type: Optional[str] = None
    generator_power_kw: Optional[float] = None
    generator_year: Optional[int] = None

class SurveyCreate(SurveyBase):
    pass

class SurveyUpdate(SurveyBase):
    pass

class SurveyResponse(SurveyBase):
    id: str
    estimated_class: Optional[str] = None
    energy_score: Optional[float] = None
    status: str
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class PhotoAnalysisBase(BaseModel):
    survey_id: str
    photo_type: str
    file_path: str
    raw_response: Optional[Dict[str, Any]] = None
    extracted_brand: Optional[str] = None
    extracted_model: Optional[str] = None
    extracted_power_kw: Optional[float] = None
    extracted_year: Optional[int] = None
    quality_score: Optional[float] = None
    is_readable: Optional[bool] = None

class PhotoAnalysisCreate(PhotoAnalysisBase):
    pass

class PhotoAnalysisResponse(PhotoAnalysisBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True

# API Endpoints
@router.post("/surveys", response_model=SurveyResponse, status_code=status.HTTP_201_CREATED)
async def create_survey(
    survey: SurveyCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    try:
        db_survey = Survey(
            id=uuid.uuid4(),
            **survey.model_dump(exclude_unset=True) if hasattr(survey, 'model_dump') else survey.dict(exclude_unset=True)
        )
        
        db.add(db_survey)
        db.commit()
        db.refresh(db_survey)
        
        # Background task for AI analysis
        if survey.generator_type:
            background_tasks.add_task(analyze_generator_photo, db_survey.id)
        
        logger.info(f"Created survey with ID: {db_survey.id}")
        return {
            "id": str(db_survey.id),
            "address": db_survey.address,
            "latitude": db_survey.latitude,
            "longitude": db_survey.longitude,
            "square_meters": db_survey.square_meters,
            "avg_height": db_survey.avg_height,
            "climate_zone": db_survey.climate_zone,
            "wall_thickness": db_survey.wall_thickness,
            "window_frame": db_survey.window_frame,
            "window_glass": db_survey.window_glass,
            "heating_type": db_survey.heating_type,
            "generator_type": db_survey.generator_type,
            "generator_power_kw": db_survey.generator_power_kw,
            "generator_year": db_survey.generator_year,
            "estimated_class": db_survey.estimated_class,
            "energy_score": db_survey.energy_score,
            "status": db_survey.status,
            "created_at": db_survey.created_at,
            "updated_at": db_survey.updated_at,
        }
    except Exception as e:
        logger.error(f"Error creating survey: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/surveys/{survey_id}", response_model=SurveyResponse)
async def get_survey(survey_id: str, db: Session = Depends(get_db)):
    try:
        uid = uuid.UUID(survey_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid UUID format")
    
    survey = db.query(Survey).filter(Survey.id == uid).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    # Convert to dict to avoid Pydantic issues
    from pydantic import BaseModel
    return {
        "id": str(survey.id),
        "address": survey.address,
        "latitude": survey.latitude,
        "longitude": survey.longitude,
        "square_meters": survey.square_meters,
        "avg_height": survey.avg_height,
        "climate_zone": survey.climate_zone,
        "wall_thickness": survey.wall_thickness,
        "window_frame": survey.window_frame,
        "window_glass": survey.window_glass,
        "heating_type": survey.heating_type,
        "generator_type": survey.generator_type,
        "generator_power_kw": survey.generator_power_kw,
        "generator_year": survey.generator_year,
        "estimated_class": survey.estimated_class,
        "energy_score": survey.energy_score,
        "status": survey.status,
        "created_at": survey.created_at,
        "updated_at": survey.updated_at,
    }

@router.put("/surveys/{survey_id}", response_model=SurveyResponse)
async def update_survey(
    survey_id: str,
    survey_update: SurveyUpdate,
    db: Session = Depends(get_db)
):
    try:
        uid = uuid.UUID(survey_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid UUID format")
    
    survey = db.query(Survey).filter(Survey.id == uid).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    update_data = survey_update.model_dump(exclude_unset=True) if hasattr(survey_update, 'model_dump') else survey_update.dict(exclude_unset=True)
    for key, value in update_data.items():
        setattr(survey, key, value)
    
    survey.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(survey)
    return {
        "id": str(survey.id),
        "address": survey.address,
        "latitude": survey.latitude,
        "longitude": survey.longitude,
        "square_meters": survey.square_meters,
        "avg_height": survey.avg_height,
        "climate_zone": survey.climate_zone,
        "wall_thickness": survey.wall_thickness,
        "window_frame": survey.window_frame,
        "window_glass": survey.window_glass,
        "heating_type": survey.heating_type,
        "generator_type": survey.generator_type,
        "generator_power_kw": survey.generator_power_kw,
        "generator_year": survey.generator_year,
        "estimated_class": survey.estimated_class,
        "energy_score": survey.energy_score,
        "status": survey.status,
        "created_at": survey.created_at,
        "updated_at": survey.updated_at,
    }

@router.delete("/surveys/{survey_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_survey(survey_id: str, db: Session = Depends(get_db)):
    try:
        uid = uuid.UUID(survey_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid UUID format")
    
    survey = db.query(Survey).filter(Survey.id == uid).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    db.delete(survey)
    db.commit()
    return None

@router.post("/photo-analyses", response_model=PhotoAnalysisResponse, status_code=status.HTTP_201_CREATED)
async def create_photo_analysis(
    analysis: PhotoAnalysisCreate,
    db: Session = Depends(get_db)
):
    try:
        db_analysis = PhotoAnalysis(
            id=uuid.uuid4(),
            **analysis.model_dump(exclude_unset=True) if hasattr(analysis, 'model_dump') else analysis.dict(exclude_unset=True)
        )
        
        db.add(db_analysis)
        db.commit()
        db.refresh(db_analysis)
        
        logger.info(f"Created photo analysis with ID: {db_analysis.id}")
        return db_analysis
    except Exception as e:
        logger.error(f"Error creating photo analysis: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/surveys/{survey_id}/photo-analyses", response_model=List[PhotoAnalysisResponse])
async def get_survey_photo_analyses(survey_id: str, db: Session = Depends(get_db)):
    try:
        uid = uuid.UUID(survey_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid UUID format")
    
    photo_analyses = db.query(PhotoAnalysis).filter(
        PhotoAnalysis.survey_id == uid
    ).all()
    return photo_analyses

@router.get("/surveys/{survey_id}/results")
async def get_survey_results(survey_id: str, db: Session = Depends(get_db)):
    try:
        uid = uuid.UUID(survey_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid UUID format")
    
    survey = db.query(Survey).filter(Survey.id == uid).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    results = {
        "survey_id": str(survey.id),
        "estimated_class": survey.estimated_class,
        "energy_score": survey.energy_score,
        "final_score": (survey.energy_score or 0) * 1.5,
        "geo_location": {
            "address": survey.address,
            "latitude": survey.latitude,
            "longitude": survey.longitude
        },
        "building_data": {
            "square_meters": survey.square_meters,
            "avg_height": survey.avg_height,
            "wall_thickness": survey.wall_thickness,
            "window_frame": survey.window_frame,
            "window_glass": survey.window_glass
        },
        "systems": {
            "heating_type": survey.heating_type,
            "generator_type": survey.generator_type,
            "generator_power_kw": survey.generator_power_kw,
            "generator_year": survey.generator_year
        },
        "photo_count": len(survey.photo_paths) if survey.photo_paths else 0,
        "status": survey.status,
        "created_at": survey.created_at,
        "updated_at": survey.updated_at
    }
    
    return results

async def analyze_generator_photo(survey_id: str):
    logger.info(f"Starting AI analysis for survey {survey_id}")
    
    try:
        # TODO: Implement AI photo analysis
        # This would involve:
        # 1. Loading the photo file
        # 2. Sending to AI model (LLaVA via Ollama)
        # 3. Parsing the response
        # 4. Updating the survey with extracted data
        
        await asyncio.sleep(1)  # Simulate processing time
        
        logger.info(f"Completed AI analysis for survey {survey_id}")
    except Exception as e:
        logger.error(f"Error in AI analysis for survey {survey_id}: {str(e)}")
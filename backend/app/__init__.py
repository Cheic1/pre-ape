from fastapi import FastAPI, HTTPException, Depends, status, BackgroundTasks
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
from app.models.database import Base, SessionLocal, User, Survey, PhotoAnalysis

app = FastAPI(
    title="Pre-APE API",
    description="API for Pre-APE - Preliminary Energy Performance Assessment",
    version="1.0.0",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# OAuth2 scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/v1/auth/login")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database dependency
def get_db():
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
@app.post("/api/v1/surveys", response_model=SurveyResponse, status_code=status.HTTP_201_CREATED)
async def create_survey(
    survey: SurveyCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    try:
        db_survey = Survey(
            id=uuid.uuid4(),
            **survey.dict(exclude_unset=True)
        )
        
        db.add(db_survey)
        db.commit()
        db.refresh(db_survey)
        
        # Background task for AI analysis
        if survey.generator_type:
            background_tasks.add_task(analyze_generator_photo, db_survey.id)
        
        logger.info(f"Created survey with ID: {db_survey.id}")
        return db_survey
    except Exception as e:
        logger.error(f"Error creating survey: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/surveys/{survey_id}", response_model=SurveyResponse)
async def get_survey(survey_id: str, db: Session = Depends(get_db)):
    survey = db.query(Survey).filter(Survey.id == uuid.UUID(survey_id)).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    return survey

@app.put("/api/v1/surveys/{survey_id}", response_model=SurveyResponse)
async def update_survey(
    survey_id: str,
    survey_update: SurveyUpdate,
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(Survey.id == uuid.UUID(survey_id)).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    for key, value in survey_update.dict(exclude_unset=True).items():
        setattr(survey, key, value)
    
    survey.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(survey)
    return survey

@app.delete("/api/v1/surveys/{survey_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_survey(survey_id: str, db: Session = Depends(get_db)):
    survey = db.query(Survey).filter(Survey.id == uuid.UUID(survey_id)).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    db.delete(survey)
    db.commit()
    return None

@app.post("/api/v1/photo-analyses", response_model=PhotoAnalysisResponse, status_code=status.HTTP_201_CREATED)
async def create_photo_analysis(
    analysis: PhotoAnalysisCreate,
    db: Session = Depends(get_db)
):
    try:
        db_analysis = PhotoAnalysis(
            id=uuid.uuid4(),
            **analysis.dict(exclude_unset=True)
        )
        
        db.add(db_analysis)
        db.commit()
        db.refresh(db_analysis)
        
        logger.info(f"Created photo analysis with ID: {db_analysis.id}")
        return db_analysis
    except Exception as e:
        logger.error(f"Error creating photo analysis: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/v1/surveys/{survey_id}/photo-analyses", response_model=List[PhotoAnalysisResponse])
async def get_survey_photo_analyses(survey_id: str, db: Session = Depends(get_db)):
    photo_analyses = db.query(PhotoAnalysis).filter(
        PhotoAnalysis.survey_id == uuid.UUID(survey_id)
    ).all()
    return photo_analyses

@app.get("/api/v1/surveys/{survey_id}/results")
async def get_survey_results(survey_id: str, db: Session = Depends(get_db)):
    survey = db.query(Survey).filter(Survey.id == uuid.UUID(survey_id)).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    
    # Calculate final results
    results = {
        "survey_id": str(survey.id),
        "estimated_class": survey.estimated_class,
        "energy_score": survey.energy_score,
        "final_score": (survey.energy_score or 0) * 1.5,  # Simple calculation for now
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
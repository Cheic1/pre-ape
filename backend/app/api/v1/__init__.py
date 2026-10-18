"""Pre-APE API v1 Router.

=============================================================================
 MINIMAL API CONTRACT (single source of truth: GET /openapi.json)
 Consumed by the Flutter client (P1-A3: lib/services/api_client.dart).
=============================================================================

Authentication
  POST /api/v1/auth/register  {email, password(>=8), name?}
      -> 201 {access_token, token_type: "bearer", user_id, email, name}  (409 if email taken)
  POST /api/v1/auth/login     {email, password}
      -> 200 {access_token, token_type: "bearer", user_id, email, name}  (401 if wrong)
  Every /surveys and /photo-analyses call requires the header:
      Authorization: Bearer <access_token>
  The scheme is matched strictly (uppercase `Bearer`): `Token x`, `bearer x`
  and scheme-less headers -> 401.
  Missing/invalid/expired token -> 401 + WWW-Authenticate: Bearer.
  /auth/* is rate limited: AUTH_RATE_LIMIT_PER_MINUTE per client IP per 60 s -> 429.

Resource: Survey (JSON)
  {id: uuid, title?, client_name?, notes?, address?, latitude?, longitude?,
   square_meters?, avg_height?, climate_zone?, wall_thickness?, window_frame?,
   window_glass?, heating_type?, generator_type?, generator_power_kw?,
   generator_year?, building?: BuildingInputs, photos?: {slot: data-URL},
   additional_photos?: [data-URL], estimated_class?, energy_score?,
   energy_result?: EnergyResult, status: "draft" | "completed" | "exported",
   created_at: datetime, updated_at: datetime}
  `building` holds every input of the energy model (app.core.energy.inputs,
  extra="forbid"); the flat wall_/window_/heating_/generator_ columns are the
  first MVP's inputs, still read as a fallback for old surveys.
  estimated_class / energy_score / energy_result / climate_zone are computed by
  the server on every create/update (app.core.energy): sending the first three
  to POST/PUT /surveys -> 422 (input models use extra="forbid").
  Photos are data:image/(jpeg|png|webp);base64 URLs, capped per photo and count.

Energy estimate (DM 26/06/2015 classification, UNI/TS 11300 simplified)
  POST /api/v1/estimate  {building?, square_meters?, avg_height?, address?,
                          latitude?, longitude?}  -> 200 EnergyResult (live preview)
  GET  /api/v1/climate/comuni?q=mil           -> 200 [{comune, provincia, zona, gradi_giorno…}]
  GET  /api/v1/climate/resolve?address=&lat=&lon= -> 200 comune | 404

Endpoints (path ids are UUIDs -> 422 when malformed, per-field validation)
  GET    /api/v1/surveys                     -> 200 [SurveySummary] (caller's, newest first)
  POST   /api/v1/surveys                     -> 201 Survey (stored with user_id = caller)
  GET    /api/v1/surveys/{id}                -> 200 Survey | 404
  PUT    /api/v1/surveys/{id}                -> 200 Survey | 404
  DELETE /api/v1/surveys/{id}                -> 204 | 404
  GET    /api/v1/surveys/{id}/results        -> 200 results | 404
  GET    /api/v1/surveys/{id}/photo-analyses -> 200 [PhotoAnalysis] | 404
  POST   /api/v1/photo-analyses              -> 201 | 404 (target survey must be owned)

Authorization / IDOR (P1-A1 AC-3)
  Every survey read/update/delete filters on user_id: a survey belonging to
  another user answers 404 (no existence oracle), never 200. Creation always
  stamps user_id with the authenticated caller.

Errors: FastAPI default shape {"detail": ...} — 422 validation, 401 auth,
404 not found OR not owned, 409 duplicate email, 429 rate limited.
"""
from fastapi import APIRouter, HTTPException, Depends, status, BackgroundTasks, Request
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from typing import List, Literal, Optional, Dict, Any
from uuid import UUID
import uuid
import asyncio
import logging
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.core import energy
from app.core.catasto import CadastralUnit, MAX_CADASTRAL_UNITS
from app.core.energy import BuildingInputs, climate
from app.core.config import settings
from app.core.rate_limit import auth_rate_limiter, client_ip
from app.core.security import (
    create_access_token,
    decode_token,
    dummy_verify_async,
    hash_password,
    verify_password_async,
)
from app.models.database import User, Survey, PhotoAnalysis

# Create router
router = APIRouter(prefix="/api/v1")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Bearer scheme for Swagger "Authorize" and OpenAPI (manual 401 below so the
# WWW-Authenticate header is always present per RFC 6750).
# Extraction is deliberately strict (M2 contract): only the exact uppercase
# `Bearer ` prefix is accepted — FastAPI's default matches the scheme
# case-insensitively, which would let `bearer x` through; `Token x`,
# `bearer x`, `BEARER x` and scheme-less headers must all answer 401.
class _StrictBearerScheme(OAuth2PasswordBearer):
    async def __call__(self, request: Request) -> Optional[str]:
        authorization = request.headers.get("Authorization")
        if not authorization or not authorization.startswith("Bearer "):
            return None  # auto_error=False -> get_current_user raises the 401
        _, _, param = authorization.partition(" ")
        return param or None


oauth2_scheme = _StrictBearerScheme(tokenUrl="/api/v1/auth/login", auto_error=False)

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

# ---------------------------------------------------------------------------
# Auth schemas & dependencies (P1-A1: JWT + ownership)
# ---------------------------------------------------------------------------
class RegisterRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255, examples=["user@example.com"])
    password: str = Field(min_length=8, max_length=128, examples=["S3cure-Pass!"])
    name: Optional[str] = Field(default=None, max_length=255)

class LoginRequest(BaseModel):
    email: str = Field(min_length=5, max_length=255)
    password: str = Field(min_length=1, max_length=128)

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: UUID
    email: str
    name: str
    is_admin: bool = False

_unauthorized = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Not authenticated",
    headers={"WWW-Authenticate": "Bearer"},
)

def rate_limit_auth(request: Request) -> None:
    """In-memory sliding-window rate limit for /auth/* (per client IP).

    Key source is proxy-aware (M1): ``CF-Connecting-IP`` only behind a loopback
    proxy (cloudflared), otherwise the socket peer — see app.core.rate_limit.
    """
    key = f"auth:{client_ip(request)}"
    if not auth_rate_limiter.allow(key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Rate limit exceeded for auth endpoints",
            headers={"Retry-After": "60"},
        )

def get_current_user(
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Resolve the JWT bearer token to an existing user (401 otherwise)."""
    if not token:
        raise _unauthorized
    try:
        user_id = decode_token(token)
    except Exception:  # invalid signature, expired, malformed sub...
        raise _unauthorized
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise _unauthorized
    return user

def is_admin(user: User) -> bool:
    """Admin = email listed in settings.ADMIN_EMAILS (no UI to grant the role)."""
    return bool(user.email) and user.email.lower() in settings.admin_emails


# API Schemas
# Photo limits (MVP: photos travel inline as data-URLs and are stored in the
# survey row). The client already downsizes to ~1600px / JPEG q0.82 (~500 KB).
MAX_PHOTO_DATA_URL_CHARS = 1_000_000  # ~730 KB decoded
MAX_PHOTO_SLOTS = 8
MAX_ADDITIONAL_PHOTOS = 6
_ALLOWED_PHOTO_PREFIXES = (
    "data:image/jpeg;base64,",
    "data:image/png;base64,",
    "data:image/webp;base64,",
)


def _check_photo(value: str) -> str:
    if not isinstance(value, str) or not value.startswith(_ALLOWED_PHOTO_PREFIXES):
        raise ValueError("photo must be a data:image/(jpeg|png|webp);base64 URL")
    if len(value) > MAX_PHOTO_DATA_URL_CHARS:
        raise ValueError("photo too large")
    return value


SurveyStatus = Literal["draft", "completed", "exported"]


class SurveyBase(BaseModel):
    title: Optional[str] = Field(default=None, max_length=255)
    client_name: Optional[str] = Field(default=None, max_length=255)
    notes: Optional[str] = Field(default=None, max_length=10_000)
    address: Optional[str] = Field(default=None, max_length=512)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)
    square_meters: Optional[float] = Field(default=None, ge=0, le=100_000)
    avg_height: Optional[float] = Field(default=None, ge=0, le=100)
    climate_zone: Optional[str] = Field(default=None, max_length=10)
    wall_thickness: Optional[str] = Field(default=None, max_length=20)
    window_frame: Optional[str] = Field(default=None, max_length=20)
    window_glass: Optional[str] = Field(default=None, max_length=20)
    heating_type: Optional[str] = Field(default=None, max_length=50)
    generator_type: Optional[str] = Field(default=None, max_length=50)
    generator_power_kw: Optional[float] = Field(default=None, ge=0)
    generator_year: Optional[int] = Field(default=None, ge=1900, le=2100)
    building: Optional[BuildingInputs] = None
    cadastral: Optional[List[CadastralUnit]] = Field(default=None, max_length=MAX_CADASTRAL_UNITS)
    photos: Optional[Dict[str, str]] = None
    additional_photos: Optional[List[str]] = None
    status: Optional[SurveyStatus] = None


class _SurveyInput(SurveyBase):
    """Input create/update: self-describing contract — unknown keys are
    rejected with 422 instead of being silently dropped, in particular the
    computed fields ``estimated_class`` / ``energy_score`` (read-only, M1)."""
    model_config = ConfigDict(extra="forbid")

    @field_validator("photos")
    @classmethod
    def _validate_photos(cls, value):
        if value is None:
            return value
        if len(value) > MAX_PHOTO_SLOTS:
            raise ValueError(f"at most {MAX_PHOTO_SLOTS} photo slots")
        for slot, photo in value.items():
            if not slot or len(slot) > 40:
                raise ValueError("photo slot label must be 1-40 chars")
            _check_photo(photo)
        return value

    @field_validator("additional_photos")
    @classmethod
    def _validate_additional(cls, value):
        if value is None:
            return value
        if len(value) > MAX_ADDITIONAL_PHOTOS:
            raise ValueError(f"at most {MAX_ADDITIONAL_PHOTOS} additional photos")
        for photo in value:
            _check_photo(photo)
        return value


class SurveyCreate(_SurveyInput):
    pass


class SurveyUpdate(_SurveyInput):
    pass


class SurveyResponse(SurveyBase):
    id: UUID
    estimated_class: Optional[str] = None
    energy_score: Optional[float] = None
    energy_result: Optional[Dict[str, Any]] = None
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class SurveySummary(BaseModel):
    """Lightweight row for GET /surveys (no photo payloads)."""
    id: UUID
    title: Optional[str] = None
    client_name: Optional[str] = None
    address: Optional[str] = None
    square_meters: Optional[float] = None
    estimated_class: Optional[str] = None
    energy_score: Optional[float] = None
    status: str
    photo_count: int = 0
    comune: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class EstimateRequest(BaseModel):
    """Body of POST /estimate: the energy-relevant subset of a survey."""
    model_config = ConfigDict(extra="forbid")

    building: Optional[BuildingInputs] = None
    square_meters: Optional[float] = Field(default=None, ge=0, le=100_000)
    avg_height: Optional[float] = Field(default=None, ge=0, le=100)
    address: Optional[str] = Field(default=None, max_length=512)
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


def _photo_count(survey: Survey) -> int:
    return len(survey.photos or {}) + len(survey.additional_photos or [])


def _comune_name(survey: Survey) -> Optional[str]:
    comune = ((survey.energy_result or {}).get("clima") or {}).get("comune")
    return comune.get("comune") if isinstance(comune, dict) else None


def _building_of(survey: Survey) -> BuildingInputs:
    try:
        return BuildingInputs.model_validate(survey.building or {})
    except ValueError:  # stored by an older schema: ignore what no longer validates
        logger.warning("Survey %s: building inputs no longer valid, using defaults", survey.id)
        return BuildingInputs()


def _apply_score(survey: Survey) -> None:
    """Server-side energy estimate (app.core.energy), stored with the survey."""
    result = energy.compute(
        _building_of(survey),
        square_meters=survey.square_meters,
        avg_height=survey.avg_height,
        address=survey.address,
        latitude=survey.latitude,
        longitude=survey.longitude,
        legacy={
            "wall_thickness": survey.wall_thickness,
            "window_frame": survey.window_frame,
            "window_glass": survey.window_glass,
            "heating_type": survey.heating_type,
            "generator_type": survey.generator_type,
            "generator_year": survey.generator_year,
        },
    )
    survey.energy_result = result
    survey.energy_score = result["punteggio"]
    survey.estimated_class = result["classe"]
    survey.climate_zone = result["clima"]["zona"]

class PhotoAnalysisBase(BaseModel):
    survey_id: UUID
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
    id: UUID
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# ---------------------------------------------------------------------------
# Auth endpoints (rate limited)
# ---------------------------------------------------------------------------
@router.post(
    "/auth/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    responses={429: {"description": "Rate limit exceeded"}},
)
async def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
    _rate_limit: None = Depends(rate_limit_auth),
):
    email = payload.email.strip().lower()
    if "@" not in email or email.startswith("@") or email.endswith("@"):
        raise HTTPException(status_code=422, detail="Invalid email format")

    existing = db.query(User).filter(User.email == email).first()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")

    user = User(
        id=uuid.uuid4(),
        email=email,
        name=(payload.name or email.split("@", 1)[0])[:255],
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        # unique email race with a concurrent register
        db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")
    db.refresh(user)
    logger.info(f"Registered user {user.id}")
    return TokenResponse(
        access_token=create_access_token(user.id),
        user_id=user.id,
        email=user.email,
        name=user.name,
        is_admin=is_admin(user),
    )

@router.post(
    "/auth/login",
    response_model=TokenResponse,
    responses={429: {"description": "Rate limit exceeded"}},
)
async def login(
    payload: LoginRequest,
    db: Session = Depends(get_db),
    _rate_limit: None = Depends(rate_limit_auth),
):
    email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == email).first()
    stored_hash = user.password_hash if user is not None else None
    if stored_hash:
        # PBKDF2 (600k) runs in a worker thread: never block the event loop (M1)
        password_ok = await verify_password_async(payload.password, stored_hash)
    else:
        # equal PBKDF2 cost for unknown accounts -> no timing-based enumeration
        await dummy_verify_async(payload.password)
        password_ok = False
    # uniform message: no user enumeration
    if not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user.last_login = datetime.utcnow()
    db.commit()
    return TokenResponse(
        access_token=create_access_token(user.id),
        user_id=user.id,
        email=user.email,
        name=user.name,
        is_admin=is_admin(user),
    )

# API Endpoints (all require Authorization: Bearer <JWT>)
@router.post("/surveys", response_model=SurveyResponse, status_code=status.HTTP_201_CREATED)
async def create_survey(
    survey: SurveyCreate,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    db_survey = Survey(
        id=uuid.uuid4(),
        user_id=current_user.id,
        **survey.model_dump(exclude_unset=True, exclude_none=True),
    )
    _apply_score(db_survey)
    db.add(db_survey)
    db.commit()
    db.refresh(db_survey)

    # Background task for AI analysis
    if survey.generator_type:
        background_tasks.add_task(analyze_generator_photo, db_survey.id)

    logger.info(f"Created survey with ID: {db_survey.id} for user {current_user.id}")
    return db_survey

@router.get("/surveys", response_model=List[SurveySummary])
async def list_surveys(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Caller's surveys, most recently updated first (no photo payloads)."""
    surveys = (
        db.query(Survey)
        .filter(Survey.user_id == current_user.id)
        .order_by(Survey.updated_at.desc())
        .all()
    )
    return [
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

@router.get("/surveys/{survey_id}", response_model=SurveyResponse)
async def get_survey(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")
    return survey

@router.put("/surveys/{survey_id}", response_model=SurveyResponse)
async def update_survey(
    survey_id: UUID,
    survey_update: SurveyUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")

    update_data = survey_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        if key == "status" and value is None:
            continue  # status is NOT NULL in practice: null means "unchanged"
        setattr(survey, key, value)

    _apply_score(survey)
    survey.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(survey)
    return survey

@router.delete("/surveys/{survey_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_survey(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")

    db.query(PhotoAnalysis).filter(PhotoAnalysis.survey_id == survey.id).delete()
    db.delete(survey)
    db.commit()
    return None

@router.post("/photo-analyses", response_model=PhotoAnalysisResponse, status_code=status.HTTP_201_CREATED)
async def create_photo_analysis(
    analysis: PhotoAnalysisCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Ownership check on the target survey closes the IDOR on this sub-resource
    survey = db.query(Survey).filter(
        Survey.id == analysis.survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")

    db_analysis = PhotoAnalysis(
        id=uuid.uuid4(),
        **analysis.model_dump(),
    )
    db.add(db_analysis)
    db.commit()
    db.refresh(db_analysis)

    logger.info(f"Created photo analysis with ID: {db_analysis.id}")
    return db_analysis

@router.get("/surveys/{survey_id}/photo-analyses", response_model=List[PhotoAnalysisResponse])
async def get_survey_photo_analyses(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")

    photo_analyses = db.query(PhotoAnalysis).filter(
        PhotoAnalysis.survey_id == survey_id
    ).all()
    return photo_analyses

@router.get("/surveys/{survey_id}/results")
async def get_survey_results(
    survey_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    survey = db.query(Survey).filter(
        Survey.id == survey_id,
        Survey.user_id == current_user.id,
    ).first()
    if not survey:
        raise HTTPException(status_code=404, detail="Survey not found")

    # Calculate final results
    results = {
        "survey_id": str(survey.id),
        "estimated_class": survey.estimated_class,
        "energy_score": survey.energy_score,
        "final_score": survey.energy_score or 0.0,
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
        "energy_result": survey.energy_result,
        "photo_count": _photo_count(survey),
        "status": survey.status,
        "created_at": survey.created_at,
        "updated_at": survey.updated_at
    }

    return results

@router.post("/estimate")
async def estimate(
    payload: EstimateRequest,
    current_user: User = Depends(get_current_user),
) -> Dict[str, Any]:
    """Live estimate for the wizard (nothing is stored)."""
    return energy.compute(
        payload.building,
        square_meters=payload.square_meters,
        avg_height=payload.avg_height,
        address=payload.address,
        latitude=payload.latitude,
        longitude=payload.longitude,
    )


@router.get("/climate/comuni")
async def search_comuni(
    q: str,
    current_user: User = Depends(get_current_user),
) -> List[Dict[str, Any]]:
    """Autocomplete: comuni whose name starts with / contains ``q``."""
    return [c.as_dict() for c in climate.search(q[:80])]


@router.get("/climate/resolve")
async def resolve_comune(
    address: Optional[str] = None,
    lat: Optional[float] = None,
    lon: Optional[float] = None,
    current_user: User = Depends(get_current_user),
) -> Dict[str, Any]:
    """Comune (and its climate data) for a geocoded address / coordinates."""
    found = climate.resolve(address[:512] if address else None, lat, lon)
    if found is None:
        raise HTTPException(status_code=404, detail="Comune non individuato")
    return found.as_dict()


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


# Sub-routers (imported last: they depend on get_db / get_current_user above).
from app.api.v1 import admin, cened, documents  # noqa: E402

router.include_router(documents.router)
router.include_router(admin.router)
router.include_router(cened.router)

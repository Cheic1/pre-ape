import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, Text, ForeignKey, JSON, create_engine
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship, sessionmaker, declarative_base
from app.core.config import settings

# Create database engine
def _normalize_db_url(url: str) -> str:
    # Heroku-style URLs (Render, Neon dashboards) use the legacy scheme that
    # SQLAlchemy 2 no longer accepts.
    if url.startswith("postgres://"):
        return "postgresql://" + url[len("postgres://"):]
    return url


# pool_pre_ping: managed Postgres (Neon, Render) closes idle connections.
engine = create_engine(_normalize_db_url(settings.DATABASE_URL), pool_pre_ping=True)

# Create session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class for models
Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, index=True, nullable=False)
    name = Column(String(255), nullable=False)
    picture = Column(Text)
    google_id = Column(String(255), unique=True, index=True)
    # JWT login (nullable: pre-existing rows have no password until they re-register)
    password_hash = Column(String(255))
    created_at = Column(DateTime, default=datetime.utcnow)
    last_login = Column(DateTime)
    
    surveys = relationship("Survey", back_populates="user")


class Survey(Base):
    __tablename__ = "surveys"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    
    # Intestazione pratica (cliente / riferimento) + note libere del tecnico
    title = Column(String(255))
    client_name = Column(String(255))
    notes = Column(Text)

    # Step 1: Dati Generali
    address = Column(String(512))
    latitude = Column(Float)
    longitude = Column(Float)
    square_meters = Column(Float)
    avg_height = Column(Float)
    climate_zone = Column(String(10))
    
    # Step 2: Involucro
    wall_thickness = Column(String(20))
    window_frame = Column(String(20))
    window_glass = Column(String(20))
    
    # Step 3: Impianti
    heating_type = Column(String(50))
    generator_type = Column(String(50))
    generator_power_kw = Column(Float)
    generator_year = Column(Integer)
    
    # Step 4: Foto
    photo_paths = Column(JSON)  # List of file paths
    photo_metadata = Column(JSON)  # AI analysis results
    # Foto guidate {slot: data-URL} + foto aggiuntive [data-URL] (MVP: inline
    # nel DB, con cap per foto e totale lato API; object storage in futuro).
    photos = Column(JSON)
    additional_photos = Column(JSON)

    # Results
    estimated_class = Column(String(5))
    energy_score = Column(Float)
    
    # Status
    status = Column(String(20), default="draft")  # draft, completed, exported
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    user = relationship("User", back_populates="surveys")


class PhotoAnalysis(Base):
    __tablename__ = "photo_analyses"
    
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    survey_id = Column(UUID(as_uuid=True), ForeignKey("surveys.id"))
    photo_type = Column(String(50))  # facciata, caldaia, finestra, muro
    file_path = Column(Text)
    
    # AI extraction results
    raw_response = Column(JSON)
    extracted_brand = Column(String(255))
    extracted_model = Column(String(255))
    extracted_power_kw = Column(Float)
    extracted_year = Column(Integer)
    
    # Quality check
    quality_score = Column(Float)
    is_readable = Column(Boolean, default=False)
    
    created_at = Column(DateTime, default=datetime.utcnow)
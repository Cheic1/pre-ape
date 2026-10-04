from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
from datetime import datetime
from sqlalchemy import text
from app.core.config import settings
from app.api.v1 import router as api_v1_router
from app.models.database import Base, engine

# Create database tables (reuses the single engine from app.models.database)
def init_db():
    """Create missing tables and apply additive schema migrations.

    Uses the shared engine from app.models.database — never a second engine.
    Fails fast on error so a broken DB cannot silently produce a zombie API.
    """
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        # Additive migration for the JWT login (no Alembic yet — see P2-B1):
        conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255)"))
    print("Database tables created successfully")

# Create main FastAPI application
app = FastAPI(
    title="Pre-APE API",
    description="API for Pre-APE - Preliminary Energy Performance Assessment",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS: default list already contains the production origin
# (https://preape.cheic2.it, see app.core.config); set CORS_ORIGINS as a JSON
# env var to override it without touching the code.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API v1 router
app.include_router(api_v1_router)

@app.get("/")
async def root():
    return JSONResponse({
        "app": "Pre-APE API",
        "version": "1.0.0",
        "status": "running",
        "database_url": settings.DATABASE_URL.split("@")[-1] if "@" in settings.DATABASE_URL else settings.DATABASE_URL,
    })

@app.get("/health")
async def health_check():
    return JSONResponse({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat()
    })

def main():
    # Initialize database
    init_db()

    # Run the application
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=7031,
        reload=settings.DEBUG,
        access_log=True
    )

if __name__ == "__main__":
    main()

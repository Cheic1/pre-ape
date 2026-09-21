from fastapi import FastAPI
from fastapi.responses import JSONResponse
import uvicorn
from datetime import datetime
from app.core.config import settings
from app.api.v1 import router as api_v1_router
from app.models.database import Base, SessionLocal, User, Survey, PhotoAnalysis
from sqlalchemy import create_engine
import os

# Create database tables
def init_db():
    try:
        engine = create_engine(settings.DATABASE_URL)
        Base.metadata.create_all(bind=engine)
        print("Database tables created successfully")
    except Exception as e:
        print(f"Error creating database tables: {e}")

# Create main FastAPI application
app = FastAPI(
    title="Pre-APE API",
    description="API for Pre-APE - Preliminary Energy Performance Assessment",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
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
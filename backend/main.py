import os
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy import text

from app.core.config import settings
from app.api.v1 import router as api_v1_router
from app.models.database import Base, engine

# Additive schema migrations (no Alembic yet — see P2-B1). Idempotent.
_ADDITIVE_MIGRATIONS = (
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255)",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS title VARCHAR(255)",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS client_name VARCHAR(255)",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS notes TEXT",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS photos JSON",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS additional_photos JSON",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS building JSON",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS energy_result JSON",
    "ALTER TABLE surveys ADD COLUMN IF NOT EXISTS cadastral JSON",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_version VARCHAR(32)",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_at TIMESTAMP",
    "ALTER TABLE survey_documents ADD COLUMN IF NOT EXISTS cad JSON",
)

# Max request body: 14 photos × ~1 MB data-URL + JSON fields.
MAX_BODY_BYTES = 16 * 1024 * 1024

# Built Flutter web app (Docker image copies it here). When present the API
# also serves the SPA from "/", so web + API share one origin (no CORS).
STATIC_DIR = Path(os.environ.get("STATIC_DIR", Path(__file__).parent / "static"))


def init_db():
    """Create missing tables and apply additive schema migrations.

    Uses the shared engine from app.models.database — never a second engine.
    Fails fast on error so a broken DB cannot silently produce a zombie API.
    """
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
        for statement in _ADDITIVE_MIGRATIONS:
            conn.execute(text(statement))
    print("Database tables created successfully")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Runs under `python main.py` and `uvicorn main:app` alike (Docker/PaaS).
    if os.environ.get("SKIP_INIT_DB") != "1":
        init_db()
    yield


# Create main FastAPI application
app = FastAPI(
    title="Pre-APE API",
    description="API for Pre-APE - Preliminary Energy Performance Assessment",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
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


class _BodyTooLarge(HTTPException):
    """Raised while the body streams in; FastAPI lets HTTPException through its
    body parsing (any other error would become a 400)."""

    def __init__(self):
        super().__init__(status_code=413, detail="Request body too large")


class LimitBodySizeMiddleware:
    """413 for bodies over MAX_BODY_BYTES.

    Checks Content-Length up front and also counts the streamed bytes, so a
    chunked upload (no Content-Length) cannot slip past the limit.
    """

    def __init__(self, app, max_bytes: int):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        too_large = JSONResponse({"detail": "Request body too large"}, status_code=413)
        for name, value in scope.get("headers", []):
            if name == b"content-length":
                if value.isdigit() and int(value) > self.max_bytes:
                    return await too_large(scope, receive, send)
                break

        received = 0
        response_started = False

        async def limited_receive():
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > self.max_bytes:
                    raise _BodyTooLarge()
            return message

        async def tracking_send(message):
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, limited_receive, tracking_send)
        except _BodyTooLarge:
            if not response_started:
                await too_large(scope, receive, send)


app.add_middleware(LimitBodySizeMiddleware, max_bytes=MAX_BODY_BYTES)


# Include API v1 router
app.include_router(api_v1_router)


@app.get("/api")
async def api_info():
    return JSONResponse({
        "app": "Pre-APE API",
        "version": "1.0.0",
        "status": "running",
    })


@app.api_route("/health", methods=["GET", "HEAD"])
async def health_check():
    return JSONResponse({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat()
    })


if (STATIC_DIR / "index.html").is_file():
    _index = STATIC_DIR / "index.html"
    _static_root = STATIC_DIR.resolve()

    # HEAD too: uptime monitors and link checkers probe with it (was 405).
    @app.api_route("/{full_path:path}", methods=["GET", "HEAD"], include_in_schema=False)
    async def spa(full_path: str):
        """Serve the Flutter web build; unknown paths fall back to index.html."""
        if full_path.startswith(("api/", "docs", "redoc", "openapi.json")):
            return JSONResponse({"detail": "Not Found"}, status_code=404)
        candidate = (STATIC_DIR / full_path).resolve()
        if full_path and candidate.is_file() and _static_root in candidate.parents:
            # Flutter web file names carry no content hash (main.dart.js,
            # assets/…): without no-cache a browser may keep running the old
            # bundle after a deploy. no-cache still allows 304 revalidation.
            return FileResponse(candidate, headers={"Cache-Control": "no-cache"})
        return FileResponse(_index, headers={"Cache-Control": "no-cache"})
else:
    @app.get("/")
    async def root():
        return await api_info()


def main():
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "7031")),
        reload=settings.DEBUG,
        access_log=True
    )

if __name__ == "__main__":
    main()

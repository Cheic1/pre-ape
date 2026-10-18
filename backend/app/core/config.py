import os
from pydantic_settings import BaseSettings
from pydantic import Field, model_validator

# Placeholder values that must never ship outside development (M1 fail-fast).
SECRET_KEY_PLACEHOLDER = "your-secret-key-change-in-production"
_PLACEHOLDER_SECRETS = frozenset({"", SECRET_KEY_PLACEHOLDER, "changeme", "change-me"})

class Settings(BaseSettings):
    # App
    APP_NAME: str = "Pre-APE"
    VERSION: str = "1.0.0"
    DEBUG: bool = False
    APP_ENV: str = Field(
        default="production",
        description="deployment environment: development | staging | production"
    )
    
    # Database
    DATABASE_URL: str = Field(
        default="postgresql://postgres:postgres@localhost:5433/pre_ape",
        description="PostgreSQL connection string"
    )
    
    # Redis
    REDIS_URL: str = Field(
        default="redis://localhost:6379/0",
        description="Redis connection string"
    )
    
    # Auth - Google OAuth
    GOOGLE_CLIENT_ID: str = Field(default="", description="Google OAuth Client ID")
    GOOGLE_CLIENT_SECRET: str = Field(default="", description="Google OAuth Client Secret")
    GOOGLE_REDIRECT_URI: str = Field(
        default="http://localhost:8000/api/v1/auth/google/callback",
        description="Google OAuth redirect URI"
    )
    
    # JWT
    SECRET_KEY: str = Field(default=SECRET_KEY_PLACEHOLDER)
    ALGORITHM: str = "HS256"
    # 7 days: technicians work on site for hours with no refresh-token flow
    # yet; a 401 sends the app back to the login screen.
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7
    
    # AI/Vision
    AI_PROVIDER: str = Field(default="ollama", description="AI provider: ollama, openai, anthropic")
    OLLAMA_BASE_URL: str = Field(default="http://localhost:11434")
    OLLAMA_MODEL: str = Field(default="llava:7b")
    OPENAI_API_KEY: str = Field(default="")
    ANTHROPIC_API_KEY: str = Field(default="")
    
    # Storage
    UPLOAD_DIR: str = Field(default="/tmp/pre_ape_uploads")
    MAX_UPLOAD_SIZE: int = 10 * 1024 * 1024  # 10MB
    
    # CORS: dev origins + production origin by default.
    # Env override must be a JSON list, e.g.
    #   CORS_ORIGINS='["https://preape.cheic2.it"]'
    CORS_ORIGINS: list[str] = Field(
        default=[
            "http://localhost:3000",
            "http://localhost:8080",
            "http://localhost:7030",
            "https://preape.cheic2.it",
        ],
        description="Allowed CORS origins (JSON list when set via env)"
    )

    # Admin: comma-separated emails with access to /api/v1/admin (no UI to grant it)
    ADMIN_EMAILS: str = Field(default="", description="comma-separated admin emails")

    @property
    def admin_emails(self) -> frozenset[str]:
        return frozenset(e.strip().lower() for e in self.ADMIN_EMAILS.split(",") if e.strip())

    # Rate limiting (auth endpoints, per client IP)
    AUTH_RATE_LIMIT_PER_MINUTE: int = 10
    
    # Email (for reports)
    SMTP_HOST: str = Field(default="smtp.gmail.com")
    SMTP_PORT: int = Field(default=587)
    SMTP_USER: str = Field(default="")
    SMTP_PASSWORD: str = Field(default="")
    
    @model_validator(mode="after")
    def _fail_fast_on_placeholder_secret(self):
        """Refuse to start with a placeholder SECRET_KEY outside development (M1).

        Runs at import time (``settings = Settings()``), so a misconfigured
        production process dies immediately instead of signing forgeable JWTs.
        Tests opt out explicitly via ``APP_ENV=development`` (tests/conftest.py).
        """
        if self.APP_ENV != "development" and self.SECRET_KEY.strip() in _PLACEHOLDER_SECRETS:
            raise ValueError(
                "SECRET_KEY is still a placeholder: set a strong SECRET_KEY "
                "environment variable, or run with APP_ENV=development"
            )
        return self

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
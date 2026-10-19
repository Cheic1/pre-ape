import base64
import binascii
import os
from pydantic_settings import BaseSettings
from pydantic import Field, model_validator

# Placeholder values that must never ship outside development (M1 fail-fast).
SECRET_KEY_PLACEHOLDER = "your-secret-key-change-in-production"
_PLACEHOLDER_SECRETS = frozenset({"", SECRET_KEY_PLACEHOLDER, "changeme", "change-me"})


def _decode_documents_key(value: str) -> bytes | None:
    """base64 (urlsafe or standard, padding optional) of exactly 32 bytes, else None."""
    value = (value or "").strip()
    if not value:
        return None
    value = value.replace("+", "-").replace("/", "_")
    try:
        key = base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)
    except (binascii.Error, ValueError):
        return None
    return key if len(key) == 32 else None

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

    # Documenti catastali cifrati a riposo (AES-256-GCM, app/core/crypto.py):
    # base64 (urlsafe o standard) di 32 byte casuali. Vuota solo in development
    # (chiave derivata da SECRET_KEY). Persa la chiave, i documenti sono persi.
    DOCUMENTS_ENCRYPTION_KEY: str = Field(default="", description="base64 of 32 random bytes")

    @property
    def documents_key(self) -> bytes:
        """32-byte AES key (validated at startup, see ``_check_documents_key``)."""
        key = _decode_documents_key(self.DOCUMENTS_ENCRYPTION_KEY)
        if key is not None:
            return key
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.kdf.hkdf import HKDF

        return HKDF(
            algorithm=hashes.SHA256(), length=32, salt=None, info=b"pre-ape-documents"
        ).derive(self.SECRET_KEY.encode())
    # Documenti legali (app/legal/*.md): valori dei segnaposto {{...}}.
    # Vuoti = restano "[da completare: ...]" e l'app mostra il banner bozza.
    LEGAL_TITOLARE_NOME: str = Field(default="", description="ragione sociale / nome del titolare")
    LEGAL_TITOLARE_INDIRIZZO: str = Field(default="", description="sede legale / indirizzo")
    LEGAL_TITOLARE_PIVA_CF: str = Field(default="", description="P.IVA e/o codice fiscale")
    LEGAL_TITOLARE_EMAIL_PRIVACY: str = Field(default="", description="email per richieste privacy")
    LEGAL_SERVER_UBICAZIONE: str = Field(default="", description="dove sono i server (es. 'Italia')")
    LEGAL_FORO_COMPETENTE: str = Field(default="", description="foro competente (es. 'Milano')")
    LEGAL_DATA_EFFICACIA: str = Field(default="", description="data di efficacia dei documenti")

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

    @model_validator(mode="after")
    def _check_documents_key(self):
        """DOCUMENTS_ENCRYPTION_KEY must be a valid 32-byte key outside development.

        In development an empty value falls back to a key derived from
        SECRET_KEY (tests need no config); a non-empty invalid value is always
        refused, so a typo never silently switches key.
        """
        raw = self.DOCUMENTS_ENCRYPTION_KEY.strip()
        if raw and _decode_documents_key(raw) is None:
            raise ValueError(
                "DOCUMENTS_ENCRYPTION_KEY is invalid: it must be the base64 of 32 bytes"
            )
        if not raw and self.APP_ENV != "development":
            raise ValueError(
                "DOCUMENTS_ENCRYPTION_KEY is empty: generate one with "
                "python -c \"import os,base64;print(base64.urlsafe_b64encode(os.urandom(32)).decode())\""
                " or run with APP_ENV=development"
            )
        return self

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()
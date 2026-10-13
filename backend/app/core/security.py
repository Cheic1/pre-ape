"""JWT + password primitives (P1-A1).

Choices reported to the team:
  * JWT: python-jose (already declared in pyproject — per task instruction);
    algorithm is pinned to settings.ALGORITHM on decode to prevent
    algorithm-confusion attacks, and exp is always verified.
  * Passwords: PBKDF2-HMAC-SHA256 via hashlib (stdlib) instead of the declared
    passlib 1.7.4 — passlib is unmaintained and raises trapped version-detection
    errors with bcrypt >= 4.1 (pyca/bcrypt#684); bcrypt also caps passwords at
    72 bytes. PBKDF2 is NIST-approved, dependency-free and the stored format is
    self-describing (`pbkdf2_sha256$iterations$salt$digest`, passlib-compatible
    layout), so migrating to argon2/bcrypt later only needs rehash-on-login.
"""
import asyncio
import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone
from uuid import UUID

from jose import jwt
from jose.exceptions import JWTError

from app.core.config import settings

PBKDF2_ITERATIONS = 600_000  # OWASP recommendation for PBKDF2-HMAC-SHA256
_SCHEME = "pbkdf2_sha256"


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return f"{_SCHEME}${PBKDF2_ITERATIONS}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, iterations, salt_hex, digest_hex = stored.split("$")
        if scheme != _SCHEME:
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            bytes.fromhex(salt_hex),
            int(iterations),
        )
        return hmac.compare_digest(digest, bytes.fromhex(digest_hex))
    except (ValueError, TypeError):
        return False


# Precomputed hash so login can burn the same PBKDF2 work when the account does
# not exist (timing side-channel against user enumeration).
_DUMMY_PASSWORD_HASH = hash_password("constant-time-login-placeholder")


def dummy_verify(password: str) -> bool:
    """Equalize login cost for unknown accounts; always returns False."""
    verify_password(password, _DUMMY_PASSWORD_HASH)
    return False


async def verify_password_async(password: str, stored: str) -> bool:
    """PBKDF2 verify off the event loop (M1): 600k iterations would stall every
    in-flight request while a single login hashes."""
    return await asyncio.to_thread(verify_password, password, stored)


async def dummy_verify_async(password: str) -> bool:
    """Async variant of dummy_verify; always returns False (equal login cost)."""
    return await asyncio.to_thread(dummy_verify, password)


def create_access_token(user_id: UUID) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)).timestamp()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> UUID:
    """Verify signature + expiry and return the user id (sub).

    Raises jose.exceptions.JWTError (or ValueError on a malformed sub) which
    callers translate to 401.
    """
    payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    sub = payload.get("sub")
    if not sub:
        raise JWTError("missing sub claim")
    return UUID(str(sub))

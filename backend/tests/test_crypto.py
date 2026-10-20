"""Cifratura a riposo dei documenti (app.core.crypto) + DOCUMENTS_ENCRYPTION_KEY."""
import base64
import os

import pytest
from pydantic import ValidationError

from app.core.config import Settings, settings
from app.core.crypto import (
    AAD,
    VERSION_PREFIX,
    DocumentDecryptionError,
    decrypt_document,
    encrypt_document,
)

PLAIN = b"%PDF-1.4\nvisura riservata\n"
STRONG_SECRET = "not-a-placeholder-" + "x" * 48


def _key() -> str:
    return base64.urlsafe_b64encode(os.urandom(32)).decode()


class TestEncryptDecrypt:
    def test_round_trip(self):
        blob = encrypt_document(PLAIN)
        assert blob.startswith(VERSION_PREFIX)
        assert PLAIN not in blob
        assert len(blob) == len(VERSION_PREFIX) + 12 + len(PLAIN) + 16
        assert decrypt_document(blob) == PLAIN
        assert decrypt_document(memoryview(blob)) == PLAIN  # DB drivers may return memoryview

    def test_empty_round_trip(self):
        assert decrypt_document(encrypt_document(b"")) == b""

    def test_random_nonce(self):
        assert encrypt_document(PLAIN) != encrypt_document(PLAIN)

    @pytest.mark.parametrize("index", [4, 10, 20, -1])  # nonce, ciphertext, tag
    def test_tamper_detected(self, index):
        blob = bytearray(encrypt_document(PLAIN))
        blob[index] ^= 0x01
        with pytest.raises(DocumentDecryptionError):
            decrypt_document(bytes(blob))

    def test_unknown_format(self):
        for blob in (PLAIN, b"", VERSION_PREFIX + b"short", b"PAE2" + encrypt_document(PLAIN)[4:]):
            with pytest.raises(DocumentDecryptionError):
                decrypt_document(blob)

    def test_aad_bound(self):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM

        nonce = os.urandom(12)
        other_aad = VERSION_PREFIX + nonce + AESGCM(settings.documents_key).encrypt(
            nonce, PLAIN, b"other"
        )
        with pytest.raises(DocumentDecryptionError):
            decrypt_document(other_aad)
        assert AAD == b"pre-ape-doc-v1"

    def test_wrong_key(self, monkeypatch):
        blob = encrypt_document(PLAIN)
        monkeypatch.setattr(settings, "DOCUMENTS_ENCRYPTION_KEY", _key())
        with pytest.raises(DocumentDecryptionError):
            decrypt_document(blob)


class TestDocumentsKeyConfig:
    def test_required_outside_development(self, monkeypatch):
        monkeypatch.setenv("APP_ENV", "production")
        monkeypatch.setenv("SECRET_KEY", STRONG_SECRET)
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", "")
        with pytest.raises(ValidationError, match="DOCUMENTS_ENCRYPTION_KEY"):
            Settings()

    @pytest.mark.parametrize("env", ["production", "development"])
    @pytest.mark.parametrize(
        "bad",
        ["not-base64!!", base64.urlsafe_b64encode(b"k" * 16).decode(), base64.urlsafe_b64encode(b"k" * 33).decode()],
    )
    def test_invalid_key_rejected(self, monkeypatch, env, bad):
        monkeypatch.setenv("APP_ENV", env)
        monkeypatch.setenv("SECRET_KEY", STRONG_SECRET)
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", bad)
        with pytest.raises(ValidationError, match="DOCUMENTS_ENCRYPTION_KEY"):
            Settings()

    def test_valid_key_in_production(self, monkeypatch):
        raw = os.urandom(32)
        monkeypatch.setenv("APP_ENV", "production")
        monkeypatch.setenv("SECRET_KEY", STRONG_SECRET)
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", base64.urlsafe_b64encode(raw).decode())
        assert Settings().documents_key == raw
        # standard base64 (e.g. Render generateValue) and missing padding accepted too
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", base64.b64encode(raw).decode().rstrip("="))
        assert Settings().documents_key == raw

    def test_development_fallback_is_deterministic(self, monkeypatch):
        monkeypatch.setenv("APP_ENV", "development")
        monkeypatch.setenv("SECRET_KEY", STRONG_SECRET)
        monkeypatch.setenv("DOCUMENTS_ENCRYPTION_KEY", "")
        first, second = Settings().documents_key, Settings().documents_key
        assert first == second and len(first) == 32
        monkeypatch.setenv("SECRET_KEY", STRONG_SECRET + "-other")
        assert Settings().documents_key != first

"""Cifratura a riposo dei documenti catastali (AES-256-GCM).

Formato del blob salvato in ``survey_documents.content``::

    b"PAE1" + nonce (12 byte casuali) + ciphertext || tag (16 byte)

con AAD ``b"pre-ape-doc-v1"``. Il prefisso di versione permette in futuro una
rotazione della chiave (``PAE2`` = nuova chiave) senza ambiguità. La chiave è
``settings.documents_key`` (``DOCUMENTS_ENCRYPTION_KEY``).
"""
from __future__ import annotations

import os

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import settings

VERSION_PREFIX = b"PAE1"
NONCE_BYTES = 12
TAG_BYTES = 16
AAD = b"pre-ape-doc-v1"


class DocumentDecryptionError(Exception):
    """Blob non decifrabile: formato sconosciuto, alterato o chiave sbagliata."""


def encrypt_document(plain: bytes) -> bytes:
    nonce = os.urandom(NONCE_BYTES)
    return VERSION_PREFIX + nonce + AESGCM(settings.documents_key).encrypt(nonce, plain, AAD)


def decrypt_document(blob: bytes) -> bytes:
    blob = bytes(blob)
    header = len(VERSION_PREFIX) + NONCE_BYTES
    if not blob.startswith(VERSION_PREFIX) or len(blob) < header + TAG_BYTES:
        raise DocumentDecryptionError("formato del documento cifrato non riconosciuto")
    nonce = blob[len(VERSION_PREFIX):header]
    try:
        return AESGCM(settings.documents_key).decrypt(nonce, blob[header:], AAD)
    except InvalidTag as exc:
        raise DocumentDecryptionError("documento alterato o chiave errata") from exc

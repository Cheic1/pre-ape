"""Dati catastali: schema condiviso fra API, parser visura e scheda CENED.

``CadastralUnit`` descrive una unità immobiliare come appare in visura; i nomi
seguono la visura dell'Agenzia delle Entrate, la mappatura verso CENED+2.0
(provinciaCatastale, comuneCatastale, foglio, particella, subalternoNumero…)
sta in ``app.core.cened``.
"""
from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

MAX_CADASTRAL_UNITS = 20


class CadastralUnit(BaseModel):
    model_config = ConfigDict(extra="forbid")

    comune: Optional[str] = Field(default=None, max_length=120)
    # Codice catastale (Belfiore) del comune, es. "F205" (Milano)
    codice_comune: Optional[str] = Field(default=None, max_length=4)
    provincia: Optional[str] = Field(default=None, max_length=2)
    sezione_urbana: Optional[str] = Field(default=None, max_length=10)
    foglio: Optional[str] = Field(default=None, max_length=10)
    particella: Optional[str] = Field(default=None, max_length=20)
    subalterno: Optional[str] = Field(default=None, max_length=10)
    categoria: Optional[str] = Field(default=None, max_length=10)  # es. "A/2"
    classe: Optional[str] = Field(default=None, max_length=10)
    consistenza: Optional[str] = Field(default=None, max_length=50)  # es. "5,5 vani"
    superficie_mq: Optional[float] = Field(default=None, ge=0, le=100_000)
    rendita_euro: Optional[float] = Field(default=None, ge=0, le=10_000_000)
    indirizzo: Optional[str] = Field(default=None, max_length=512)
    piano: Optional[str] = Field(default=None, max_length=50)

"""Documenti legali (informativa privacy, termini d'uso, DPA art. 28 GDPR).

I testi sono file Markdown in questa cartella con segnaposto ``{{NOME}}``;
al momento della richiesta vengono sostituiti con le impostazioni
``LEGAL_<NOME>`` (app.core.config). I segnaposto non configurati restano
visibili come ``[da completare: NOME]`` e il documento risulta
``complete = False`` (l'app mostra il banner "bozza" finché è così).

``LEGAL_VERSION`` identifica la versione dei termini accettata dagli utenti:
cambiarla obbliga tutti a riaccettare (login -> ``terms_accepted: false``).
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Mapping, Optional

LEGAL_VERSION = "2026-10-19"

LEGAL_DIR = Path(__file__).parent

# doc id -> (file, titolo)
DOCUMENTS: dict[str, tuple[str, str]] = {
    "privacy": ("informativa-privacy.md", "Informativa privacy"),
    "termini": ("termini-uso.md", "Termini d'uso"),
    "dpa": ("accordo-trattamento-dati.md", "Accordo sul trattamento dei dati (art. 28 GDPR)"),
}

# Segnaposto ammessi -> impostazione (variabile d'ambiente) che li valorizza
PLACEHOLDERS: dict[str, str] = {
    "TITOLARE_NOME": "LEGAL_TITOLARE_NOME",
    "TITOLARE_INDIRIZZO": "LEGAL_TITOLARE_INDIRIZZO",
    "TITOLARE_PIVA_CF": "LEGAL_TITOLARE_PIVA_CF",
    "TITOLARE_EMAIL_PRIVACY": "LEGAL_TITOLARE_EMAIL_PRIVACY",
    "SERVER_UBICAZIONE": "LEGAL_SERVER_UBICAZIONE",
    "FORO_COMPETENTE": "LEGAL_FORO_COMPETENTE",
    "DATA_EFFICACIA": "LEGAL_DATA_EFFICACIA",
}

_PLACEHOLDER_RE = re.compile(r"\{\{([A-Z_]+)\}\}")
_VERSION_TOKEN = "{{LEGAL_VERSION}}"
# Nota per l'operatore nel sorgente Markdown: l'app non la mostra come testo
# ma come banner, finché il documento non è completo.
_DRAFT_NOTE_PREFIX = "> **Bozza da far verificare a un legale"


def placeholder_values(settings) -> dict[str, str]:
    """Valori configurati (stringhe non vuote) per ciascun segnaposto."""
    values = {}
    for name, setting in PLACEHOLDERS.items():
        value = (getattr(settings, setting, "") or "").strip()
        if value:
            values[name] = value
    return values


def render(doc: str, values: Mapping[str, str]) -> Optional[dict]:
    """Documento con i segnaposto sostituiti, o None se ``doc`` non esiste."""
    entry = DOCUMENTS.get(doc)
    if entry is None:
        return None
    filename, title = entry
    source = (LEGAL_DIR / filename).read_text(encoding="utf-8")
    source = source.replace(_VERSION_TOKEN, LEGAL_VERSION)
    source = "\n".join(
        line for line in source.split("\n") if not line.startswith(_DRAFT_NOTE_PREFIX)
    )
    missing: set[str] = set()

    def _sub(match: re.Match) -> str:
        name = match.group(1)
        if name in values:
            return values[name]
        missing.add(name)
        return f"[da completare: {name}]"

    markdown = _PLACEHOLDER_RE.sub(_sub, source)
    return {
        "doc": doc,
        "title": title,
        "version": LEGAL_VERSION,
        "markdown": markdown,
        "complete": not missing,
    }

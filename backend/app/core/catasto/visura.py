"""Estrazione dei dati catastali da una visura dell'Agenzia delle Entrate.

Layout di riferimento: visura per immobile / per soggetto (SISTER, servizi
online). Il testo è letto riga per riga:

* intestazione ``Comune di MILANO ( Codice: F205)`` e ``Provincia di MILANO``
  (valgono per le righe successive: una visura per soggetto può elencare più
  comuni);
* righe della tabella "Unità immobiliare": ``N. [Sezione] Foglio Particella
  [Sub] [Zona Cens.] [Micro Zona] Categoria [Classe] [Consistenza]
  [Totale: 95 m²] … Euro 1.032,91``; la riga ``Indirizzo … Piano …`` che segue
  appartiene all'ultima unità;
* in mancanza di tabella, gli identificativi etichettati della richiesta
  (``Foglio: 351 Particella: 125 Sub.: 12``).

Gli intestatari (nomi, codici fiscali, diritti) non vengono mai letti: si
estraggono solo i campi di ``CadastralUnit``. Visure scansionate (senza testo)
danno ``[]``.
"""
from __future__ import annotations

import io
import logging
import re
from typing import List, Optional

from app.core.catasto import MAX_CADASTRAL_UNITS, CadastralUnit
from app.core.energy import climate

logger = logging.getLogger(__name__)

MAX_PDF_PAGES = 50

_COMUNE_RE = re.compile(
    r"\bComune\s+di\s+([A-Z][A-Z'\s.-]*?)\s*\(\s*Codice\s*:?\s*([A-Z]\d{3})\s*\)"
    r"(?:\s*\(\s*([A-Z]{2})\s*\))?",
    re.IGNORECASE,
)
_PROVINCIA_RE = re.compile(r"\bProvincia\s+di\s+([A-Za-z][A-Za-z'\s-]*[A-Za-z])", re.IGNORECASE)
_CATEGORIA = r"[A-F]/\d{1,2}"
_ROW_RE = re.compile(rf"^\s*\d{{1,3}}\.?\s+((?:[A-Z0-9]+\s+){{2,6}}?)({_CATEGORIA})\b(.*)$")
_UNIT = r"(?:vani|m²|m2|mq|m\^2)"
_CLASSE_RE = re.compile(rf"^\s*(\d{{1,2}}|U)(?=\s|$)(?!\s*{_UNIT}\b)")
_CONSISTENZA_RE = re.compile(rf"^\s*(\d+(?:,\d+)?)\s*({_UNIT})(?![\w])")
_SUPERFICIE_RE = re.compile(r"Totale\s*:\s*(\d+(?:[.,]\d+)?)\s*m", re.IGNORECASE)
_RENDITA_RE = re.compile(r"(?:Euro|€)\s*(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:,\d{1,2})?)")
_INDIRIZZO_RE = re.compile(r"^\s*Indirizzo\s*:?\s*(.+?)\s*$", re.IGNORECASE)
_PIANO_RE = re.compile(r"\s*\bPiano\b\s*:?\s*([A-Z0-9]+(?:\s*-\s*[A-Z0-9]+)*)", re.IGNORECASE)
_LABELED_RE = re.compile(
    r"(?:Sezione\s+Urbana\s*:\s*([A-Z0-9]+)\s+)?"
    r"Foglio\s*:\s*([A-Z0-9]+)\s+Particella\s*:\s*([A-Z0-9]+)"
    r"(?:\s+Sub(?:alterno)?\.?\s*:\s*([A-Z0-9]+))?",
    re.IGNORECASE,
)


def _it_number(value: str) -> Optional[float]:
    """``1.032,91`` → 1032.91; ``95`` → 95.0."""
    try:
        return float(value.replace(".", "").replace(",", "."))
    except ValueError:
        return None


def _clip(value: Optional[str], limit: int) -> Optional[str]:
    if value is None:
        return None
    value = value.strip()
    return value[:limit] or None


class _Place:
    """Comune/provincia correnti mentre si scorre il testo."""

    def __init__(self) -> None:
        self.comune: Optional[str] = None
        self.codice: Optional[str] = None
        self.sigla: Optional[str] = None
        self.provincia_nome: Optional[str] = None

    def fields(self) -> dict:
        comune = None
        found = None
        if self.comune:
            found = climate.find(self.comune, self.sigla)
            comune = found.nome if found else self.comune.title()
        sigla = self.sigla
        if not sigla and self.provincia_nome:
            capoluogo = climate.find(self.provincia_nome)
            if capoluogo is not None:
                sigla = capoluogo.provincia
        if not sigla and found is not None:
            sigla = found.provincia
        return {"comune": comune, "codice_comune": self.codice, "provincia": sigla}


def _parse_row(match: re.Match, place: _Place) -> dict:
    tokens = match.group(1).split()
    sezione = None
    if tokens and not tokens[0][0].isdigit():
        sezione = tokens.pop(0)
    foglio = tokens[0] if tokens else None
    particella = tokens[1] if len(tokens) > 1 else None
    # dopo foglio e particella: [sub] [zona cens.] [micro zona]
    sub = tokens[2] if len(tokens) > 2 else None

    rest = match.group(3)
    classe = None
    m = _CLASSE_RE.match(rest)
    if m:
        classe = m.group(1)
        rest = rest[m.end():]
    consistenza = None
    m = _CONSISTENZA_RE.match(rest)
    if m:
        unit = "vani" if m.group(2) == "vani" else "m²"
        consistenza = f"{m.group(1)} {unit}"
    m = _SUPERFICIE_RE.search(rest)
    superficie = _it_number(m.group(1)) if m else None
    m = _RENDITA_RE.search(rest)
    rendita = _it_number(m.group(1)) if m else None

    return {
        **place.fields(),
        "sezione_urbana": sezione,
        "foglio": foglio,
        "particella": particella,
        "subalterno": sub,
        "categoria": match.group(2),
        "classe": classe,
        "consistenza": consistenza,
        "superficie_mq": superficie,
        "rendita_euro": rendita,
    }


_MAX_LENGTHS = {
    name: next((m.max_length for m in field.metadata if hasattr(m, "max_length")), None)
    for name, field in CadastralUnit.model_fields.items()
}


def _build(data: dict) -> Optional[CadastralUnit]:
    clean = {}
    for key, value in data.items():
        if isinstance(value, str):
            value = _clip(value, _MAX_LENGTHS.get(key) or 512)
        if value is not None:
            clean[key] = value
    try:
        return CadastralUnit(**clean)
    except ValueError:  # es. rendita fuori scala: meglio scartare l'unità
        logger.warning("Unità catastale scartata: %s", clean)
        return None


def _key(unit: dict) -> tuple:
    return tuple(unit.get(k) for k in ("sezione_urbana", "foglio", "particella", "subalterno"))


def parse_visura_text(text: str) -> List[CadastralUnit]:
    """Unità immobiliari presenti nel testo di una visura (lista, anche vuota)."""
    place = _Place()
    rows: List[dict] = []
    labeled: List[dict] = []
    for line in (text or "").splitlines():
        m = _COMUNE_RE.search(line)
        if m:
            codice = m.group(2).upper()
            if codice != place.codice:  # nuovo comune: la provincia va riletta
                place.provincia_nome = None
            place.comune = " ".join(m.group(1).split())
            place.codice = codice
            place.sigla = m.group(3).upper() if m.group(3) else None
        m = _PROVINCIA_RE.search(line)
        if m:
            place.provincia_nome = " ".join(m.group(1).split())

        m = _ROW_RE.match(line)
        if m:
            rows.append(_parse_row(m, place))
            continue
        m = _INDIRIZZO_RE.match(line)
        if m and rows and rows[-1].get("indirizzo") is None:
            value = m.group(1)
            matches = list(_PIANO_RE.finditer(value))
            piano = matches[-1] if matches else None
            if piano:
                rows[-1]["piano"] = piano.group(1).replace(" ", "")
                value = value[: piano.start()]
            rows[-1]["indirizzo"] = value.strip(" ;,") or None
            continue
        for m in _LABELED_RE.finditer(line):
            labeled.append({
                **place.fields(),
                "sezione_urbana": m.group(1),
                "foglio": m.group(2),
                "particella": m.group(3),
                "subalterno": m.group(4),
            })

    units: List[CadastralUnit] = []
    seen = set()
    for data in rows or labeled:
        key = _key(data)
        if key in seen:  # visura storica: la situazione attuale viene prima
            continue
        seen.add(key)
        unit = _build(data)
        if unit is not None:
            units.append(unit)
        if len(units) >= MAX_CADASTRAL_UNITS:
            break
    return units


def parse_visura_pdf(data: bytes) -> List[CadastralUnit]:
    """Testo del PDF (pypdf) → ``parse_visura_text``. PDF illeggibile → ``[]``."""
    try:
        from pypdf import PdfReader

        reader = PdfReader(io.BytesIO(data))
        pages = [page.extract_text() or "" for page in reader.pages[:MAX_PDF_PAGES]]
    except Exception:  # noqa: BLE001 - PDF corrotto/cifrato: nessuna proposta
        logger.warning("Visura PDF non leggibile", exc_info=True)
        return []
    return parse_visura_text("\n".join(pages))

"""Climate data per comune: zona climatica + gradi giorno (DPR 412/93, Allegato A).

The table lives in ``app/data/comuni_climatici.csv`` (built by
``scripts/build_climate_data.py``) and is loaded once, lazily.
"""
from __future__ import annotations

import csv
import math
import re
import unicodedata
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import List, Optional

_CSV = Path(__file__).resolve().parents[2] / "data" / "comuni_climatici.csv"

ZONES = ("A", "B", "C", "D", "E", "F")

# DPR 412/93 art. 9: heating season length (days). Zone F has no legal limit:
# 200 days is the conventional value used for the seasonal balance.
HEATING_DAYS = {"A": 106, "B": 121, "C": 137, "D": 166, "E": 183, "F": 200}

# Representative GG when only the zone is known (centre of the DPR 412 band).
ZONE_DEFAULT_GG = {"A": 550, "B": 750, "C": 1150, "D": 1750, "E": 2550, "F": 3300}


@dataclass(frozen=True)
class Comune:
    istat: str
    nome: str
    provincia: str
    regione: str
    zona: str
    gradi_giorno: int
    altitudine: Optional[int]
    lat: Optional[float]
    lon: Optional[float]
    fonte: str

    def as_dict(self) -> dict:
        return {
            "comune": self.nome,
            "provincia": self.provincia,
            "regione": self.regione,
            "zona": self.zona,
            "gradi_giorno": self.gradi_giorno,
            "altitudine": self.altitudine,
            "fonte": self.fonte,
        }


def normalize(name: str) -> str:
    s = unicodedata.normalize("NFKD", name or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z]", "", s)


def zone_for_gg(gg: float) -> str:
    if gg <= 600:
        return "A"
    if gg <= 900:
        return "B"
    if gg <= 1400:
        return "C"
    if gg <= 2100:
        return "D"
    if gg <= 3000:
        return "E"
    return "F"


@lru_cache(maxsize=1)
def _table() -> tuple:
    rows: List[Comune] = []
    with open(_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows.append(Comune(
                istat=r["istat"],
                nome=r["comune"],
                provincia=r["provincia"],
                regione=r["regione"],
                zona=r["zona"],
                gradi_giorno=int(r["gradi_giorno"]),
                altitudine=int(r["altitudine"]) if r["altitudine"] else None,
                lat=float(r["lat"]) if r["lat"] else None,
                lon=float(r["lon"]) if r["lon"] else None,
                fonte=r["fonte"],
            ))
    by_name: dict = {}
    for c in rows:
        by_name.setdefault(normalize(c.nome), []).append(c)
    return tuple(rows), by_name


def find(comune: str, provincia: Optional[str] = None) -> Optional[Comune]:
    """Exact (accent/case-insensitive) match; ``provincia`` disambiguates."""
    _, by_name = _table()
    cands = by_name.get(normalize(comune), [])
    if provincia:
        p = provincia.strip().upper()
        cands = [c for c in cands if c.provincia == p] or cands
    return cands[0] if cands else None


def search(query: str, limit: int = 10) -> List[Comune]:
    """Prefix matches first, then substring matches (autocomplete)."""
    q = normalize(query)
    if len(q) < 2:
        return []
    rows, _ = _table()
    prefix = [c for c in rows if normalize(c.nome).startswith(q)]
    inner = [c for c in rows if q in normalize(c.nome) and c not in prefix]
    prefix.sort(key=lambda c: (len(c.nome), c.nome))
    return (prefix + inner)[:limit]


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(a))


def resolve(
    address: Optional[str] = None,
    lat: Optional[float] = None,
    lon: Optional[float] = None,
) -> Optional[Comune]:
    """Best guess of the comune from a geocoded address and/or coordinates.

    Address parts (Nominatim ``display_name``) that are comune names are the
    candidates; the one nearest to the coordinates wins (so "…, Moncalieri,
    Torino, …" resolves to Moncalieri, not to the province capital). Without
    candidates, the comune whose town hall is nearest is used.
    """
    rows, by_name = _table()
    cands: List[Comune] = []
    for part in (address or "").split(","):
        # "20100 Milano MI", "Milano (MI)" → "Milano"
        bare = re.sub(r"\b\d{5}\b|\(?\b[A-Z]{2}\b\)?\s*$", " ", part.strip())
        for name in {normalize(part), normalize(bare)}:
            cands.extend(c for c in by_name.get(name, []) if c not in cands)
    has_point = lat is not None and lon is not None
    if cands:
        if not has_point or len(cands) == 1:
            return cands[0]
        located = [c for c in cands if c.lat is not None]
        if not located:
            return cands[0]
        return min(located, key=lambda c: _distance_km(lat, lon, c.lat, c.lon))
    if has_point:
        located = [c for c in rows if c.lat is not None]
        best = min(located, key=lambda c: _distance_km(lat, lon, c.lat, c.lon))
        if _distance_km(lat, lon, best.lat, best.lon) <= 25:
            return best
    return None

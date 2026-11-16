"""Agente LLM con visione (opzionale) per la planimetria.

Legge dal disegno ciò che la visione artificiale non sa leggere: scala
dichiarata, altezza dei locali ("H 2,70") e nomi dei vani con la loro
posizione. Usa qualunque API compatibile OpenAI (``/chat/completions``):
freellmapi, OpenAI, OpenRouter, Ollama… configurata con ``LLM_BASE_URL``,
``LLM_API_KEY``, ``LLM_MODEL``. Se non configurata, o se la chiamata fallisce,
l'estrazione prosegue col solo riconoscimento automatico (fallback).
"""
from __future__ import annotations

import base64
import io
import json
import logging
import re
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)

MAX_SIDE_PX = 1600

PROMPT = """Sei un geometra italiano. L'immagine è una planimetria catastale.
Rispondi SOLO con un oggetto JSON, senza testo attorno, con queste chiavi:
{"scale_denominator": intero o null (es. 200 se c'è scritto "Scala 1:200"),
 "wall_height_m": numero o null (altezza dei locali, es. "H 2,70" -> 2.7),
 "rooms": [{"name": "nome del vano come scritto (es. CUCINA, LETTO, BAGNO)",
            "x": frazione 0-1 della larghezza immagine del centro del nome,
            "y": frazione 0-1 dell'altezza immagine (0 = in alto)}]}
Non inventare: usa null o lista vuota se non leggibile. Ignora nomi di persone."""


@dataclass
class LlmHints:
    scale_denominator: Optional[int] = None
    wall_height_m: Optional[float] = None
    # (nome, x_px, y_px) nell'immagine analizzata a piena risoluzione
    rooms: List[Tuple[str, float, float]] = field(default_factory=list)


def is_configured(settings=None) -> bool:
    from app.core.config import settings as default

    s = settings or default
    return bool(s.LLM_BASE_URL.strip() and s.LLM_MODEL.strip())


def _png_data_url(gray: np.ndarray) -> str:
    from PIL import Image

    img = Image.fromarray(gray)
    img.thumbnail((MAX_SIDE_PX, MAX_SIDE_PX))
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def _chat(settings, data_url: str) -> str:
    """POST /chat/completions → testo della risposta (solleva su errore)."""
    url = settings.LLM_BASE_URL.rstrip("/") + "/chat/completions"
    body = {
        "model": settings.LLM_MODEL,
        "temperature": 0,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": PROMPT},
                {"type": "image_url", "image_url": {"url": data_url}},
            ],
        }],
    }
    headers = {"Content-Type": "application/json"}
    if settings.LLM_API_KEY:
        headers["Authorization"] = f"Bearer {settings.LLM_API_KEY}"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=settings.LLM_TIMEOUT_S) as resp:  # noqa: S310
        payload = json.loads(resp.read().decode("utf-8"))
    content = payload["choices"][0]["message"]["content"]
    if isinstance(content, list):  # alcuni provider: lista di parti
        content = "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return str(content)


def parse_hints(text: str, width: int, height: int) -> LlmHints:
    """Testo del modello (JSON, anche dentro ```json```) → valori plausibili."""
    match = re.search(r"\{.*\}", text or "", re.DOTALL)
    if not match:
        raise ValueError("risposta senza JSON")
    data = json.loads(match.group(0))
    hints = LlmHints()
    scale = data.get("scale_denominator")
    if isinstance(scale, (int, float)) and 20 <= scale <= 2000:
        hints.scale_denominator = int(scale)
    h = data.get("wall_height_m")
    if isinstance(h, str):
        try:
            h = float(h.replace(",", "."))
        except ValueError:
            h = None
    if isinstance(h, (int, float)) and 2.0 <= h <= 6.0:
        hints.wall_height_m = round(float(h), 2)
    for room in data.get("rooms") or []:
        if not isinstance(room, dict):
            continue
        name, x, y = room.get("name"), room.get("x"), room.get("y")
        if not isinstance(name, str) or not name.strip():
            continue
        if not all(isinstance(v, (int, float)) and 0 <= v <= 1 for v in (x, y)):
            continue
        hints.rooms.append((name.strip()[:40].upper(), x * width, y * height))
    return hints


def analyze(gray: np.ndarray, settings=None) -> LlmHints:
    """Chiama il modello sull'immagine (solleva su errore di rete/formato)."""
    from app.core.config import settings as default

    s = settings or default
    text = _chat(s, _png_data_url(gray))
    return parse_hints(text, gray.shape[1], gray.shape[0])


def safe_analyze(gray: np.ndarray, warnings: List[str], settings=None) -> Optional[LlmHints]:
    """Come ``analyze`` ma non fallisce mai: None + avviso se non disponibile."""
    if not is_configured(settings):
        return None
    try:
        return analyze(gray, settings)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError,
            IndexError, TypeError, json.JSONDecodeError) as exc:
        logger.warning("Analisi LLM della planimetria non riuscita: %s", exc)
        warnings.append("Analisi AI non disponibile: usato solo il riconoscimento automatico.")
        return None

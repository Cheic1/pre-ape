"""Documento (PDF/JPEG/PNG) → immagine in scala di grigi + dpi + scala dichiarata.

Le planimetrie catastali da SISTER sono PDF A4/A3 con la pianta in scala
(di norma 1:200), spesso come immagine scansionata: si renderizza la pagina
intera a ``RENDER_DPI``, così vale sia per PDF raster sia vettoriali, e il
rapporto pixel → metri discende da dpi e scala.
"""
from __future__ import annotations

import io
import re
from dataclasses import dataclass, field
from typing import List, Optional

import numpy as np

RENDER_DPI = 300
MAX_PDF_PAGES = 50
MAX_PIXELS = 40_000_000  # ~A2 a 300 dpi; oltre si riduce
MAX_SOURCE_PIXELS = 120_000_000  # immagini più grandi: rifiutate (decompression bomb)

_SCALE_RE = re.compile(r"\bscala\s*(?:di\s*)?1\s*[:/]\s*(\d{2,4})\b", re.IGNORECASE)


@dataclass
class Raster:
    gray: np.ndarray  # uint8, 0 = nero
    dpi: Optional[float]
    scale_denominator: Optional[int]
    warnings: List[str] = field(default_factory=list)


def find_scale(text: str) -> Optional[int]:
    """``"Scala 1:200"`` → 200 (prima occorrenza plausibile)."""
    for match in _SCALE_RE.finditer(text or ""):
        value = int(match.group(1))
        if 20 <= value <= 2000:
            return value
    return None


def _downscale(gray: np.ndarray, dpi: Optional[float]):
    import cv2

    h, w = gray.shape
    if h * w <= MAX_PIXELS:
        return gray, dpi
    f = (MAX_PIXELS / (h * w)) ** 0.5
    gray = cv2.resize(gray, (int(w * f), int(h * f)), interpolation=cv2.INTER_AREA)
    return gray, (dpi * f if dpi else None)


def _load_pdf(data: bytes, page: int) -> Raster:
    import pypdfium2 as pdfium

    try:
        pdf = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as exc:
        raise ValueError("PDF non leggibile") from exc
    try:
        n = len(pdf)
        if n == 0:
            raise ValueError("PDF senza pagine")
        if page >= min(n, MAX_PDF_PAGES):
            raise ValueError(f"Pagina {page + 1} inesistente (il PDF ne ha {n})")
        pg = pdf[page]
        w_pt, h_pt = pg.get_size()
        dpi = float(RENDER_DPI)
        if (w_pt / 72 * dpi) * (h_pt / 72 * dpi) > MAX_PIXELS:
            dpi = (MAX_PIXELS / ((w_pt / 72) * (h_pt / 72))) ** 0.5
        image = pg.render(scale=dpi / 72, grayscale=True).to_pil().convert("L")
        textpage = pg.get_textpage()
        text = textpage.get_text_bounded()
        textpage.close()
        pg.close()
    finally:
        pdf.close()
    warnings = [] if n == 1 else [f"Il PDF ha {n} pagine: elaborata la pagina {page + 1}."]
    return Raster(np.array(image, dtype=np.uint8), dpi, find_scale(text), warnings)


def _load_image(data: bytes) -> Raster:
    from PIL import Image

    try:
        img = Image.open(io.BytesIO(data))
        if img.width * img.height > MAX_SOURCE_PIXELS:
            raise ValueError("Immagine troppo grande")
        dpi_info = img.info.get("dpi")
        img = img.convert("L")
    except (OSError, Image.DecompressionBombError) as exc:
        raise ValueError("Immagine non leggibile") from exc
    dpi = None
    if dpi_info:
        try:
            value = float(dpi_info[0])
            # 72/96 dpi = valore di default di molti programmi, non una scansione
            dpi = value if value >= 100 else None
        except (TypeError, ValueError, IndexError):
            dpi = None
    gray, dpi = _downscale(np.array(img, dtype=np.uint8), dpi)
    return Raster(gray, dpi, None)


def load_raster(data: bytes, mime: str, page: int = 0) -> Raster:
    if mime == "application/pdf":
        return _load_pdf(data, page)
    if mime in ("image/jpeg", "image/png"):
        return _load_image(data)
    raise ValueError("Formato non supportato")

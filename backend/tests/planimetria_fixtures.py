"""Planimetria sintetica "stile catastale" per i test (Pillow + fpdf2).

Appartamento 10 × 8 m in scala 1:200 su A4 a 300 dpi: muri esterni 30 cm
campiti, tramezzi 10 cm, tre vani, due porte interne (varchi) e quattro
finestre (varchi con due linee sottili), più quote, testi e cornice a tratto
sottile che il riconoscimento deve ignorare.

Vani attesi (m²): 3,6 × 7,4 = 26,64 · 5,7 × 3,7 = 21,09 · 5,7 × 3,6 = 20,52.
"""
from __future__ import annotations

import io

from PIL import Image, ImageDraw

DPI = 300
SCALE = 200
PX_PER_M = DPI / 25.4 * 1000 / SCALE  # 59.055…
A4_PX = (2480, 3508)
ORIGIN = (400, 2600)  # pixel del punto (0, 0) del disegno (y verso il basso)

EXPECTED_ROOMS_M2 = sorted([26.64, 21.09, 20.52], reverse=True)
EXPECTED_GROSS_M2 = 80.0


def _px(x_m: float, y_m: float):
    return ORIGIN[0] + x_m * PX_PER_M, ORIGIN[1] - y_m * PX_PER_M


def _rect(draw, x0, y0, x1, y1, fill=0):
    (ax, ay), (bx, by) = _px(x0, y0), _px(x1, y1)
    draw.rectangle([min(ax, bx), min(ay, by), max(ax, bx), max(ay, by)], fill=fill)


def _line(draw, x0, y0, x1, y1, width=2):
    draw.line([_px(x0, y0), _px(x1, y1)], fill=0, width=width)


def plan_image() -> Image.Image:
    img = Image.new("L", A4_PX, 255)
    d = ImageDraw.Draw(img)
    # cornice e cartiglio (tratto sottile)
    d.rectangle([60, 60, A4_PX[0] - 60, A4_PX[1] - 60], outline=0, width=3)
    d.rectangle([60, 60, A4_PX[0] - 60, 500], outline=0, width=3)
    d.text((120, 120), "Catasto dei Fabbricati - Planimetria - Scala 1:200", fill=0)

    # muri esterni 30 cm
    _rect(d, 0, 0, 10, 0.3)
    _rect(d, 0, 7.7, 10, 8)
    _rect(d, 0, 0, 0.3, 8)
    _rect(d, 9.7, 0, 10, 8)
    # tramezzi 10 cm
    _rect(d, 6.0, 0.3, 6.1, 7.7)
    _rect(d, 0.3, 4.0, 6.0, 4.1)
    # porte interne (varchi da 90 cm)
    _rect(d, 6.0, 2.0, 6.1, 2.9, fill=255)
    _rect(d, 2.0, 4.0, 2.9, 4.1, fill=255)
    # finestre (varchi da 1,2 m con due linee sottili)
    for x0 in (2.0, 7.5):  # lato sud
        _rect(d, x0, 0, x0 + 1.2, 0.3, fill=255)
        _line(d, x0, 0.1, x0 + 1.2, 0.1)
        _line(d, x0, 0.2, x0 + 1.2, 0.2)
    for x0 in (2.0, 7.5):  # lato nord
        _rect(d, x0, 7.7, x0 + 1.2, 8, fill=255)
        _line(d, x0, 7.8, x0 + 1.2, 7.8)
        _line(d, x0, 7.9, x0 + 1.2, 7.9)
    # quote e testi (sottili)
    _line(d, 0, -1.0, 10, -1.0)
    _line(d, 0, -1.2, 0, -0.8)
    _line(d, 10, -1.2, 10, -0.8)
    for (x, y, t) in ((1.5, 2.0, "CAMERA"), (1.5, 6.0, "SOGGIORNO"), (7.0, 4.5, "CUCINA"),
                      (4.5, -0.8, "10.00"), (4.0, 9.0, "PIANO PRIMO  H 2.70")):
        d.text(_px(x, y), t, fill=0)
    return img


def plan_png() -> bytes:
    buf = io.BytesIO()
    plan_image().save(buf, format="PNG", dpi=(DPI, DPI))
    return buf.getvalue()


def plan_pdf(with_scale_text: bool = True) -> bytes:
    from fpdf import FPDF

    pdf = FPDF(unit="mm", format="A4")
    pdf.set_auto_page_break(False)
    pdf.add_page()
    buf = io.BytesIO()
    plan_image().save(buf, format="PNG")
    buf.seek(0)
    pdf.image(buf, x=0, y=0, w=210, h=297)
    if with_scale_text:
        pdf.set_font("helvetica", size=9)
        pdf.set_xy(15, 285)
        pdf.cell(text="Planimetria di u.i.u. - Scala 1:200")
    return bytes(pdf.output())


def plan_scanned_jpeg() -> bytes:
    """Come una scansione: ruotata di 0,8°, sfocata, rumore, JPEG qualità 60."""
    import numpy as np
    from PIL import ImageFilter

    img = plan_image().rotate(0.8, fillcolor=255, resample=Image.BICUBIC)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    noise = np.random.default_rng(0).normal(0, 18, (img.height, img.width))
    img = Image.fromarray(np.clip(np.asarray(img, dtype=float) + noise, 0, 255).astype("uint8"))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=60, dpi=(DPI, DPI))
    return buf.getvalue()

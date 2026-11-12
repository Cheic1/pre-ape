"""Riconoscimento di muri, aperture e vani su una planimetria raster (OpenCV).

Ipotesi tipiche delle planimetrie catastali: muri campiti di nero (spessori
reali 8–60 cm), tutto il resto a tratto sottile (quote, testi, cornice,
finestre disegnate come linee sottili nello spessore del muro, porte come
varchi). Passi:

1. binarizzazione (Otsu) → ``ink``;
2. apertura morfologica ~7 cm reali: restano solo i tratti spessi (muri); se
   resta troppo poco i muri sono a doppia linea e prima si chiudono;
3. si tengono le componenti abbastanza grandi (via testi in grassetto, frecce);
4. i varchi lungo i muri (≤ 1,5 m) si chiudono con una chiusura morfologica e
   si accettano solo i riempimenti "sottili" come lo spessore di un muro
   (un corridoio riempito viene scartato): sono le aperture, finestre se nel
   varco c'era tratto sottile, altrimenti porte;
5. sui muri chiusi: contorno esterno = sagoma, fori = vani.
"""
from __future__ import annotations

from typing import Dict, List

import cv2
import numpy as np

MIN_STROKE_M = 0.07  # tratti più sottili non sono muri
MIN_KERNEL_PX = 4  # le linee sottili a 300 dpi sono larghe 1–3 px
MAX_WALL_THICKNESS_M = 0.60
MAX_OPENING_M = 1.50
MIN_COMPONENT_SIDE_M = 0.80
MIN_ROOM_AREA_M2 = 0.8
SIMPLIFY_M = 0.03
ORTHO_TOLERANCE = np.tan(np.radians(4))


def _kernel(px: int) -> np.ndarray:
    px = max(1, int(px))
    return cv2.getStructuringElement(cv2.MORPH_RECT, (px, px))


def _wall_mask(ink: np.ndarray, px, warnings: List[str]) -> np.ndarray:
    walls = cv2.morphologyEx(ink, cv2.MORPH_OPEN, _kernel(max(MIN_KERNEL_PX, px(MIN_STROKE_M))))
    ink_area = int(np.count_nonzero(ink))
    if ink_area and np.count_nonzero(walls) < 0.15 * ink_area:
        # Muri disegnati a doppia linea: si riempie lo spazio fra le linee.
        closed = cv2.morphologyEx(ink, cv2.MORPH_CLOSE, _kernel(px(MAX_WALL_THICKNESS_M)))
        walls = cv2.morphologyEx(closed, cv2.MORPH_OPEN, _kernel(max(MIN_KERNEL_PX, px(MIN_STROKE_M))))
        warnings.append("Muri a doppia linea: riconoscimento meno preciso, verificare.")

    n, labels, stats, _ = cv2.connectedComponentsWithStats(walls, connectivity=8)
    min_side = px(MIN_COMPONENT_SIDE_M)
    min_area = px(0.08) * px(MIN_COMPONENT_SIDE_M)
    keep = np.zeros(n, dtype=bool)
    for i in range(1, n):
        w, h, area = stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT], stats[i, cv2.CC_STAT_AREA]
        keep[i] = max(w, h) >= min_side and area >= min_area
    return np.where(keep[labels], 255, 0).astype(np.uint8)


def _openings(walls: np.ndarray, ink: np.ndarray, px):
    """Riempimenti dei varchi (maschera) + lista (contorno, è_finestra)."""
    k = px(MAX_OPENING_M)
    closed = cv2.morphologyEx(walls, cv2.MORPH_CLOSE, _kernel(k))
    added = cv2.subtract(closed, walls)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(added, connectivity=4)
    mask = np.zeros_like(walls)
    found = []
    max_thick = px(MAX_WALL_THICKNESS_M)
    min_width = px(0.45)
    min_thick = px(MIN_STROKE_M)  # più sottili: sbavature lungo il bordo dei muri
    thin_ink = cv2.subtract(ink, walls)
    for i in range(1, n):
        area = stats[i, cv2.CC_STAT_AREA]
        if area < 4:
            continue
        comp = (labels == i).astype(np.uint8)
        contours, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cnt = max(contours, key=cv2.contourArea)
        (_, _), (rw, rh), _ = cv2.minAreaRect(cnt)
        short, long_ = sorted((rw, rh))
        # un varco: sottile come un muro, largo come una porta, quasi pieno
        if short > max_thick or short < min_thick or long_ < min_width or long_ > k * 1.05:
            continue
        if area < 0.6 * max(rw * rh, 1):
            continue
        mask[labels == i] = 255
        ink_ratio = np.count_nonzero(thin_ink[labels == i]) / area
        found.append((cnt, ink_ratio > 0.04))
    return mask, found


def _simplify(contour: np.ndarray, eps: float) -> np.ndarray:
    pts = cv2.approxPolyDP(contour, eps, True).reshape(-1, 2).astype(np.float64)
    if len(pts) < 3:
        return pts
    # rende ortogonali i lati quasi orizzontali/verticali
    for _ in range(2):
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            dx, dy = abs(b[0] - a[0]), abs(b[1] - a[1])
            if dx and dy / dx < ORTHO_TOLERANCE:
                a[1] = b[1] = (a[1] + b[1]) / 2
            elif dy and dx / dy < ORTHO_TOLERANCE:
                a[0] = b[0] = (a[0] + b[0]) / 2
    return pts


def _polygons(mask: np.ndarray, eps: float, min_px_area: float):
    """Maschera → [(esterno, [fori])] in pixel (RETR_CCOMP)."""
    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_SIMPLE)
    out = []
    if hierarchy is None:
        return out
    hierarchy = hierarchy[0]
    for i, cnt in enumerate(contours):
        if hierarchy[i][3] != -1 or cv2.contourArea(cnt) < min_px_area:
            continue
        holes = []
        child = hierarchy[i][2]
        while child != -1:
            if cv2.contourArea(contours[child]) >= min_px_area:
                holes.append(_simplify(contours[child], eps))
            child = hierarchy[child][0]
        out.append((_simplify(cnt, eps), holes))
    return out


def extract_geometry(gray: np.ndarray, mpp: float, warnings: List[str]) -> Dict:
    """Immagine (uint8) + metri/pixel → campi geometrici di ``FloorPlan``."""
    from app.core.planimetria import NoWallsFound

    def px(meters: float) -> int:
        return max(1, int(round(meters / mpp)))

    _, ink = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    walls = _wall_mask(ink, px, warnings)
    if np.count_nonzero(walls) == 0:
        raise NoWallsFound("Nessun muro riconosciuto nella planimetria")

    opening_mask, opening_list = _openings(walls, ink, px)
    closed = cv2.bitwise_or(walls, opening_mask)

    ys, xs = np.nonzero(closed)
    ox, oy = float(xs.min()), float(ys.max() + 1)

    def to_m(pts) -> List[tuple]:
        return [(round((x - ox) * mpp, 3), round((oy - y) * mpp, 3)) for x, y in pts]

    eps = max(1.0, SIMPLIFY_M / mpp)
    min_area_px = (0.05 / mpp) ** 2

    wall_polys = [
        {"outer": to_m(o), "holes": [to_m(h) for h in hs]}
        for o, hs in _polygons(walls, eps, min_area_px)
    ]

    # sagoma: contorni esterni dei muri chiusi (fori riempiti)
    ext, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    big = [c for c in ext if cv2.contourArea(c) * mpp * mpp >= 4.0]
    filled = np.zeros_like(closed)
    cv2.drawContours(filled, big, -1, 255, thickness=cv2.FILLED)
    footprint = [{"outer": to_m(_simplify(c, eps)), "holes": []} for c in big]
    gross = sum(cv2.contourArea(c) for c in big) * mpp * mpp
    perimeter = sum(cv2.arcLength(c, True) for c in big) * mpp

    # vani: spazio libero dentro la sagoma
    free = cv2.subtract(filled, closed)
    free = cv2.morphologyEx(free, cv2.MORPH_OPEN, _kernel(3))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(free, connectivity=4)
    rooms = []
    for i in range(1, n):
        area_m2 = stats[i, cv2.CC_STAT_AREA] * mpp * mpp
        if area_m2 < MIN_ROOM_AREA_M2:
            continue
        x, y, w, h = (stats[i, k] for k in (cv2.CC_STAT_LEFT, cv2.CC_STAT_TOP,
                                             cv2.CC_STAT_WIDTH, cv2.CC_STAT_HEIGHT))
        comp = np.zeros((h + 2, w + 2), np.uint8)
        comp[1:-1, 1:-1] = (labels[y:y + h, x:x + w] == i).astype(np.uint8) * 255
        cnts, _ = cv2.findContours(comp, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cnt = max(cnts, key=cv2.contourArea) + np.array([x - 1, y - 1])
        dist = cv2.distanceTransform(comp, cv2.DIST_L2, 3)
        ly, lx = np.unravel_index(int(np.argmax(dist)), dist.shape)
        rooms.append({
            "polygon": to_m(_simplify(cnt, eps)),
            "area_m2": round(area_m2, 2),
            "label_point": to_m([(lx + x - 1, ly + y - 1)])[0],
        })
    rooms.sort(key=lambda r: -r["area_m2"])

    # aperture: esterne se toccano lo spazio fuori dalla sagoma
    outside = cv2.dilate(cv2.bitwise_not(filled), _kernel(3))
    openings = []
    for cnt, has_ink in opening_list:
        comp = np.zeros_like(closed)
        cv2.drawContours(comp, [cnt], -1, 255, thickness=cv2.FILLED)
        exterior = bool(np.count_nonzero(cv2.bitwise_and(comp, outside)))
        (cx, cy), (rw, rh), ang = cv2.minAreaRect(cnt)
        box = cv2.boxPoints(((cx, cy), (rw, rh), ang))
        openings.append({
            "kind": "finestra" if has_ink else "porta",
            "polygon": to_m(box),
            "width_m": round(max(rw, rh) * mpp, 2),
            "exterior": exterior,
        })

    if not rooms:
        warnings.append("Nessun vano chiuso riconosciuto: controllare la planimetria.")

    windows = [o for o in openings if o["kind"] == "finestra"]
    return {
        "origin_px": (ox, oy),
        "walls": wall_polys,
        "footprint": footprint,
        "rooms": rooms,
        "openings": openings,
        "stats": {
            "gross_area_m2": round(gross, 2),
            "net_area_m2": round(sum(r["area_m2"] for r in rooms), 2),
            "perimeter_m": round(perimeter, 2),
            "rooms": len(rooms),
            "doors": len(openings) - len(windows),
            "windows": len(windows),
            "windows_width_m": round(sum(o["width_m"] for o in windows), 2),
        },
    }

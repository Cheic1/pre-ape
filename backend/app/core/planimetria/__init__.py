"""Planimetria catastale → geometria vettoriale (pianta 2D e modello 3D).

Pipeline (vedi ``extract_floor_plan``):

1. ``raster``: PDF (pagina renderizzata con pdfium) o immagine → scala di grigi,
   più dpi e testo della pagina (per leggere "Scala 1:200");
2. ``walls``: visione artificiale classica (OpenCV) → muri, vani, aperture e
   sagoma, già in **metri** (origine in basso a sinistra, asse y verso l'alto);
3. ``export``: DXF (pianta su layer + muri estrusi in 3D) e OBJ.

È un'estrazione automatica da un disegno in scala, non un rilievo: il
tecnico deve verificare misure e scala (``warnings``) prima di usarla.
"""
from __future__ import annotations

from typing import List, Literal, Optional, Tuple

from pydantic import BaseModel, ConfigDict, Field

Point = Tuple[float, float]

DEFAULT_SCALE = 200  # scala standard delle planimetrie catastali
DEFAULT_WALL_HEIGHT_M = 2.70


class Polygon(BaseModel):
    """Anello esterno + fori, in metri (antiorario/orario non garantito)."""

    outer: List[Point]
    holes: List[List[Point]] = Field(default_factory=list)


class Room(BaseModel):
    polygon: List[Point]
    area_m2: float
    label_point: Point  # punto interno, il più lontano dai muri
    label: Optional[str] = None


class Opening(BaseModel):
    kind: Literal["porta", "finestra"]
    polygon: List[Point]  # rettangolo nello spessore del muro
    width_m: float
    exterior: bool  # affaccia sull'esterno della sagoma


class PlanStats(BaseModel):
    gross_area_m2: float  # superficie lorda (sagoma, muri compresi)
    net_area_m2: float  # somma dei vani
    perimeter_m: float  # perimetro della sagoma
    rooms: int
    doors: int
    windows: int
    windows_width_m: float


class CadParams(BaseModel):
    """Parametri opzionali per ripetere l'estrazione (correzioni del tecnico)."""

    model_config = ConfigDict(extra="forbid")

    scale_denominator: Optional[int] = Field(default=None, ge=20, le=2000)
    wall_height_m: Optional[float] = Field(default=None, ge=2.0, le=8.0)
    # Calibrazione diretta (es. da due punti di distanza nota): ha la
    # precedenza su scala + dpi.
    meters_per_px: Optional[float] = Field(default=None, gt=0, le=1.0)
    page: int = Field(default=0, ge=0, le=49)


class FloorPlan(BaseModel):
    version: Literal[1] = 1
    source: Literal["cv", "cv+llm"] = "cv"
    page: int = 0
    scale_denominator: Optional[int]
    meters_per_px: float
    wall_height_m: float
    image_width_px: int
    image_height_px: int
    # pixel immagine (x, y) che corrisponde all'origine (0, 0) in metri:
    # x_m = (x_px - ox) * mpp ;  y_m = (oy - y_px) * mpp
    origin_px: Point
    walls: List[Polygon]
    footprint: List[Polygon]
    rooms: List[Room]
    openings: List[Opening]
    stats: PlanStats
    warnings: List[str] = Field(default_factory=list)


class NoWallsFound(ValueError):
    """Nella pagina non c'è nulla che somigli a dei muri."""


def extract_floor_plan(data: bytes, mime: str, params: Optional[CadParams] = None) -> FloorPlan:
    """Bytes del documento → ``FloorPlan`` (solleva ``NoWallsFound``/``ValueError``)."""
    from app.core.planimetria.raster import load_raster
    from app.core.planimetria.walls import extract_geometry

    params = params or CadParams()
    raster = load_raster(data, mime, page=params.page)
    warnings: List[str] = list(raster.warnings)

    scale = params.scale_denominator or raster.scale_denominator
    if params.meters_per_px:
        mpp = params.meters_per_px
    else:
        if scale is None:
            scale = DEFAULT_SCALE
            warnings.append(
                f"Scala non trovata nel documento: assunta 1:{DEFAULT_SCALE}, da verificare."
            )
        if raster.dpi is None:
            warnings.append(
                "Immagine senza risoluzione (dpi): misure non affidabili, calibrare la scala."
            )
        dpi = raster.dpi or 300.0
        mpp = (25.4 / dpi) / 1000.0 * scale

    height = params.wall_height_m or DEFAULT_WALL_HEIGHT_M
    plan = extract_geometry(raster.gray, mpp, warnings)
    return FloorPlan(
        page=params.page,
        scale_denominator=None if params.meters_per_px else scale,
        meters_per_px=mpp,
        wall_height_m=height,
        image_width_px=int(raster.gray.shape[1]),
        image_height_px=int(raster.gray.shape[0]),
        warnings=warnings,
        **plan,
    )

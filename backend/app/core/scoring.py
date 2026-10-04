"""Preliminary energy score — server-side port of `frontend/lib/core/scoring.dart`.

The formula is intentionally identical to the Flutter client (base 30, area
bonus, wall/window/heating bonuses, clamp 0–100) so the score shown live in the
wizard and the one stored with the survey always agree. It is an *indicative*
pre-survey estimate, NOT an APE classification (UNI/TS 11300 is computed by the
certifier's own software).
"""
from typing import Optional

# Best (A4) → worst (G); must stay aligned with kEnergyClassLetters (Dart).
ENERGY_CLASS_LETTERS = ["A4", "A3", "A2", "A1", "B", "C", "D", "E", "F", "G"]

_WALL_BONUS = {">40cm": 25, "30-40cm": 15, "<30cm": 5}
_HEATING_BONUS = {"Pompa di Calore": 10, "Condensazione": 8, "Pellet": 6}


def compute_score(
    *,
    square_meters: Optional[float] = None,
    wall_thickness: Optional[str] = None,
    window_frame: Optional[str] = None,
    window_glass: Optional[str] = None,
    heating_type: Optional[str] = None,
) -> float:
    score = 30.0
    if square_meters and square_meters > 0:
        score += min(max(square_meters / 100, 0), 20)

    score += _WALL_BONUS.get(wall_thickness or "", 0)

    # The client stores "<frame> <glass>" as one windowType string: any window
    # answer counts, glass decides the bonus.
    if window_frame or window_glass:
        glass = window_glass or ""
        if "Triplo" in glass:
            score += 15
        elif "Doppio" in glass:
            score += 10
        else:
            score += 5

    score += _HEATING_BONUS.get(heating_type or "", 2)
    return float(min(max(score, 0), 100))


def energy_class_for_score(score: float) -> str:
    normalized = min(max(score, 0), 100)
    # Dart's double.round() rounds half away from zero; Python's round() is
    # banker's rounding, so use floor(x + 0.5) for positive values.
    index = min(max(int(normalized / 100 * 9 + 0.5), 0), 9)
    return ENERGY_CLASS_LETTERS[9 - index]

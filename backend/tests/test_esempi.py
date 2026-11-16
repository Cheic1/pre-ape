"""Le pratiche di esempio devono restare valide rispetto al contratto API."""
from pathlib import Path

from app.api.v1 import SurveyCreate
from app.esempi import PRATICHE, PREFISSO


def test_pratiche_valide():
    titoli = set()
    for p in PRATICHE:
        body = {k: v for k, v in p.items() if k != "planimetria"}
        SurveyCreate.model_validate(body)
        assert body["title"].startswith(PREFISSO)
        titoli.add(body["title"])
    assert len(titoli) == len(PRATICHE) >= 5


def test_planimetria_presente():
    here = Path(__file__).resolve().parents[1] / "app" / "esempi"
    for p in PRATICHE:
        if p.get("planimetria"):
            assert (here / p["planimetria"]).read_bytes().startswith(b"%PDF-")

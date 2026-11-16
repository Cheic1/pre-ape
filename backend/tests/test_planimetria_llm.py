"""Agente LLM opzionale della planimetria (API compatibile OpenAI, es. freellmapi).

Un server HTTP locale finge il provider: si verifica la richiesta (immagine,
modello, chiave), l'uso della risposta e il fallback quando non risponde.
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from planimetria_fixtures import A4_PX, ORIGIN, PX_PER_M, plan_pdf, plan_png

from app.core.config import settings
from app.core.planimetria import CadParams, extract_floor_plan
from app.core.planimetria.llm import parse_hints

PDF = "application/pdf"


def _frac(x_m, y_m):
    return (ORIGIN[0] + x_m * PX_PER_M) / A4_PX[0], (ORIGIN[1] - y_m * PX_PER_M) / A4_PX[1]


def _answer(scale=200, height=2.9):
    rooms = []
    for name, (x, y) in (("CAMERA", (1.5, 2.0)), ("SOGGIORNO", (1.5, 6.0)), ("CUCINA", (7.0, 4.5))):
        fx, fy = _frac(x, y)
        rooms.append({"name": name, "x": fx, "y": fy})
    body = {"scale_denominator": scale, "wall_height_m": height, "rooms": rooms}
    return "Ecco il risultato:\n```json\n" + json.dumps(body) + "\n```"


class _Fake:
    def __init__(self, status=200, content=None):
        self.status, self.content, self.requests = status, content or _answer(), []

    def __enter__(self):
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                length = int(self.headers["Content-Length"])
                fake.requests.append((self.path, dict(self.headers), json.loads(self.rfile.read(length))))
                body = json.dumps({"choices": [{"message": {"content": fake.content}}]}).encode()
                self.send_response(fake.status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_port}/v1"
        return self

    def __exit__(self, *exc):
        self.server.shutdown()


@pytest.fixture
def llm(monkeypatch):
    def configure(url):
        monkeypatch.setattr(settings, "LLM_BASE_URL", url)
        monkeypatch.setattr(settings, "LLM_MODEL", "gemini-vision")
        monkeypatch.setattr(settings, "LLM_API_KEY", "chiave-di-prova")
        monkeypatch.setattr(settings, "LLM_TIMEOUT_S", 5.0)
    return configure


def test_disabled_by_default():
    plan = extract_floor_plan(plan_pdf(), PDF)
    assert plan.source == "cv"
    assert all(r.label is None for r in plan.rooms)


def test_rooms_named_and_height_from_ai(llm):
    with _Fake() as fake:
        llm(fake.url)
        plan = extract_floor_plan(plan_pdf(), PDF)
    assert plan.source == "cv+llm"
    assert plan.wall_height_m == 2.9
    labels = {r.label for r in plan.rooms}
    assert labels == {"CAMERA", "SOGGIORNO", "CUCINA"}
    path, headers, body = fake.requests[0]
    assert path == "/v1/chat/completions"
    assert headers["Authorization"] == "Bearer chiave-di-prova"
    assert body["model"] == "gemini-vision"
    image = body["messages"][0]["content"][1]["image_url"]["url"]
    assert image.startswith("data:image/png;base64,")


def test_user_values_win_over_ai(llm):
    with _Fake() as fake:
        llm(fake.url)
        plan = extract_floor_plan(plan_pdf(), PDF, CadParams(wall_height_m=3.2))
    assert plan.wall_height_m == 3.2


def test_ai_scale_used_when_document_has_none(llm):
    with _Fake(content=_answer(scale=100)) as fake:
        llm(fake.url)
        plan = extract_floor_plan(plan_png(), "image/png")
    assert plan.scale_denominator == 100
    assert any("letta dall'AI" in w for w in plan.warnings)


def test_use_ai_false_skips_call(llm):
    with _Fake() as fake:
        llm(fake.url)
        plan = extract_floor_plan(plan_pdf(), PDF, CadParams(use_ai=False))
    assert fake.requests == [] and plan.source == "cv"


@pytest.mark.parametrize("status,content", [(500, None), (200, "non so leggerla")])
def test_fallback_when_provider_fails(llm, status, content):
    with _Fake(status=status, content=content) as fake:
        llm(fake.url)
        plan = extract_floor_plan(plan_pdf(), PDF)
    assert plan.source == "cv"
    assert plan.stats.rooms == 3
    assert any("Analisi AI non disponibile" in w for w in plan.warnings)


def test_unreachable_provider_falls_back(llm):
    llm("http://127.0.0.1:9/v1")
    plan = extract_floor_plan(plan_pdf(), PDF)
    assert plan.source == "cv" and plan.stats.rooms == 3


def test_parse_hints_rejects_implausible_values():
    hints = parse_hints(
        '{"scale_denominator": 3, "wall_height_m": "2,85", "rooms": ['
        '{"name": "bagno", "x": 0.5, "y": 0.5}, {"name": "", "x": 0.1, "y": 0.1},'
        '{"name": "fuori", "x": 1.5, "y": 0.2}, "x"]}',
        1000, 2000,
    )
    assert hints.scale_denominator is None
    assert hints.wall_height_m == 2.85
    assert hints.rooms == [("BAGNO", 500.0, 1000.0)]

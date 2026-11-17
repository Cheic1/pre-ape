"""Caccia ai bug delle funzioni AI: LLM "dispettoso" + property-based testing.

Nessuna rete e niente database: l'LLM è finto, il motore è puro.
Regola di base: qualunque cosa risponda il modello, il consulente deve
restituire un risultato valido o un AdvisorError (→ 502), mai un 500.
"""
import json
import math
import typing

import pytest
from hypothesis import HealthCheck, given, settings as hsettings, strategies as st

from app.core import advisor
from app.core.config import settings
from app.core.energy import BuildingInputs, compute
from app.core.planimetria import llm as plan_llm

FLAT = dict(comune="Milano", tipologia="appartamento", anno_costruzione=1965,
            piano="ultimo", telaio="Legno", vetro="Singolo",
            generatore="caldaia_tradizionale", anno_generatore=1995)
CLASSES = {"A4", "A3", "A2", "A1", "B", "C", "D", "E", "F", "G"}


@pytest.fixture(autouse=True)
def _llm_on(monkeypatch):
    monkeypatch.setattr(settings, "LLM_BASE_URL", "http://llm.test/v1")
    monkeypatch.setattr(settings, "LLM_MODEL", "modello-test")


def _msg(content=None, tool_calls=None):
    return {"choices": [{"message": {"role": "assistant", "content": content,
                                     "tool_calls": tool_calls}}]}


def _seq(*responses):
    responses = list(responses)
    return lambda payload: responses.pop(0) if len(responses) > 1 else responses[0]


def _run(transport):
    """None se ok, 'AdvisorError' se errore gestito; altre eccezioni = bug."""
    try:
        return advisor.run(BuildingInputs(**FLAT), square_meters=80, transport=transport)
    except advisor.AdvisorError:
        return "AdvisorError"


GOOD_FINAL = json.dumps({"sintesi": "ok", "raccomandazioni": [{"rif": "copertura"}],
                         "avvertenze": ["x"]})

# --- 1. risposte malformate del servizio LLM -------------------------------
MALFORMED = {
    "choices_vuoto": {"choices": []},
    "message_null": {"choices": [{"message": None}]},
    "message_stringa": {"choices": [{"message": "ciao"}]},
    "risposta_lista": [1, 2, 3],
    "content_numero": _msg(content=42),
    "json_lista": _msg(content="[1, 2]"),
    "json_troncato": _msg(content='{"sintesi": "a"'),
    "tool_call_stringa": _msg(tool_calls=["simula_scenario"]),
    "tool_calls_dict": _msg(tool_calls={"id": "x"}),
    "function_stringa": _msg(tool_calls=[{"id": "c", "function": "simula_scenario"}]),
    "arguments_lista": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario", "arguments": "[1,2]"}}]),
    "arguments_dict_non_stringa": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario", "arguments": {"nome": "x"}}}]),
    "modifiche_lista": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario",
        "arguments": json.dumps({"nome": "x", "modifiche": ["vmc"], "investimento_eur": 1000})}}]),
    "investimento_nan": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario",
        "arguments": '{"nome": "x", "modifiche": {"vmc": "recupero"}, "investimento_eur": NaN}'}}]),
    "investimento_stringa_inf": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario",
        "arguments": json.dumps({"nome": "x", "modifiche": {"vmc": "recupero"},
                                 "investimento_eur": "inf"})}}]),
    "modifiche_valore_dict": _msg(tool_calls=[{"id": "c", "function": {
        "name": "simula_scenario",
        "arguments": json.dumps({"nome": "x", "modifiche": {"telaio": {"a": 1}},
                                 "investimento_eur": 1000})}}]),
}


@pytest.mark.parametrize("name", sorted(MALFORMED))
def test_malformed_llm_response_never_500(name):
    out = _run(_seq(MALFORMED[name], _msg(content=GOOD_FINAL)))
    assert out == "AdvisorError" or isinstance(out, dict)


# --- 2. JSON finale con tipi sbagliati ---------------------------------------
BAD_FINALS = {
    "raccomandazioni_dict": {"raccomandazioni": {"rif": "copertura"}},
    "raccomandazioni_stringa": {"raccomandazioni": "copertura"},
    "avvertenze_stringa": {"raccomandazioni": [], "avvertenze": "Attenzione ai massimali"},
    "rif_lista": {"raccomandazioni": [{"rif": ["copertura"]}]},
    "rif_dict": {"raccomandazioni": [{"rif": {"a": 1}}]},
}


@pytest.mark.parametrize("name", sorted(BAD_FINALS))
def test_bad_final_json_never_500(name):
    out = _run(_seq(_msg(content=json.dumps(BAD_FINALS[name]))))
    assert out == "AdvisorError" or isinstance(out, dict)


def test_string_warnings_not_split_into_characters():
    out = _run(_seq(_msg(content=json.dumps(BAD_FINALS["avvertenze_stringa"]))))
    assert isinstance(out, dict)
    assert all(len(w) > 1 for w in out["avvertenze"]), out["avvertenze"]


# --- 3. il modello non deve poter "spacciare" numeri ------------------------
def _scenario_call(nome, invest, modifiche=None, cid="c1"):
    return {"id": cid, "type": "function", "function": {
        "name": "simula_scenario",
        "arguments": json.dumps({"nome": nome, "investimento_eur": invest,
                                 "modifiche": modifiche or {"isolamento_pareti_cm": 12}})}}


def test_scenario_cannot_overwrite_engine_intervention():
    base = compute(BuildingInputs(**FLAT), square_meters=80)
    code = base["interventi"][0]["codice"]
    engine_invest = base["interventi"][0]["investimento_eur"]
    final = json.dumps({"raccomandazioni": [{"rif": code}]})
    out = _run(_seq(_msg(tool_calls=[_scenario_call(code, 999)]), _msg(content=final)))
    assert out["raccomandazioni"][0]["investimento_eur"] == engine_invest


def test_tiny_investment_is_rejected_not_reported_as_zero():
    sess = advisor._Session(BuildingInputs(**FLAT), dict(square_meters=80),
                            compute(BuildingInputs(**FLAT), square_meters=80))
    out = sess.simulate({"nome": "Mini", "investimento_eur": 40,
                         "modifiche": {"isolamento_pareti_cm": 12}})
    assert "errore" in out
    ok = sess.simulate({"nome": "Ok", "investimento_eur": 149,
                        "modifiche": {"isolamento_pareti_cm": 12}})
    assert ok["investimento_eur"] == 100 and ok["incentivo_eur"] <= 100


def test_endless_tool_calls_end_with_advisor_error():
    out = _run(lambda p: _msg(tool_calls=[_scenario_call("x", 1000)]))
    assert out == "AdvisorError"


# --- 4. planimetria: parse_hints con testo arbitrario -----------------------
@pytest.mark.parametrize("text", [
    "[1, 2, 3]", '"solo stringa"', "{\"rooms\": 5}", "{\"rooms\": {\"name\": \"x\"}}",
    "{\"rooms\": [{\"name\": \"CUCINA\", \"x\": true, \"y\": 0.5}]}",
    "{\"wall_height_m\": NaN, \"scale_denominator\": Infinity}",
    "{\"a\": 1} e poi {\"b\": 2}",
])
def test_parse_hints_raises_only_handled_errors(text):
    try:
        hints = plan_llm.parse_hints(text, 1000, 800)
    except (ValueError, KeyError, IndexError, TypeError):
        return  # gestito da safe_analyze
    for name, x, y in hints.rooms:
        assert isinstance(x, float) or type(x) is int
        assert 0 <= x <= 1000 and 0 <= y <= 800


def test_safe_analyze_never_raises(monkeypatch):
    import numpy as np
    monkeypatch.setattr(plan_llm, "_chat", lambda s, url: "[1, 2]")
    warnings = []
    assert plan_llm.safe_analyze(np.zeros((10, 10), np.uint8), warnings, settings) is None
    assert warnings


@hsettings(max_examples=300, deadline=None)
@given(st.text())
def test_parse_hints_fuzz(text):
    try:
        plan_llm.parse_hints(text, 1000, 800)
    except (ValueError, KeyError, IndexError, TypeError):
        pass


# --- 5. motore energetico: proprietà che devono valere sempre ---------------
def _field_strategy(annotation, field):
    args = [a for a in typing.get_args(annotation) if a is not type(None)]
    inner = args[0] if args else annotation
    if typing.get_origin(inner) is typing.Literal:
        return st.sampled_from(typing.get_args(inner))
    ge = next((m.ge for m in field.metadata if getattr(m, "ge", None) is not None), 0)
    le = next((m.le for m in field.metadata if getattr(m, "le", None) is not None), 100)
    if inner is bool:
        return st.booleans()
    if inner is int:
        return st.integers(ge, le)
    if inner is float:
        return st.floats(ge, le, allow_nan=False)
    return None


_SKIP = {"comune", "provincia"}
BUILDINGS = st.fixed_dictionaries({}, optional={
    name: s for name, f in BuildingInputs.model_fields.items()
    if name not in _SKIP and (s := _field_strategy(f.annotation, f)) is not None
}).map(lambda d: BuildingInputs(**d))
SQM = st.one_of(st.none(), st.floats(15, 2000))
FAST = hsettings(max_examples=150, deadline=None,
                 suppress_health_check=[HealthCheck.too_slow])


def _finite(obj, path="r"):
    if isinstance(obj, float):
        assert math.isfinite(obj), path
    elif isinstance(obj, dict):
        for k, v in obj.items():
            _finite(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            _finite(v, f"{path}[{i}]")


@FAST
@given(BUILDINGS, SQM)
def test_engine_always_valid(building, sqm):
    res = compute(building, square_meters=sqm)
    assert res["classe"] in CLASSES
    assert res["costo_annuo_eur"] >= 0
    _finite(res)
    for item in res.get("interventi", []):
        assert item["classe"] in CLASSES
        assert item["investimento_eur"] >= 0
        assert item["incentivo_eur"] <= item["investimento_eur"] + 10


@FAST
@given(BUILDINGS, SQM, st.sampled_from(["isolamento_pareti_cm", "isolamento_copertura_cm",
                                        "isolamento_pavimento_cm"]))
def test_more_insulation_never_increases_ep(building, sqm, field):
    data = building.model_dump(exclude_none=True)
    lo = {**data, field: data.get(field, 0)}
    hi = {**lo, field: min(40, lo[field] + 10)}
    ep_lo = compute(BuildingInputs(**lo), square_meters=sqm, with_improvements=False)["ep"]["gl_nren"]
    ep_hi = compute(BuildingInputs(**hi), square_meters=sqm, with_improvements=False)["ep"]["gl_nren"]
    assert ep_hi <= ep_lo + 1e-6


@FAST
@given(BUILDINGS, SQM)
def test_advisor_simulation_matches_engine(building, sqm):
    """Uno scenario del consulente con gli stessi dati non deve dare risparmio."""
    base = compute(building, square_meters=sqm)
    sess = advisor._Session(building, dict(square_meters=sqm, avg_height=None, address=None,
                                           latitude=None, longitude=None), base)
    vmc = building.vmc or "nessuna"
    out = sess.simulate({"nome": "x", "modifiche": {"vmc": vmc}, "investimento_eur": 1000})
    assert out.get("risparmio_annuo_eur", 0) == 0, out

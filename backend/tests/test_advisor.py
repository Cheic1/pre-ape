"""Agente consulente (app.core.advisor) con un LLM finto: niente rete."""
import json

import pytest

from app.core import advisor
from app.core.config import settings
from app.core.energy import BuildingInputs

API = "/api/v1"
FLAT = dict(comune="Milano", tipologia="appartamento", anno_costruzione=1965,
            piano="ultimo", telaio="Legno", vetro="Singolo",
            generatore="caldaia_tradizionale", anno_generatore=1995)


def _msg(content=None, tool_calls=None):
    return {"choices": [{"message": {"role": "assistant", "content": content,
                                     "tool_calls": tool_calls}}]}


def _call(args, name="simula_scenario", cid="c1"):
    return {"id": cid, "type": "function",
            "function": {"name": name, "arguments": json.dumps(args)}}


class FakeLLM:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.payloads = []

    def __call__(self, payload):
        self.payloads.append(json.loads(json.dumps(payload)))
        return self.responses.pop(0)


FINAL = {
    "sintesi": "Conviene partire dall'involucro.",
    "raccomandazioni": [
        {"rif": "Cappotto + PdC", "titolo": "Cappotto e pompa di calore", "motivazione": "Massimo risparmio."},
        {"rif": "copertura", "titolo": "Isolare il sottotetto", "motivazione": "Rientro rapido."},
        {"rif": "inventato", "titolo": "Non esiste", "motivazione": "x"},
    ],
    "avvertenze": ["Verificare i massimali."],
}


@pytest.fixture
def llm_on(monkeypatch):
    monkeypatch.setattr(settings, "LLM_BASE_URL", "http://llm.test/v1")
    monkeypatch.setattr(settings, "LLM_MODEL", "modello-test")


def test_disabled_without_config(monkeypatch):
    monkeypatch.setattr(settings, "LLM_BASE_URL", "")
    assert not advisor.is_enabled()
    with pytest.raises(advisor.AdvisorDisabled):
        advisor.run(BuildingInputs(**FLAT), square_meters=80)


def test_agent_uses_engine_numbers_and_drops_unknown_refs(llm_on):
    fake = FakeLLM(
        _msg(tool_calls=[_call({"nome": "Cappotto + PdC", "investimento_eur": 20000,
                                "modifiche": {"isolamento_pareti_cm": 12,
                                              "generatore": "pompa_calore_aria_acqua"}})]),
        _msg(content="```json\n" + json.dumps(FINAL) + "\n```"),
    )
    out = advisor.run(BuildingInputs(**FLAT), square_meters=80, transport=fake)

    # il contesto mandato all'LLM non contiene indirizzo o dati personali
    ctx = json.loads(fake.payloads[0]["messages"][1]["content"])
    assert ctx["comune"] == "Milano" and "indirizzo" not in json.dumps(ctx)
    assert ctx["interventi_simulati"]
    # lo strumento ha ricevuto i numeri del motore
    tool_reply = json.loads(fake.payloads[1]["messages"][-1]["content"])
    assert tool_reply["risparmio_annuo_eur"] > 0 and tool_reply["incentivo_eur"] == 10000

    recs = out["raccomandazioni"]
    assert [r["rif"] for r in recs] == ["Cappotto + PdC", "copertura"]
    assert recs[0]["investimento_eur"] == 20000 and recs[0]["incentivo_eur"] == 10000
    assert recs[0]["tempo_ritorno_netto_anni"] is not None
    assert len(recs[0]["flusso_cassa_cumulato"]) == 16
    assert recs[1]["investimento_eur"] > 0
    assert out["sintesi"] and out["avvertenze"] == ["Verificare i massimali."]
    assert "non sostituisce" in out["nota"]


def test_tool_rejects_bad_changes(llm_on):
    fake = FakeLLM(
        _msg(tool_calls=[_call({"nome": "x", "investimento_eur": 1000,
                                "modifiche": {"anno_costruzione": 2020}})]),
        _msg(content=json.dumps({"sintesi": "ok", "raccomandazioni": []})),
    )
    out = advisor.run(BuildingInputs(**FLAT), square_meters=80, transport=fake)
    err = json.loads(fake.payloads[1]["messages"][-1]["content"])
    assert "non modificabili" in err["errore"]
    assert out["raccomandazioni"] == []


def test_invalid_final_answer(llm_on):
    with pytest.raises(advisor.AdvisorError):
        advisor.run(BuildingInputs(**FLAT), transport=FakeLLM(_msg(content="Ciao!")))


class TestAdvisorApi:
    def test_status_and_503_when_disabled(self, client, auth_a, monkeypatch):
        monkeypatch.setattr(settings, "LLM_BASE_URL", "")
        headers, _ = auth_a
        assert client.get(f"{API}/advisor/status").status_code == 401
        assert client.get(f"{API}/advisor/status", headers=headers).json() == {
            "enabled": False, "modello": None}
        r = client.post(f"{API}/advisor", headers=headers, json={"building": FLAT})
        assert r.status_code == 503

    def test_run_and_502_on_llm_error(self, client, auth_a, llm_on, monkeypatch):
        headers, _ = auth_a
        assert client.get(f"{API}/advisor/status", headers=headers).json()["enabled"] is True
        fake = FakeLLM(_msg(content=json.dumps(FINAL)))
        monkeypatch.setattr(advisor, "_http_transport", fake)
        r = client.post(f"{API}/advisor", headers=headers,
                        json={"building": FLAT, "square_meters": 80})
        assert r.status_code == 200
        assert [x["rif"] for x in r.json()["raccomandazioni"]] == ["copertura"]

        def boom(payload):
            raise advisor.AdvisorError("servizio LLM non raggiungibile")
        monkeypatch.setattr(advisor, "_http_transport", boom)
        r = client.post(f"{API}/advisor", headers=headers, json={"building": FLAT})
        assert r.status_code == 502

    def test_validation(self, client, auth_a):
        headers, _ = auth_a
        assert client.post(f"{API}/advisor", headers=headers,
                           json={"building": {"pippo": 1}}).status_code == 422

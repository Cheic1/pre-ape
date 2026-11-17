"""Agente «consulente» sugli interventi migliorativi (LLM OpenAI-compatibile).

L'LLM (es. un'istanza freellmapi) non calcola numeri: legge gli interventi già
simulati dal motore (``app.core.energy``) e può chiedere al motore altre
combinazioni con lo strumento ``simula_scenario``. Nella risposta finale indica
solo *quali* interventi/scenari consiglia e perché; costi, incentivi, risparmi
e tempi di rientro li riattacca il server dai risultati del motore, così un
numero inventato dal modello non arriva mai al geometra.

Configurazione (env, vedi ``app.core.config``): ``LLM_BASE_URL`` (es.
``http://host:porta/v1``), ``LLM_MODEL`` (deve supportare il tool calling),
``LLM_API_KEY`` (facoltativa), ``LLM_TIMEOUT_SECONDS``. Senza URL o modello
l'agente è disattivato e l'app nasconde il pulsante.

All'LLM vanno solo dati tecnici dell'edificio e il comune: niente indirizzo,
nome del cliente, note o foto.
"""
from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from app.core.config import settings
from app.core.energy import BuildingInputs, compute
from app.core.energy import engine

logger = logging.getLogger(__name__)

MAX_ROUNDS = 6
MAX_SCENARIOS = 8

# Campi che l'agente può cambiare in uno scenario (gli altri descrivono lo stato attuale).
_EDITABLE = {
    "isolamento_pareti_cm", "isolamento_copertura_cm", "isolamento_pavimento_cm",
    "telaio", "vetro", "generatore", "combustibile", "anno_generatore", "terminali",
    "regolazione", "acs", "solare_termico", "fotovoltaico_kwp", "vmc",
}


class AdvisorDisabled(RuntimeError):
    """LLM non configurato (manca LLM_BASE_URL o LLM_MODEL)."""


class AdvisorError(RuntimeError):
    """Il servizio LLM non ha risposto o ha risposto in modo inutilizzabile."""


Transport = Callable[[Dict[str, Any]], Dict[str, Any]]


def is_enabled() -> bool:
    return bool(settings.LLM_BASE_URL.strip() and settings.LLM_MODEL.strip())


def _http_transport(payload: Dict[str, Any]) -> Dict[str, Any]:
    url = settings.LLM_BASE_URL.rstrip("/") + "/chat/completions"
    headers = {"Content-Type": "application/json"}
    if settings.LLM_API_KEY:
        headers["Authorization"] = f"Bearer {settings.LLM_API_KEY}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=settings.LLM_TIMEOUT_SECONDS) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise AdvisorError(f"il servizio LLM ha risposto {exc.code}") from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise AdvisorError("servizio LLM non raggiungibile") from exc
    except ValueError as exc:
        raise AdvisorError("risposta del servizio LLM non valida") from exc


_TOOLS = [{
    "type": "function",
    "function": {
        "name": "simula_scenario",
        "description": (
            "Ricalcola la stima energetica dell'edificio con le modifiche indicate "
            "(una combinazione di interventi) e restituisce classe, risparmio annuo, "
            "incentivo, costo netto e tempo di rientro. Usalo per valutare combinazioni "
            "diverse da quelle già simulate."),
        "parameters": {
            "type": "object",
            "properties": {
                "nome": {"type": "string", "description": "Nome breve dello scenario, in italiano"},
                "modifiche": {
                    "type": "object",
                    "description": ("Campi dei dati edificio da cambiare. Ammessi: "
                                    + ", ".join(sorted(_EDITABLE))
                                    + ". Valori come nei dati dell'edificio forniti."),
                },
                "investimento_eur": {"type": "number", "description": "Costo stimato IVA inclusa"},
                "agevolabile": {"type": "boolean",
                                "description": "false se non rientra nelle detrazioni (es. caldaia a gas)"},
            },
            "required": ["nome", "modifiche", "investimento_eur"],
        },
    },
}]

_SYSTEM = """Sei un consulente di efficienza energetica che aiuta un geometra italiano.
Ricevi i dati di un edificio e una stima preliminare (non è un APE) con gli interventi già
simulati dal motore di calcolo. Il tuo compito: scegliere gli interventi o le combinazioni
più convenienti per QUESTO edificio, mettendo in evidenza costo, incentivo, risparmio annuo e
in quanti anni si rientra dell'investimento.

Regole:
- Non inventare numeri. Ogni valore economico viene dal motore: usa gli interventi forniti
  (campo "codice") oppure chiama lo strumento simula_scenario per combinazioni nuove.
- Al massimo %d scenari nuovi. Usa costi realistici IVA inclusa.
- Rispondi alla fine SOLO con un oggetto JSON, senza testo attorno:
  {"sintesi": "2-4 frasi per il cliente",
   "raccomandazioni": [{"rif": "<codice intervento o nome scenario>",
                        "titolo": "...", "motivazione": "1-2 frasi", "priorita": 1}],
   "avvertenze": ["..."]}
- Al massimo 4 raccomandazioni, ordinate per priorità. Scrivi in italiano semplice.""" % MAX_SCENARIOS


def _intervention_view(item: Dict[str, Any]) -> Dict[str, Any]:
    keys = ("codice", "intervento", "classe", "riduzione_ep_pct", "risparmio_annuo_eur",
            "investimento_eur", "incentivo_eur", "investimento_netto_eur",
            "tempo_ritorno_anni", "tempo_ritorno_netto_anni")
    return {k: item.get(k) for k in keys}


def _context(building: BuildingInputs, result: Dict[str, Any]) -> Dict[str, Any]:
    comune = (result.get("clima") or {}).get("comune") or {}
    return {
        "comune": comune.get("comune") if isinstance(comune, dict) else None,
        "zona_climatica": result["clima"]["zona"],
        "gradi_giorno": result["clima"]["gradi_giorno"],
        "superficie_m2": result.get("geometria", {}).get("superficie_utile"),
        "dati_edificio": building.model_dump(exclude_none=True, exclude={"comune", "provincia"}),
        "stato_attuale": {
            "classe": result["classe"],
            "ep_gl_nren": result["ep"]["gl_nren"],
            "costo_annuo_eur": result["costo_annuo_eur"],
            "generatore": result["impianto"]["generatore"],
        },
        "note_incentivi": result.get("note_incentivi"),
        "interventi_simulati": [_intervention_view(i) for i in result.get("interventi", [])],
    }


class _Session:
    def __init__(self, building: BuildingInputs, kwargs: Dict[str, Any], base: Dict[str, Any]):
        self.building = building
        self.kwargs = kwargs
        self.base = base
        self.scenarios: Dict[str, Dict[str, Any]] = {}
        self.reserved = {i.get("codice") for i in base.get("interventi", [])}

    def simulate(self, args: Dict[str, Any]) -> Dict[str, Any]:
        if len(self.scenarios) >= MAX_SCENARIOS:
            return {"errore": "limite di scenari raggiunto"}
        name = str(args.get("nome") or f"Scenario {len(self.scenarios) + 1}")[:80]
        changes = args.get("modifiche") or {}
        if not isinstance(changes, dict) or not changes:
            return {"errore": "modifiche mancanti"}
        bad = sorted(set(changes) - _EDITABLE)
        if bad:
            return {"errore": f"campi non modificabili: {', '.join(bad)}"}
        if name in self.reserved:
            return {"errore": f"nome già usato da un intervento simulato: {name}"}
        try:
            invest = float(args.get("investimento_eur") or 0)
        except (TypeError, ValueError):
            return {"errore": "investimento_eur non numerico"}
        if not 100 <= invest <= 500_000:  # NaN/inf falliscono il confronto
            return {"errore": "investimento_eur fuori scala (100–500000 €)"}
        invest = int(round(invest, -2))
        try:
            variant = BuildingInputs.model_validate(
                {**self.building.model_dump(exclude_none=True), **changes})
        except ValueError as exc:
            return {"errore": f"valori non validi: {exc.errors()[0].get('msg', '')}"[:200]}
        res = compute(variant, with_improvements=False, **self.kwargs)
        saving = self.base["costo_annuo_eur"] - res["costo_annuo_eur"]
        principale = self.building.abitazione_principale is not False
        rate = engine.INCENTIVE_RATE_MAIN if principale else engine.INCENTIVE_RATE_OTHER
        incentive = invest * rate if args.get("agevolabile", True) else 0.0
        out = {
            "codice": name,
            "intervento": name,
            "classe": res["classe"],
            "ep_gl_nren": res["ep"]["gl_nren"],
            "riduzione_ep_pct": round(100 * (1 - res["ep"]["gl_nren"] / self.base["ep"]["gl_nren"]), 1)
            if self.base["ep"]["gl_nren"] else 0.0,
            "risparmio_annuo_eur": round(saving),
            "investimento_eur": invest,
            "tempo_ritorno_anni": round(invest / saving, 1) if saving > 50 else None,
            **engine._economics(invest, incentive, saving),
            "modifiche": changes,
        }
        self.scenarios[name] = out
        return {k: v for k, v in out.items() if k != "flusso_cassa_cumulato"}


def _parse_final(text: str) -> Dict[str, Any]:
    text = (text or "").strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text[text.find("{"):] if "{" in text else text
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        raise AdvisorError("il modello non ha restituito un JSON")
    try:
        data = json.loads(text[start:end + 1])
    except ValueError as exc:
        raise AdvisorError("il modello ha restituito un JSON non valido") from exc
    if not isinstance(data, dict):
        raise AdvisorError("il modello ha restituito un JSON non valido")
    return data


def run(
    building: Optional[BuildingInputs],
    *,
    square_meters: Optional[float] = None,
    avg_height: Optional[float] = None,
    address: Optional[str] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    transport: Optional[Transport] = None,
) -> Dict[str, Any]:
    """Esegue l'agente e restituisce raccomandazioni con i numeri del motore."""
    if transport is None:
        if not is_enabled():
            raise AdvisorDisabled("agente consulente non configurato")
        transport = _http_transport
    building = building or BuildingInputs()
    kwargs = dict(square_meters=square_meters, avg_height=avg_height, address=address,
                  latitude=latitude, longitude=longitude)
    base = compute(building, **kwargs)
    session = _Session(building, kwargs, base)
    messages: List[Dict[str, Any]] = [
        {"role": "system", "content": _SYSTEM},
        {"role": "user", "content": json.dumps(_context(building, base), ensure_ascii=False)},
    ]
    final: Optional[Dict[str, Any]] = None
    for _ in range(MAX_ROUNDS):
        payload = {"model": settings.LLM_MODEL, "messages": messages, "tools": _TOOLS,
                   "temperature": 0.2}
        resp = transport(payload)
        try:
            msg = resp["choices"][0]["message"]
        except (KeyError, IndexError, TypeError) as exc:
            raise AdvisorError("risposta del servizio LLM senza messaggio") from exc
        if not isinstance(msg, dict):
            raise AdvisorError("risposta del servizio LLM senza messaggio")
        calls = msg.get("tool_calls") or []
        if not isinstance(calls, list) or not all(isinstance(c, dict) for c in calls):
            raise AdvisorError("il modello ha restituito chiamate a strumenti non valide")
        if not calls:
            content = msg.get("content")
            final = _parse_final(content if isinstance(content, str) else "")
            break
        messages.append({"role": "assistant", "content": msg.get("content") or "",
                         "tool_calls": calls})
        for call in calls:
            fn = call.get("function")
            fn = fn if isinstance(fn, dict) else {}
            args = fn.get("arguments") or "{}"
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except ValueError:
                    args = {}
            if not isinstance(args, dict):
                args = {}
            out = (session.simulate(args) if fn.get("name") == "simula_scenario"
                   else {"errore": "strumento sconosciuto"})
            messages.append({"role": "tool", "tool_call_id": call.get("id", ""),
                             "content": json.dumps(out, ensure_ascii=False)})
    if final is None:
        raise AdvisorError("il modello non ha concluso l'analisi")

    known = {i["codice"]: i for i in base.get("interventi", [])}
    known.update(session.scenarios)
    recs = []
    raw_recs = final.get("raccomandazioni")
    for rec in (raw_recs if isinstance(raw_recs, list) else [])[:4]:
        if not isinstance(rec, dict):
            continue
        ref = str(rec.get("rif") or "")
        numbers = known.get(ref)
        if numbers is None:  # riferimento inventato: lo scartiamo
            continue
        recs.append({
            "rif": ref,
            "titolo": str(rec.get("titolo") or numbers["intervento"])[:160],
            "motivazione": str(rec.get("motivazione") or "")[:600],
            "priorita": len(recs) + 1,
            **{k: numbers.get(k) for k in (
                "classe", "riduzione_ep_pct", "risparmio_annuo_eur", "investimento_eur",
                "incentivo_eur", "investimento_netto_eur", "tempo_ritorno_anni",
                "tempo_ritorno_netto_anni", "flusso_cassa_cumulato")},
        })
    raw_warnings = final.get("avvertenze") or []
    if isinstance(raw_warnings, str):
        raw_warnings = [raw_warnings]
    elif not isinstance(raw_warnings, list):
        raw_warnings = []
    warnings = [str(w)[:300] for w in raw_warnings if w][:5]
    return {
        "modello": settings.LLM_MODEL,
        "classe_attuale": base["classe"],
        "costo_annuo_eur": base["costo_annuo_eur"],
        "sintesi": str(final.get("sintesi") or "")[:1200],
        "raccomandazioni": recs,
        "avvertenze": warnings,
        "nota": ("Analisi generata da un modello linguistico sui numeri del motore di stima: "
                 "valori indicativi, non sostituisce l'APE né un preventivo."),
    }

"""Fornitori di dati catastali a pagamento (accesso al Catasto senza SISTER).

Non esiste un'API pubblica gratuita del Catasto: l'accesso ufficiale per i
professionisti è SISTER (Agenzia delle Entrate) con credenziali personali, e
automatizzarlo con uno scraper non è consentito. Qui si passa da un fornitore
autorizzato che rivende i servizi catastali via API, attivato da
configurazione:

  CATASTO_PROVIDER=openapi
  CATASTO_OPENAPI_TOKEN=<token Bearer creato su console.openapi.com>
  CATASTO_OPENAPI_SANDBOX=true|false

Interfaccia comune (``CatastoProvider``): ``submit`` → id della richiesta,
``poll`` → stato, ``download`` → PDF. Tutti i fornitori lavorano in
asincrono (da secondi a qualche ora), quindi l'API salva la richiesta e
l'app la aggiorna con ``refresh``.

Openapi.it (API "Catasto", https://catasto.openapi.it, sandbox
https://test.catasto.openapi.it), prezzi di listino IVA esclusa a novembre
2026, più bassi con i loro abbonamenti:
  * POST /visura_catastale  visura per immobile (dati catastali)   1,90 €
  * POST /elaborato_planimetrico                                    6,90 €
  * POST /estratto_mappa                                            6,90 €
La planimetria catastale della singola unità NON è in questa API: è un
prodotto separato che richiede delega firmata e documento del proprietario.
"""
from __future__ import annotations

import base64
import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional, Tuple

from app.core.config import settings

# Tipi di richiesta supportati → tipo del documento salvato nel sopralluogo
KIND_TO_DOCUMENT = {
    "visura": "visura",
    "elaborato_planimetrico": "planimetria",
    "estratto_mappa": "mappa",
}


class ProviderError(Exception):
    """Errore del fornitore (rete, credito esaurito, dati catastali errati…)."""


@dataclass
class PollResult:
    status: str  # pending | done | failed
    error: Optional[str] = None


# (method, url, json_body|None, headers) -> (status_code, content_type, body)
HttpCall = Callable[[str, str, Optional[dict], Dict[str, str]], Tuple[int, str, bytes]]


def _urllib_call(method: str, url: str, body: Optional[dict], headers: Dict[str, str]) -> Tuple[int, str, bytes]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, resp.headers.get("Content-Type", ""), resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("Content-Type", "") if exc.headers else "", exc.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        raise ProviderError(f"Fornitore non raggiungibile: {exc}") from exc


class CatastoProvider:
    name = "base"
    prices: Dict[str, float] = {}

    def submit(self, kind: str, params: Dict[str, Any]) -> str:  # pragma: no cover
        raise NotImplementedError

    def poll(self, kind: str, request_id: str) -> PollResult:  # pragma: no cover
        raise NotImplementedError

    def download(self, kind: str, request_id: str) -> bytes:  # pragma: no cover
        raise NotImplementedError


class OpenapiCatasto(CatastoProvider):
    name = "openapi"
    # Prezzi di listino "base" (IVA esclusa), solo per mostrare il costo e
    # contare la spesa: il prezzo vero è quello del contratto col fornitore.
    prices = {"visura": 1.90, "elaborato_planimetrico": 6.90, "estratto_mappa": 6.90}
    _paths = {
        "visura": "/visura_catastale",
        "elaborato_planimetrico": "/elaborato_planimetrico",
        "estratto_mappa": "/estratto_mappa",
    }

    def __init__(self, token: str, sandbox: bool = True, http: Optional[HttpCall] = None):
        if not token:
            raise ProviderError("CATASTO_OPENAPI_TOKEN mancante")
        self.token = token
        self.base_url = "https://test.catasto.openapi.it" if sandbox else "https://catasto.openapi.it"
        self.http = http or _urllib_call

    # -- helpers ---------------------------------------------------------
    def _call(self, method: str, path: str, body: Optional[dict] = None) -> Tuple[str, bytes]:
        headers = {"Authorization": f"Bearer {self.token}", "Accept": "application/json, application/pdf"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        code, ctype, raw = self.http(method, self.base_url + path, body, headers)
        if code >= 400:
            raise ProviderError(self._error_message(code, raw))
        return ctype, raw

    @staticmethod
    def _error_message(code: int, raw: bytes) -> str:
        try:
            message = json.loads(raw.decode()).get("message")
        except Exception:  # noqa: BLE001
            message = None
        if code == 402:
            return "Credito del fornitore esaurito"
        if code in (401, 403):
            return "Token del fornitore non valido o senza permessi"
        return f"Errore del fornitore ({code})" + (f": {message}" if message else "")

    def _json(self, method: str, path: str, body: Optional[dict] = None) -> Dict[str, Any]:
        _, raw = self._call(method, path, body)
        try:
            payload = json.loads(raw.decode())
        except ValueError as exc:
            raise ProviderError("Risposta del fornitore non valida") from exc
        if payload.get("success") is False:
            raise ProviderError(payload.get("message") or "Richiesta rifiutata dal fornitore")
        data = payload.get("data")
        if not isinstance(data, dict):
            raise ProviderError("Risposta del fornitore senza dati")
        return data

    def _body(self, kind: str, p: Dict[str, Any]) -> Dict[str, Any]:
        body: Dict[str, Any] = {
            "provincia": p["provincia"],
            "comune": p["comune"],
            "foglio": p["foglio"],
            "particella": p["particella"],
        }
        if p.get("sezione"):
            body["sezione"] = p["sezione"]
        if kind == "visura":
            body.update(
                entita="immobile",
                tipo_catasto=p.get("tipo_catasto") or "F",
                tipo_visura="ordinaria",
                tipo_formato="pdf",
            )
            if p.get("sezione_urbana"):
                body["sezione_urbana"] = p["sezione_urbana"]
            if p.get("subalterno"):
                body["subalterno"] = p["subalterno"]
        elif kind == "elaborato_planimetrico" and p.get("sezione_urbana"):
            body["sezione_urbana"] = p["sezione_urbana"]
        return body

    # -- interfaccia -----------------------------------------------------
    def submit(self, kind: str, params: Dict[str, Any]) -> str:
        data = self._json("POST", self._paths[kind], self._body(kind, params))
        request_id = data.get("id")
        if not request_id:
            raise ProviderError("Il fornitore non ha restituito l'id della richiesta")
        return str(request_id)

    def poll(self, kind: str, request_id: str) -> PollResult:
        data = self._json("GET", f"{self._paths[kind]}/{request_id}")
        stato = (data.get("stato") or "").lower()
        esito = data.get("esito")
        if stato == "evasa":
            if esito in (None, "", "OK", "ok") or (isinstance(esito, dict) and esito.get("codice") in (None, 0, "OK")):
                return PollResult("done")
            return PollResult("failed", f"Esito del fornitore: {esito}")
        if stato in ("errore", "annullata", "rifiutata"):
            return PollResult("failed", f"Richiesta {stato}")
        return PollResult("pending")

    def download(self, kind: str, request_id: str) -> bytes:
        ctype, raw = self._call("GET", f"{self._paths[kind]}/{request_id}/documento")
        if raw.startswith(b"%PDF-"):
            return raw
        # Alcuni endpoint rispondono in JSON con il file in base64
        try:
            payload = json.loads(raw.decode())
            data = payload.get("data", payload)
            encoded = data if isinstance(data, str) else (data.get("file") or data.get("documento") or data.get("content"))
            pdf = base64.b64decode(encoded)
        except Exception as exc:  # noqa: BLE001
            raise ProviderError(f"Documento del fornitore in formato inatteso ({ctype})") from exc
        if not pdf.startswith(b"%PDF-"):
            raise ProviderError("Il documento del fornitore non è un PDF")
        return pdf


def get_provider() -> Optional[CatastoProvider]:
    """Il fornitore configurato, o None se l'accesso al Catasto è spento."""
    name = (settings.CATASTO_PROVIDER or "").strip().lower()
    if not name:
        return None
    if name == "openapi":
        return OpenapiCatasto(settings.CATASTO_OPENAPI_TOKEN, sandbox=settings.CATASTO_OPENAPI_SANDBOX)
    raise ProviderError(f"CATASTO_PROVIDER sconosciuto: {name}")

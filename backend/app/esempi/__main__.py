"""Carica le pratiche di esempio tramite l'API. Vedi ``app/esempi/__init__.py``."""
from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

from app.esempi import PRATICHE

HERE = Path(__file__).resolve().parent


class Api:
    def __init__(self, base: str):
        self.base = base.rstrip("/") + "/api/v1"
        self.token: str | None = None

    def call(self, method: str, path: str, body=None, ok=(200, 201)):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:  # noqa: S310
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as err:
            raw = err.read().decode(errors="replace")
            if err.code in ok:
                return err.code, None
            return err.code, raw


def login_or_register(api: Api, email: str, password: str, name: str) -> None:
    code, res = api.call("POST", "/auth/login", {"email": email, "password": password})
    if code == 200:
        api.token = res["access_token"]
        if not res.get("terms_accepted", True):
            api.call("POST", "/auth/accept-terms", {})
        print(f"Login come {email}")
        return
    code, res = api.call("POST", "/auth/register", {
        "email": email, "password": password, "name": name, "accept_terms": True,
    })
    if code != 201:
        sys.exit(f"Registrazione di {email} fallita ({code}): {res}")
    api.token = res["access_token"]
    print(f"Creato l'account {email}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Carica le pratiche di esempio di Pre-APE")
    p.add_argument("--base-url", default="http://127.0.0.1:7031",
                   help="indirizzo dell'app (default: dentro il container)")
    p.add_argument("--email", required=True, help="account su cui caricare gli esempi")
    p.add_argument("--password", required=True, help="password (min 8 caratteri)")
    p.add_argument("--name", default="Geometra Demo")
    args = p.parse_args(argv)

    api = Api(args.base_url)
    login_or_register(api, args.email.strip().lower(), args.password, args.name)

    code, existing = api.call("GET", "/surveys")
    if code != 200:
        sys.exit(f"Elenco sopralluoghi non disponibile ({code}): {existing}")
    titles = {s.get("title") for s in existing}

    for pratica in PRATICHE:
        body = {k: v for k, v in pratica.items() if k != "planimetria"}
        if body["title"] in titles:
            print(f"  già presente: {body['title']}")
            continue
        code, survey = api.call("POST", "/surveys", body)
        if code != 201:
            print(f"  ERRORE {code} su {body['title']}: {survey}")
            continue
        print(f"  creata: {body['title']}  →  classe {survey.get('estimated_class')}")

        if pratica.get("planimetria"):
            pdf = (HERE / pratica["planimetria"]).read_bytes()
            code, doc = api.call("POST", f"/surveys/{survey['id']}/documents", {
                "kind": "planimetria", "filename": pratica["planimetria"],
                "content_base64": base64.b64encode(pdf).decode(),
            })
            if code != 201:
                print(f"    planimetria non caricata ({code}): {doc}")
                continue
            code, cad = api.call("POST", f"/documents/{doc['id']}/cad", {})
            if code == 200:
                st = cad.get("stats") or {}
                print(f"    planimetria → CAD: {st.get('rooms')} vani, "
                      f"{st.get('gross_area_m2')} m² lordi, {st.get('doors')} porte, "
                      f"{st.get('windows')} finestre")
            else:
                print(f"    disegno CAD non generato ({code}): {cad}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

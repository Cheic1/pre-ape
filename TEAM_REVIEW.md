# TEAM_REVIEW.md — Revisione struttura con team di agenti

**Data**: 23/09/2026 · **Metodo**: 6 agenti specialisti, 2 round (analisi indipendente → confronto incrociato con cross-critique).
**Scope**: struttura backend, frontend, sicurezza, test/V-cycle, privacy, architettura globale.

## Il team

| Ruolo | Focus |
|---|---|
| Software Architect | struttura globale, debito strutturale, adapter futuri (OAuth/Drive/WhatsApp) |
| Backend Architect | FastAPI, schema, DB layer, test API |
| Frontend Architect/Dev | Flutter, state mgmt, layering, web-interop |
| Security Architect | confini di fiducia, authN/authZ, supply-chain |
| Test Automation Engineer | V-cycle, tracciabilità FR↔test, E2E |
| Privacy Engineer | GDPR, minimizzazione, retention, terze parti |

## Scoperte NUOVE emerse dalla revisione

1. **CORS non è mai montato su `main:app`** — `CORSMiddleware` è importato ma l'unico `add_middleware` è nella app **stale** `backend/app/__init__.py`. Conseguenza doppia: il frontend web non potrebbe parlare col backend, e `test_cors_headers` su `main:app` **fallisce** (verificato in round 2).
2. **La suite test backend è rossa/debole**: oltre al CORS, `test_get_survey_results_not_found` usa un id non-UUID e si aspetta 404 mentre il contratto dice 422; nessuna fixture/cleanup, dipendenza dall'ordine.
3. **`init_db()` crea un SECONDO engine** parallelo a quello di `database.py` (doppia connessione al stesso DB).
4. **IDOR sistematico**: CRUD survey senza auth né ownership (`user_id`): chiunque legga/modifichi i rilievi di tutti.
5. **Git history del repo pubblico**: credenziali default `DATABASE_URL` e qualsiasi secret passato restano nel history anche dopo delete → serve scan dell'intera history + rotazione, non solo pre-commit.
6. Nessuno aveva visto: **DR/backup assenti** (Postgres single-container), **performance bundle Flutter** (mai misurate, rischio 4G/low-end), **abuso quota Nominatim** (l'app rischia di diventare open-proxy di geocoding), **terzi extra-UE** (Nominatim/Ollama/Google) senza DPA né registro art. 30.

## Dispute risolte nel confronto incrociato

| # | Disputa | Esito |
|---|---------|-------|
| 1 | API client subito (Arch/FE) **vs** auth prima (Security) | **Auth prima**: un client costruito su endpoint aperti va riscritto. Ordine: auth → client. |
| 2 | Gate E2E 10-run subito (Test) **vs** troppo costoso (Arch) | **Compromesso**: smoke E2E 1 run in P1; gate `--repeat-each=10` in P2/P3 quando l'API smette di cambiare. |
| 3 | Coordinate a 3 decimali (Privacy) **vs** precisione piena (Backend) | **Fuso**: precisione piena nel DB con access-control; arrotondamento (~100 m) solo su log e chiamate a terzi (Nominatim). |
| 4 | SRI su CDN unpkg (Security) **vs** self-host Leaflet (FE) | **Self-host vince**: zero CDN terzi, CSP più stretta, offline-ready, un solo artefatto dalla build. |
| 5 | PhotoStore/Drive "così servirà" (FE) | **Respinto da Privacy**: senza finalità, minimizzazione e retention dichiarate è sovra-collezione → ridefinire prima di salvare foto. |
| 6 | Test "deboli" (BE) | **Inasprito da Test**: la diagnosi è peggiore — la suite è **rossa**, gate pre-merge = verde da zero. |

## Roadmap fuso (concordato dai 6 agenti)

### P1 — Prerequisito a tutto il resto
- **A1. Backend onesto**: montare `CORSMiddleware` in `main:app`; cancellare `backend/app/__init__.py` stale; JWT + filtro `user_id` su ogni endpoint (chiude l'IDOR); rate limit su login/upload.
- **A2. Suite test verde e deterministica**: fix CORS test, contratto UUID stretto (422 vs 404), fixture con cleanup, niente dipendenza dall'ordine + **`verify.sh`** locale pre-commit (`analyze → pytest → playwright`) come gate unico (Actions disabilitato a livello account).
- **A3. Contratto + API client**: `lib/models/survey.dart` + `lib/services/api_client.dart` (JWT injection) + `POST/GET /surveys` — il minimo per un SaaS dimostrabile. Contratto condiviso (OpenAPI/contract-test) per evitare drift.

### P2 — Prima del primo cliente
- **B1. DB deterministico**: snapshot Alembic iniziale, engine lazy (niente creazione a import-time), `requirements.txt` allineato a `pyproject.toml`, `init_db` riusa l'engine di `database.py`.
- **B2. Scomposizione `api/v1`**: `schemas.py`, `deps.py`, `routers/surveys.py`, `routers/photo_analyses.py` (prefisso invariato, zero breaking change).
- **B3. Foto end-to-end**: compressione client al tiro (prima del base64) + `POST /surveys/{id}/photos` multipart con validazione magic-bytes/limite dimensione/URL firmati a scadenza; PhotoStore con finalità+retention dichiarate (Drive rimandato a Cloud Console).
- **B4. Test**: unit `flutter test` su logica estratta (scoring, fallback geoloc, parsing Nominatim, report_builder) + **test di non-ritorno** sui fix recenti (indirizzo geocodificato, photo picker, export report) + suite E2E Playwright riproducibile (`playwright.config` con webServer, selettore primario `flt-semantics-host`, coordinate solo fallback, smoke 1 run) + test IDOR e test delete.
- **B5. Privacy operativa**: forward geocoding solo su conferma esplicita del campo, GPS su azione esplicita (non auto-trigger alla prima build), informativa a schermo "indirizzo inviato a OpenStreetMap", retention+deletion+DSAR con audit.

### P3 — Prima dell'esposizione internet/scala
- **C1.** OAuth Google backend-only con PKCE (secret solo in env/vault del server, redirect allineato a 7031) — **bloccato su Cloud Console dell'utente**.
- **C2.** HTTPS/HSTS (reverse proxy/Certbot), gitleaks sull'intera git history + rotazione credenziali, DPA + registro trattamenti art. 30, DPIA se servono profili GPS dei tecnici.
- **C3.** Self-host Leaflet (rimosso unpkg), accessibilità (`Semantics`/ARIA sugli step), misurazione performance bundle (CWV su 4G), backup/DR Postgres, wireare `ai_vision_service` dietro feature flag.

### Fuori roadmap (descope esplicita)
- Adapter anti-corruption per **WhatsApp bot**: tenere i confini puliti (niente logica canale nel core), ma non costruirlo ora.
- Gate E2E 10-run: solo dopo la stabilizzazione dell'API.

## Rischio architetturale residuo principale
**Contratto end-to-end inesistente**: oggi non esiste un solo percorso che raccolga un dato APE dal form al DB. Finché A3 non è completato, il prodotto non è vendibile indipendentemente da tutto il resto.

---
*Generato dal team di agenti (round 1 + round 2). Ogni bisogno è tracciabile in REQUIREMENTS.md come FR/NFR; aggiornare §sprint log a ogni implementazione.*

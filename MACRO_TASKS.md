# MACRO_TASKS.md — Backlog validato a ciclo V (23/09/2026)

Legenda stati: ⬜ da validare · 🟨 in corso (fase 2) · 🟩 fixato/verificato · ⛔ bloccato
Regole: ogni macro ha ≥5 subtask; validazione = onda review (fase 3, ≥10 agenti); ogni fix rientra in fase 2; chiusura = fase 4 con sprint log in `REQUIREMENTS.md`.

## M1 ⬜/🟨 Backend — FIX della review P1-A1 — *owner: backend-architect*
- [ ] CORS: aggiungere `https://preape.cheic2.it` a `CORS_ORIGINS` (default dev+prod), resta env-overridable (JSON); test preflight con origin prod + negativo stretto.
- [ ] Rate-limit key: dietro cloudflared `request.client.host` = 127.0.0.1 unico → usare `CF-Connecting-IP` **solo** se `client.host` è loopback (trusted proxy), altrimenti `client.host`; test: due IP logici → bucket separati, stesso IP → 429 al 11°.
- [ ] `SECRET_KEY`: fail-fast all'avvio se placeholder e `APP_ENV != development`; test con env esplicita.
- [ ] PBKDF2 600k: `asyncio.to_thread` per `verify`/`dummy_verify` (niente blocco event loop).
- [ ] Reintrodurre `backend/app/__init__.py` **vuoto** (package esplicito, niente app stale).
- [ ] `estimated_class`/`energy_score`: `extra="forbid"` negli input create/update (contratto self-describing, niente scarto silenzioso).

## M2 ⬜/🟨 Backend — suite completa + `verify.sh` — *owner: backend-architect (+test)*
- [ ] Token **scaduto** → 401; token **forgiato**/`alg:none`/alg-confusion → 401.
- [ ] Header senza scheme (`Token x`, `bearer` minuscolo) → 401; email malformata → 422; password errata → 401 uniforme.
- [ ] Reset rate-limit **assertato** (fuori finestra → 200), non solo nel fixture.
- [ ] `verify.sh` alla radice: flutter analyze (docker) + backend pytest (docker) + lane Playwright `|| true` finché non esiste `playwright.config`; exit code da gate.
- [ ] Determinismo: suite ×2 consecutive verdi (46 → ~52+ attesi), purge intatta, nessun test dipendente dall'ordine.
- [ ] Timeout suite ≥60s per iterazioni PBKDF2 (niente 401 al posto di 429 su host saturo).
- [ ] Header Authorization **assente** → 401 (non solo malformato). *(gap review test)*
- [ ] Token senza `sub`/`exp` o `exp` malformato → 401. *(gap review test)*
- [ ] Cross-alg (HS512) rifiutato con pin esplicito **HS256** in decode. *(gap review test)*

## M3 ⬜/🟨 Frontend — Spessore muri + cm + normativa — *owner: frontend-developer*
- [ ] `sublabel` **opzionale** in `_SelectorCard` (card telaio invariate, nessun overflow).
- [ ] Sublabel da `_WallOption`: `< 30 cm` / `30 – 40 cm` / `> 40 cm` sotto Sottile/Medio/Spesso.
- [ ] Caption/info: «Riferimento: D.Lgs. 192/2005, D.M. 26/06/2015 (UNI TS 11300)» + «lo spessore è un **proxy** della trasmittanza U, **non definisce la classe APE**»; **mai** DPR 59/2009.
- [ ] Report «Spessore muri»: label umana (`Medio — 30–40 cm`), non il valore grezzo `<30cm`.
- [ ] Score **invariato**: 27 test esistenti verdi + nuovo widget test sui sublabel esatti.
- [ ] A11y: semanticLabel distinti label/sublabel.

## M4 ⬜/🟨 Frontend — Foto aggiuntive — *owner: frontend-developer*
- [ ] `additionalPhotos: List<String>` in `SurveyData` + `addAdditionalPhoto`/`removeAdditionalPhoto(index)` (**indice stabile**) + cap 6 foto.
- [ ] Step 4: sezione «Altre foto» — tile «Aggiungi foto» riapre la stessa bottom sheet; thumbnail con ✕.
- [ ] Report: sezione «Foto aggiuntive» con N `<img src="data:image/...">` escapati.
- [ ] Zero invio API oggi (riserva `additional_photos` per M8); E2E: **zero** POST `/api/v1/**`.
- [ ] Test: provider add/remove/cap; report con 0/1/N foto; stato conservato back/forward.
- [ ] Griglia wrap, feedback rimozione, nessun overflow.

## M5 ⬜/🟨 Media — EXIF, compressione, cap — *owner: frontend-developer*
- [ ] Strip EXIF/geotag foto via re-encode canvas (**anche** le 4 foto slot).
- [ ] Downscale max 1600px lato lungo, JPEG q≈0.82.
- [ ] Validazione prefisso `data:image/*` prima di qualsiasi `src` nel report.
- [ ] Cap per foto (~500KB post-encode) + cap totale stato.
- [ ] Test: helper (size/prefisso dopo encode) + report rifiuta prefissi non-immagine.

## M6 ⬜ **NUOVO — Caricamento video** — *fase 1: design (ondata agenti)*
- [ ] Modello `additionalVideos`: ~~decisione embedded vs metadati-only~~ → **DECISO: metadati-only** (arch: report 27–46MB/OOM web; video-eng conferma) — cap **3 video, ≤15s, ≤20MB cad**; embed solo se team abbassa a 2/≤10s/≤8MB con `<video muted playsinline preload="metadata">`. *attesa voto privacy (EXIF/posizione nei video)*
- [ ] Picker unificato `accept="image/*,video/*"` nella stessa bottom sheet.
- [ ] Preview in app (`<video>`/icona, durata) + rimozione per indice.
- [ ] Report: strategia video (embed con cap rigoroso vs scheda metadati: filename, durata, data) — matematica dimensioni HTML obbligatoria nella decisione.
- [ ] Format/codec: compat browser (mp4/h264 vs webm), **nessun** transcoding pesante (ffmpeg.wasm fuori scope); accettazione per size/duration a monte.
- [ ] E2E/AC: filechooser video → tile → report + privacy (retenzione, metadati di posizione nei video).

## M7 ⬜ **NUOVO — Accesso con account Google** — *fase 1: design (ondata agenti)*
- [ ] OAuth 2.0 + **PKCE S256, backend-only** (secret mai nel client): `GET /auth/google/start` → redirect, `GET /auth/google/callback` → JWT emesso.
- [ ] `state` + `nonce` anti-CSRF/replay; verifica `id_token` (iss/aud/exp/nonce) con algoritmi pinati.
- [ ] Redirect URI `https://preape.cheic2.it/api/v1/auth/google/callback` → **dipende dal reverse proxy `/api/v1`** (M9); variante transitoria `localhost` documentata.
- [ ] Account linking: `google_sub` univoto; email verificata già presente con password → policy di link esplicita (auto-link vs errore).
- [ ] `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` solo env (gitleaks); ⛔ **bloccato**: progetto Google Cloud Console dell'utente → mock provider per i test.
- [ ] Frontend: bottone «Continua con Google» → navigazione al backend; ritorno con JWT (query/fragment vs cookie HttpOnly: decisione team).
- [ ] Privacy: minimizzazione (sub, email, nome), informativa, nessun altro dato Google conservato.

## M8 ⬜ API contract + client (P1-A3) — *owner: api-platform-engineer*
- [ ] Snapshot OpenAPI da `GET /openapi.json` → `docs/openapi.snapshot.json` (contract-first).
- [ ] `lib/models/survey.dart`: DTO wire (incl. `additional_photos` riservato) ≠ stato provider.
- [ ] `lib/services/api_client.dart`: `http` + JWT injection, register/login, POST/GET/PUT `/surveys`, error mapping (401/404/422).
- [ ] Dependenza `http` in `pubspec.yaml` (nota: prima dipendenza beyond riverpod/cupertino).
- [ ] Test client con `MockClient` (shape request/response del contratto).
- [ ] CORS/path esposti coerenti con il contratto (dipende da M1 + proxy M9).

## M9 ⬜ Deploy Docker (DEPLOY_PLAN fase 2)
- [ ] `backend/Dockerfile`: install da `pyproject.toml` (requirements incompleto).
- [ ] Stage Flutter → nginx static con `--base-href /pre-ape/`.
- [ ] `docker-compose.yml`: api + web + db (interno), `restart: unless-stopped`, healthcheck.
- [ ] Secret solo env/mount (AC-D3); immagini pinned, niente `:latest` (AC-D1).
- [ ] Reverse proxy `/api/v1` → `:7031` su `preape.cheic2.it` (servizio per M7 + M8).
- [ ] Reboot survival (AC-D4), sostituzione `:7032`/`:7031` raw, backup Postgres (AC-D2).

## M10 ⬜ E2E gate completo — *owner: test/evidence*
- [ ] Suite: load 0 errori, indirizzo+geocodifica (**regressione BUG-1**), funnel 1→4, foto slot, foto aggiuntive, video, report.
- [ ] Report content: indirizzo reale (**regressione BUG-2**), label umane muri, riferimenti normativi, immagini, disclaimer.
- [ ] Intercettazione `**/api/v1/**` → zero chiamate finché M8 non è wired.
- [ ] 1 run smoke per gate (P1) + lane **10 run consecutivi** senza flake (gate P2).
- [ ] Evidenze: screenshot `mNN_*.png` per step + `summary.json` con esiti.
- [ ] Wiring in `verify.sh` (M2).

## M11 ⬜ Sicurezza/privacy residui (P3 mappati)
- [ ] `gitleaks` su history + hook pre-commit.
- [ ] Revoca JWT: `jti` allowlist vs token opaco → decisione esplicita (nota review privacy).
- [ ] Pulizia survey orfane `user_id NULL` (11 righe) + retention esplicita.
- [ ] Informativa privacy/minima nel report e nell'app.
- [ ] Header sicurezza web (CSP, frame-ancestors, permissions-policy per GPS/fotocamera).

## M12 ⬜ Release 24h
- [ ] Regola ferrea: rebuild web + APK dopo ogni modifica grossa.
- [ ] `verify.sh` verde su tutta la pipeline (bypass Actions disabilitate a livello account).
- [ ] `release/2026-09-24` da `main` verde + changelog dallo sprint log.
- [ ] REQUIREMENTS sprint log aggiornato a ogni macro chiusa (fase 4).
- [ ] iOS: nota di build (macOS/CI) — non blocking per web+Android.

## M13 ⬜ **NUOVO — Nome del progetto (rilievo)** — *fase 1: design*
- [ ] Campo `projectName` (es. «Villa Rossi – Via Roma 5»): step 1 o header editabile, 3–80 char, trim, nessun HTML (escaping report).
- [ ] Default intelligente: da indirizzo comune o «Rilievo {data}»; rinominabile in qualsiasi momento.
- [ ] Uso: `<title>` e intestazione report, filename download (`PreAPE_{nome}_{data}.html`), lista dashboard (M14).
- [ ] Stato in `SurveyData` + riserva contratto `project_name` (M8) + futuro campo backend.
- [ ] Back-compat: report/lista senza nome → fallback indirizzo o data.
- [ ] Test: rename → titolo/filename aggiornati, escaping, default, validazione (lunghezza/caratteri).

## M14 ⬜ **NUOVO — Navigazione** — *fase 1: design*
- [ ] Wizard **non lineare**: indicatore 4 step cliccabile + validazione minima (warning se salti obbligatori) — stato preservato avanti/indietro (foto incluse).
- [ ] Pulsanti avanti/indietro coerenti su ogni step; indietro da step 1 → dashboard.
- [ ] **Dashboard/home**: lista progetti (M13) con ultimo aperto + «Nuovo rilievo»; entry point dell'app.
- [ ] Deep-link/router: rotte su `app_router` già esistente (`/step2`, `/report`), back del browser compatibile.
- [ ] «Apri in mappa» per coordinate+indirizzo via URL (`google.com/maps?q=…`) — nessuna dipendenza nuova sul web.
- [ ] A11y navigazione: focus order, keyboard, semantic label (vincoli da accessibility-auditor).
- [ ] Test: navigazione libera 1↔4 con stato intatto, deep-link, dashboard listing.

## M15 ⬜ **NUOVO — «Deve diventare un'app bellissima» (design/UI)** — *fase 1: design*
- [ ] Design system: scala tipografica Inter coerente, palette `AppColors` rivista (contrast AA 4.5:1), spaziatura `AppSpacing` uniforme.
- [ ] Micro-interazioni: transizioni step fluida, selezione card con feedback animato, gauge energia animata, skeleton/empty states.
- [ ] Coerenza componenti: card, bottoni, FAB/snackbar, header step — stessi pattern ovunque.
- [ ] Responsive: mobile-first 412px, uso dignitoso su desktop/tablet.
- [ ] Report HTML con lo stesso look (font, colori, tabella elegante) — l'output vendibile è parte della bellezza.
- [ ] Vincoli non negoziabili (accessibility-auditor): contrasto, touch target ≥48dp, reduced-motion.
- [ ] Evidenza: screenshot before/after per step nel gate E2E (M10).

## M16 ⬜ **NUOVO — UI auth (login/registrazione)** — *gap individuato da software-architect, fase 1*
- [ ] Schermata auth: login + registrazione email/password, validazione client, errori uniformi mappati da `ApiClient` (M8).
- [ ] Token JWT → stato condiviso (Riverpod) + reiniezione automatica in `ApiClient`; logout pulito.
- [ ] Guard delle route: rilievi/salvataggio autenticati **quando** il backend sarà wired — transizione offline-first preservata.
- [ ] Bottone «Continua con Google» (M7): placeholder disattivato finché il mock provider non è pronto.
- [ ] UX: loading/error state, submit da tastiera, a11y form (label/errore annunciate).
- [ ] Test: validazione form, fluxi register/login su `MockClient`, guard route.

## M17 ⬜ **NUOVO — Persistenza rilievi (locale)** — *gap individuato da software-architect, fase 1*
- [ ] Storage adapter web con **conditional import** (pattern già usato da `media_encoder`): IndexedDB; localStorage solo metadati — **mai** foto base64 in localStorage (quota 5MB).
- [ ] Salvataggio automatico stato `SurveyData` (incl. `projectName` M13) con id/versione schema + migrazione.
- [ ] Idratazione all'avvio + elenco rilievi per la dashboard M14 (ultimi N, «Nuovo rilievo»).
- [ ] Gestione quota exceeded (fallback metadati + warning) e cleanup rilievi eliminati.
- [ ] Degrade graceful senza storage (private mode) → stato in-memory.
- [ ] Test: round-trip, migrazione schema, quota, reload (E2E M10: refresh conserva il rilievo).

# DEPLOY_PLAN.md — Decisione team: Dockerizzare tutto? → **SÌ (6/6)**

**Data**: 23/09/26 · **Protocollo**: V_CYCLE_PROCESS.md fase 1, round unico 6 agenti · **Esito**: approvato all'unanimità con le fusi sotto.

## Topologia fusa (docker-compose unico)

```
                 Internet
                    │
              ┌─────▼─────┐
              │   Caddy    │  ← unico ingress 80/443, TLS automatico (Let's Encrypt)
              └─┬───────┬──┘
       /pre-ape/│       │/api/v1/
        ┌───────▼──┐ ┌──▼─────────┐        rete Docker interna (nessuna porta pubblica)
        │ web      │ │ api        │
        │ nginx    │ │ FastAPI    │
        │ statico  │ │ :7031      │──┐
        │ (multi-  │ │ (multi-    │  │  127.0.0.1 o solo rete interna
        │  stage)  │ │  stage)    │  │
        └──────────┘ └────────────┘  │
                          ┌──────────▼───┐
                          │ db (Postgres)│  volume persistente, porta 5433 NON esposta
                          └──────────────┘
```

- **web**: multi-stage — builder `ghcr.io/cirruslabs/flutter` (build `--release --base-href /pre-ape/`, Leaflet self-hosted) → nginx statico. `location /api/v1/ { proxy_pass api:7031; }` → **un'unica origine/porte in produzione → niente CORS in prod**.
- **api**: Dockerfile multi-stage (builder `pip install -e ".[dev]"`, runtime slim), `DATABASE_URL` da env del compose, `depends_on: condition: service_healthy` sul DB (mitiga l'engine a import-time), `USER non-root`, `HEALTHCHECK` su `/health`, `restart: unless-stopped`.
- **db**: Postgres con **volume dedicato**; rimuovere l'esposizione `0.0.0.0:5433` (mai esporre a Internet); credenziali da env/.env non committato.
- **Caddy**: ingress unico, TLS+Certbot, rollback possibile (se DNS/TLS in attesa → servire da porta interna).
- **Profilo `test`** (compose override): DB dedicato `pre_ape_test` porta separata → determinismo pytest; Playwright e `verify.sh` restano **host-side** (niente browser in container); trap `down --remove-orphans` + nomi progetto unici (mitiga il noto problema dei container `--rm` vivi).

## Cosa NON containerizzare (fuso tra gli agenti)
- Build Flutter locale (rimane il flusso Docker attuale) e `verify.sh`/Playwright (host).
- `.env`/secret (montati, mai dentro immagine o compose committato).
- Ollama/AI vision (non wired), reverse proxy di sistema già esistente.
- Su PaaS futuri: DB gestito (Supabase/Neon) al posto del container db.

## Impatto timeline "entro domani"
- Team: ~**mezza giornata** per Dockerfile+compose+healthcheck+test profile (Arch/FE/BE/Test concordi).
- Security stima 2-3 giorni solo se si vuole Caddy+DNS+certificati perfetti al lancio → **mitigazione**: launch con TLS best-effort + rollback, perfezionamento post-launch.
- Costi: **€0** server domestico; su PaaS si deployano solo `api`+`web` (Dockerfile 12-factor facili da ripiegare in buildpacks).

## Condizioni (accettazione della decisione)
- **AC-D1**: nessuna porta DB pubblica (`0.0.0.0:5433` rimossa dal compose/infra).
- **AC-D2**: volume persistente su Postgres + piano backup fuori dalla stessa macchina (⚠ Docker ≠ backup: privacy engine).
- **AC-D3**: secret solo via env/mount, mai nel compose committato; immagini pinned (niente `:latest`).
- **AC-D4**: stack up con `docker compose up -d` e sopravvive a reboot (`restart: unless-stopped`).
- **AC-D5**: se PaaS extra-UE (Vercel/Railway US) → DPA/SCC **prima** del deploy, non dopo (privacy engine).

## Ordine di esecuzione (allineato allo sprint)
1. Completano A1+A2 (backend) e B4a (frontend) già in corso → review fase 3.
2. Poi fase 2 qui: Dockerfiles + `docker-compose.yml` + Caddy + profilo test.
3. P1-A3 (API client) procede in parallelo sul contratto JWT/Survey.

## ✅ Esito fase 2 — Opzione A eseguita (23/09/26, 00:34 CEST)
Scelta utente (fase 1): **server domestico + tunnel cloudflared esistente "ctm"**.

| Componente | Valore |
|---|---|
| URL pubblico | **https://preape.cheic2.it/** → redirect → `/pre-ape/` (HTTPS abilita GPS+fotocamera) |
| Config tunnel | `~/.cloudflared/ctm.yml` (nuova; la vecchia `ctm-redirect.yml` aveva catch-all in posizione invalida → backup creato) |
| Ingress | `preape.cheic2.it` → `:7032` (web) · host esistenti invariati (`:3000`) · catch-all → `:5000` (comportamento attuale preservato) |
| DNS | CNAME `preape.cheic2.it` → tunnel `83db7f73…` (creato via `tunnel route dns`) |
| Processo | `cloudflared tunnel --config ~/.cloudflared/ctm.yml run ctm` (PID dal 23/09 00:34, log `ctm-run.log`, 4 connessioni registrate) |
| Verifica | `https://preape.cheic2.it/pre-ape/` → **200**, `<base href="/pre-ape/">` ✔ |

### TODO operativi emersi (da chiudere in P2/P3)
- **Persistenza reboot**: né `:7032` (python http.server) né il processo cloudflared sono servizi di sistema — servono unit systemd user (o `@reboot`) oppure il compose di `DEPLOY_PLAN` con `restart: unless-stopped` (AC-D4).
- API (`:7031`) **non** è ancora esposta via tunnel: servirà secondo hostname (es. `preapi.cheic2.it`) o proxy `/api/v1` (previsto dalla topologia) — da decidere in fase 1 con il team appena l'API client (P1-A3) richiede la chiamata cross-origin, insieme al CORS già in lavorazione in A1.

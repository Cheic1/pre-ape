# V_CYCLE_PROCESS.md — Protocollo decisionale del team (obbligatorio da ora in poi)

**Regola**: nessuna decisione o modifica "grossa" viene fatta senza passare dal team di 6 agenti
(vedi `TEAM_REVIEW.md`). Obiettivo sprint: **pubblicare il SaaS entro domani**.

## Pipeline (ciclo V corto)

Ogni decisione/modifica attraversa 4 fasi. Le fasi 1 e 3-4 sono **collettive** (tutti e 6 gli
agenti), la fase 2 è delegata.

| Fase | Chi | Output |
|------|-----|--------|
| **1. Decisione** | tutti e 6 (round parallelo): Software Architect propone il minimo diff + contratto; Backend/Frontend valutano fattibilità; Security e Privacy valutano impatto; Test Engineer definisce **come si verifica** (criteri di accettazione prima di scrivere codice) | piano approvato con criteri `AC-#` |
| **2. Implementazione** | 1 agente dedicato (Backend Architect o Frontend) | diff + `flutter analyze`/`pytest` locali verdi |
| **3. Review** | Security + Privacy + Test reviewano il diff contro i propri `AC-#`; il Software Architect verifica coerenza architetturale | approvazione o lista fix |
| **4. Verifica + tracciabilità** | Test Engineer esegue la verifica (unit/E2E/regression); REQUIREMENTS.md aggiornato (FR/NFR + sprint log); commit+push | evidenze versionate, `REQUIREMENTS.md` aggiornato |

### Regole di bootstrapping
- Gli item già fusi e approvati in `TEAM_REVIEW.md` (roadmap P1-P3) sono **pre-approvati**: passano
  direttamente da fase 2 (implementazione), con review fase 3 obbligatoria.
- Le decisioni **NUOVE** (cambi di scope, scelte di stack, deploy, pricing, dati personali) passano
  dalla fase 1 completa prima di toccare codice.
- Nessun commit senza: analisi verde, review superata, REQUIREMENTS.md aggiornato.

### Gate di uscita (release)
`verify.sh` locale = `flutter analyze` → `pytest tests/ -v` → `npx playwright test` (smoke) →
report. Tutto verde = release candidate. GitHub Actions resta la specifica eseguibile (ora
disabilitato a livello account).

## Sprint 24h — sequenza concordata

1. **P1-A1** Backend onesto: CORS su `main:app`, kill `app/__init__.py` stale, JWT + ownership `user_id` (anti-IDOR), rate limit. *(in esecuzione)*
2. **P1-A2** Suite test verde/deterministica + `verify.sh`. *(corre con A1)*
3. **P1-A3** Contratto API (OpenAPI minimo) → `lib/models/survey.dart` + `lib/services/api_client.dart` + `POST/GET /surveys`. *(dopo il contratto di A1)*
4. **P2-B*** item da `TEAM_REVIEW.md` in ordine, ove tempo.
5. **Deploy**: decide il team in fase 1 (opzioni: server domestico con reverse proxy + Certbot, oppure Vercel+Railway). **Richiede credenziali dell'utente** → sblocco dipende da lui.

## Stato continuo
- Ogni completion di agente apre la fase successiva automaticamente (nessuna attesa manuale).
- I problemi trovati in fase 3/4 rientrano in fase 1 solo se cambiano lo scope; altrimenti fix diretto + review.

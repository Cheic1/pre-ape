# Documenti catastali, pannello admin, scheda CENED — design

Data: 2026-10-18 · Branch: `feature/catasto-cened-admin`

## Obiettivo

1. Il tecnico allega al sopralluogo le carte del catasto (visura, planimetria,
   estratto di mappa); dalla visura PDF l'app propone i dati catastali, che il
   tecnico conferma.
2. L'amministratore (email in `ADMIN_EMAILS`) vede e gestisce utenti,
   sopralluoghi e documenti di tutti; ogni sua azione è registrata.
3. Il tecnico ottiene una "Scheda CENED": i dati del sopralluogo ordinati come
   le schermate di CENED+2.0 (Regione Lombardia), da ricopiare nel software.

## Decisioni e vincoli

- **Niente XML CENED per ora.** CENED+2.0 (`CenedImportXML.verificaValidita`)
  rifiuta i `calcolo.xml` senza hash/licenza del motore: serve l'accreditamento
  ARIA S.p.A. Non si falsifica l'hash. La scheda porta per ogni riga il nome del
  campo XSD di CENED (`cened_field`) come base per un futuro generatore.
- Gli XSD/binari CENED **non** entrano nel repo (licenza). Riferimento locale
  per lo sviluppo: `/tmp/cened_xsd/xml/datiCalcolo.xsd`, esempi reali
  `/tmp/cened_dl/tcs1/calcolo.xml`, `/tmp/cened_dl/tcs2/calcolo.xml`.
- I nomi degli intestatari della visura **non** vengono estratti né salvati
  dal parser (dati personali di terzi; CENED vuole solo il numero proprietari).
  Il PDF originale resta salvato così com'è.
- La stima resta "preliminare/indicativa": la scheda lo ripete in testa.
- UI in italiano.

## Basi già presenti (commit di fondazione)

- `app.models.database`: `SurveyDocument` (tabella `survey_documents`, FK
  `ON DELETE CASCADE` sul sopralluogo, `uploaded_by` FK `SET NULL`),
  `AdminAuditLog` (`admin_audit_log`, `admin_id` FK `SET NULL` +
  `admin_email` snapshot), `Survey.cadastral` (JSON) + migrazione additiva.
- `app.core.catasto.CadastralUnit` (extra="forbid", tutti i campi opzionali):
  `comune, codice_comune, provincia, sezione_urbana, foglio, particella,
  subalterno, categoria, classe, consistenza, superficie_mq, rendita_euro,
  indirizzo, piano`. `SurveyBase.cadastral: List[CadastralUnit]` (max 20).
- `settings.ADMIN_EMAILS` (CSV) → `settings.admin_emails`;
  `app.api.v1.is_admin(user)`; `TokenResponse.is_admin` (login/register).
- Router separati inclusi da `app/api/v1/__init__.py`:
  `documents.py`, `admin.py`, `cened.py` (ognuno `router = APIRouter()`,
  prefisso `/api/v1` ereditato). Importano `get_db`, `get_current_user`, ecc.
  da `app.api.v1` (import a fine modulo, niente ciclo).
- `documents.py` contiene già `DocumentMeta`, `UploaderInfo`,
  `document_meta(doc, uploader)`, `document_content_response(doc)`,
  `MAX_DOCUMENT_BYTES` (10 MB), `MAX_DOCUMENTS_PER_SURVEY` (10).

## 1. Documenti catastali (backend)

| Metodo | Path | Risposta |
|---|---|---|
| POST | `/surveys/{survey_id}/documents` | 201 `DocumentMeta` |
| GET | `/surveys/{survey_id}/documents` | 200 `[DocumentMeta]` (dal più vecchio) |
| GET | `/documents/{doc_id}/content` | 200 bytes, `Content-Type` = mime, attachment |
| DELETE | `/documents/{doc_id}` | 204 |

- Body POST (JSON, `extra="forbid"`): `{kind: "visura"|"planimetria"|"mappa"|"altro",
  filename: str 1..255, content_base64: str}`. Niente multipart (nessuna nuova
  dipendenza; 10 MB in base64 ≈ 13,4 MB < limite body 16 MB).
- Il tipo si ricava dai magic bytes, non dal nome: `%PDF-` → `application/pdf`,
  `FF D8 FF` → `image/jpeg`, `89 50 4E 47` → `image/png`; altro → 415.
  Base64 non valido → 422; oltre 10 MB decodificati → 413; oltre 10 documenti
  per sopralluogo → 409.
- Proprietà: sopralluogo/documento di un altro utente → 404 (come `/surveys`).
- `uploaded_by` = chiamante. Se `kind == "visura"` e PDF → `extracted` =
  risultato del parser (lista, anche vuota); altrimenti `null`. L'errore del
  parser non fa fallire l'upload (→ `[]` + log).
- La cancellazione del sopralluogo elimina i documenti (cascade).
- `conftest._purge_test_data` deve continuare a funzionare (cascade DB).

### Parser visura — `app/core/catasto/visura.py`

- `parse_visura_text(text: str) -> list[CadastralUnit]` (pura, testabile) e
  `parse_visura_pdf(data: bytes) -> list[CadastralUnit]` (estrae il testo con
  `pypdf`, nuova dipendenza runtime in `pyproject.toml` **e** `requirements.txt`).
- Layout di riferimento: visura per immobile / per soggetto dell'Agenzia delle
  Entrate (SISTER/servizi online): intestazione "Comune di X (Codice: F205)",
  "Provincia di X", righe "Unità immobiliare"/tabella con Sezione Urbana,
  Foglio, Particella, Sub, Zona Cens., Micro Zona, Categoria, Classe,
  Consistenza, Superficie Catastale ("Totale: 95 m²"), Rendita ("Euro 1.032,91"),
  "Indirizzo … Piano …". Più unità nella stessa visura → più elementi.
- Numeri italiani: `1.032,91` → 1032.91. Visure scansionate (nessun testo) → `[]`.
- Mai estrarre nomi/codici fiscali degli intestatari.
- Test: fixture testuali sintetiche fedeli al layout (≥3: unità singola,
  più unità, sezione urbana + campi mancanti) + un PDF generato nel test.

## 2. Pannello amministratore (backend)

`require_admin` = `get_current_user` + `is_admin` → 401 senza token, 403 se non
admin. Tutti sotto `/api/v1/admin`. **Ogni** chiamata scrive una riga in
`admin_audit_log` (`action`, `target_type`, `target_id`, `detail`) nella stessa
transazione dell'azione.

| Metodo | Path | Risposta | action |
|---|---|---|---|
| GET | `/admin/users` | `[AdminUser]` | `list_users` |
| GET | `/admin/users/{user_id}/surveys` | `[SurveySummary]` | `list_user_surveys` |
| GET | `/admin/surveys/{id}` | `SurveyResponse` | `view_survey` |
| PUT | `/admin/surveys/{id}` | `SurveyResponse` (body `SurveyUpdate`, ricalcola stima) | `update_survey` |
| DELETE | `/admin/surveys/{id}` | 204 | `delete_survey` |
| GET | `/admin/surveys/{id}/documents` | `[DocumentMeta]` | `list_documents` |
| GET | `/admin/documents/{id}/content` | bytes | `download_document` |
| DELETE | `/admin/documents/{id}` | 204 | `delete_document` |
| DELETE | `/admin/users/{id}?confirm_email=…` | 204 | `delete_user` |
| GET | `/admin/audit?limit=100&offset=0` | `[AuditEntry]` (più recenti prima) | — (non registrato) |

- `AdminUser`: `{id, email, name, created_at, last_login, survey_count,
  document_count, is_admin}`, ordinati per email.
- `delete_user`: `confirm_email` deve coincidere (case-insensitive) → altrimenti
  422; l'admin non può cancellare se stesso → 409. Cancella utente, sopralluoghi,
  photo_analyses, documenti. Le righe di audit restano (admin_id SET NULL non
  serve: il target è un altro utente).
- `AuditEntry`: `{id, admin_email, action, target_type, target_id, detail, created_at}`.
- Gli endpoint normali non cambiano: un admin su `/surveys` vede solo i propri.
- Riuso: `_apply_score`, `SurveySummary`, `SurveyResponse`, `SurveyUpdate` da
  `app.api.v1`; `document_meta`/`document_content_response` da `documents.py`.
- Test: 401/403, audit scritto per ogni azione, delete utente a cascata, 409 su
  se stesso, 422 su email errata, `is_admin` nel login. Gli admin di test si
  attivano con `monkeypatch.setattr(settings, "ADMIN_EMAILS", ...)`; il purge
  in `conftest.py` deve cancellare anche le righe di audit con
  `admin_email LIKE '%@example.test'`.

## 3. Scheda CENED (backend)

- `app/core/cened/sheet.py`: `build_cened_sheet(survey, documents) -> CenedSheet`
  pura (riceve il modello `Survey` e la lista di `DocumentMeta`), niente DB.
- `GET /api/v1/surveys/{survey_id}/cened-sheet` (proprietario; 404 altrimenti).
- Forma:
  ```json
  {"survey_id": "…", "generated_at": "…", "disclaimer": "…stima preliminare…",
   "sections": [{"key": "edificio", "title": "Edificio e localizzazione",
     "rows": [{"label": "Comune", "value": "Milano", "cened_field": "servizioDatiClimatici@codiceIstat",
               "status": "ok"}]}]}
  ```
  `status`: `ok` (dato rilevato), `stimato` (default del motore di stima,
  da `energy_result.assunzioni` o equivalente), `da_rilevare` (manca; `value` null).
- Sezioni (`key`): `edificio` (comune, provincia, zona climatica, GG, anno,
  tipologia, piani, superficie, altezza), `subalterni` (una serie di righe per
  `CadastralUnit`: foglio, particella, sub, categoria, sezione, comune
  catastale, indirizzo; più destinazione d'uso suggerita E.1(1) per categorie
  A/1–A/9, A/11), `strutture_opache` (muratura, spessore, isolamenti, copertura,
  pavimento), `serramenti` (telaio, vetro, superficie finestrata), `impianti`
  (generatore, combustibile, potenza, anno, impianto, terminali, regolazione,
  ACS, solare, raffrescamento, FV, VMC), `documenti` (elenco allegati con chi/quando).
- `cened_field`: nome elemento/attributo in `datiCalcolo.xsd` quando esiste una
  corrispondenza chiara (es. `subalterno@subalternoNumero`, catasto
  `@foglio/@particella/@provinciaCatastale/@comuneCatastale`); `null` se non c'è.
- Test: survey vuoto → tutto `da_rilevare` senza eccezioni; survey completo →
  valori/etichette attesi; endpoint 404 per altri utenti.

## 4. Frontend — catasto + scheda CENED

- `lib/models/survey.dart`: `CadastralUnit` (fromJson/toJson, solo chiavi del
  contratto), `cadastral` nel DTO; `DocumentMeta`; `CenedSheet`.
- `lib/services/api_client.dart`: `uploadDocument`, `listDocuments`,
  `downloadDocument` (bytes), `deleteDocument`, `getCenedSheet`.
- `SurveyNotifier`: stato `cadastral`, `loadFrom`/`toWire` (chiave `cadastral`).
- Step 1: sezione "Dati catastali": elenco unità modificabili (aggiungi/rimuovi),
  pulsante "Carica documento" con scelta tipo (visura, planimetria, estratto di
  mappa, altro) via `web_file_picker`; se il sopralluogo non ha ancora id lo
  salva prima. Dopo l'upload di una visura con `extracted` non vuoto: anteprima
  e "Applica dati della visura" (sostituisce le unità vuote / aggiunge le nuove).
  Elenco documenti con scarica/elimina.
- Step 6: card "Scheda CENED" (sezioni, righe `da_rilevare` evidenziate); il
  report HTML (`report_builder.dart`) include la scheda e i dati catastali.
- Test: modelli/round-trip, api client con `MockClient`, widget della sezione catasto.

## 5. Frontend — pannello admin

- `authProvider` salva `is_admin` dalla login (persistito come il token).
- `lib/services/admin_api.dart` (stessa gestione 401 di `ApiClient`, 403 →
  eccezione dedicata).
- `lib/features/admin/`: menu "Amministrazione" in `SurveyListPage` solo se
  admin → utenti (con conteggi) → sopralluoghi dell'utente → apri nel wizard in
  modalità admin (salvataggio via `PUT /admin/surveys/{id}`) / elimina;
  documenti (scarica/elimina con "caricato da" e data); "Registro accessi";
  "Elimina utente" con conferma digitando l'email.
- Test: visibilità menu solo admin, flusso elimina utente (conferma), admin API
  con `MockClient`.

## Verifica finale

`./verify.sh` (flutter analyze + test, backend pytest) verde; build Docker ok.

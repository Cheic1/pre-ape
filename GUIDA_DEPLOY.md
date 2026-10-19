# Guida: mettere online Pre-APE

Pre-APE è **un'unica immagine Docker** (`Dockerfile` alla radice) che contiene
l'app web Flutter **e** l'API FastAPI sullo stesso indirizzo. Le servono solo:

| Variabile | Cosa mettere |
|---|---|
| `DATABASE_URL` | stringa di connessione Postgres (`postgresql://utente:password@host/db`) |
| `SECRET_KEY` | stringa casuale lunga (firma dei login). Generala con `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `APP_ENV` | `production` |
| `ADMIN_EMAILS` | (facoltativa) email degli amministratori separate da virgola, es. `io@studio.it,socio@studio.it`. Vuota = nessun admin |

Senza `SECRET_KEY` valida l'app **si rifiuta di partire** (protezione voluta).

**Amministratore.** Chi ha l'email in `ADMIN_EMAILS` vede il pannello
"Amministrazione" (utenti, sopralluoghi e documenti di tutti, eliminazione
utenti). L'account va prima registrato normalmente nell'app; dopo aver
cambiato la variabile riavvia l'app (`docker compose up -d`, o redeploy su
Render) e rifai il login. Ogni azione dell'admin resta nel "Registro accessi".

---

## Opzione A — Gratis nel cloud: Render + Neon (consigliata per il pilota)

Costo: **0 €**. Limite: dopo 15 minuti senza visite il server "dorme" e la
prima apertura impiega ~30–60 secondi.

1. **Database (Neon)**
   1. Registrati su <https://neon.tech> (piano Free).
   2. Crea un progetto, regione **Europe (Frankfurt)**.
   3. Copia la *connection string* (inizia con `postgresql://…?sslmode=require`).
2. **App (Render)**
   1. Registrati su <https://render.com> con il tuo account GitHub.
   2. *New → Blueprint* → scegli il repository `Cheic1/pre-ape`.
      Render legge `render.yaml`: servizio web Docker, piano Free, Francoforte,
      `SECRET_KEY` generata automaticamente.
   3. Quando chiede `DATABASE_URL`, incolla la stringa di Neon.
   4. Attendi la build (~10 minuti la prima volta, compila Flutter).
   5. Apri l'URL `https://pre-ape-xxxx.onrender.com` → schermata di login.
3. **(Facoltativo) Tenerlo sveglio**: su <https://uptimerobot.com> (free) crea
   un monitor HTTP verso `https://…onrender.com/health` ogni 5 minuti.
4. **(Facoltativo) Dominio tuo**: su Render *Settings → Custom Domains* →
   `app.tuodominio.it`, poi aggiungi il CNAME indicato su Cloudflare.

Alternative equivalenti con la stessa immagine: **Fly.io**, **Google Cloud Run**
(quote gratuite), **Railway** (~5 $/mese, nessun piano gratis stabile). Per il
database: **Supabase** al posto di Neon.

> **Lovable** non serve qui: genera app nuove da zero (React + Supabase), non
> ospita un progetto Flutter + FastAPI esistente.

## Opzione B — Il tuo server di casa (Docker Compose)

```bash
cp .env.example .env        # poi compila SECRET_KEY e POSTGRES_PASSWORD
docker compose up -d --build
```

- App + API su `http://127.0.0.1:7032`; il database **non** è esposto.
- Sopravvive ai riavvii (`restart: unless-stopped`); dati nel volume `pgdata`.
- Per pubblicarla su `https://preape.cheic2.it`: nel pannello **CTM** aggiungi
  il servizio `preape` → porta `7032`, host `localhost` (CTM crea il Proxy Host
  in Nginx Proxy Manager, il tunnel `home` fa il resto).
- **Backup** (da fare!): `docker compose exec db pg_dump -U preape pre_ape > backup.sql`
  e copia il file fuori dal server.

## Privacy, termini d'uso e accordo sul trattamento dei dati

L'app mostra tre documenti (menu account → "Privacy e termini", e nella
registrazione): informativa privacy, termini d'uso e accordo sul trattamento
dei dati (DPA, art. 28 GDPR). I testi sono in `backend/app/legal/*.md`; i tuoi
dati si inseriscono come variabili d'ambiente (nel `.env` per il server di
casa, in "Environment" su Render):

| Variabile | Cosa scrivere |
|---|---|
| `LEGAL_TITOLARE_NOME` | nome e cognome o ragione sociale di chi gestisce il servizio |
| `LEGAL_TITOLARE_INDIRIZZO` | sede / indirizzo |
| `LEGAL_TITOLARE_PIVA_CF` | partita IVA e/o codice fiscale |
| `LEGAL_TITOLARE_EMAIL_PRIVACY` | email per le richieste privacy (controllala!) |
| `LEGAL_SERVER_UBICAZIONE` | dove sono i server, es. `Italia` (o il Paese UE del VPS) |
| `LEGAL_FORO_COMPETENTE` | città del tribunale competente, es. `Milano` |
| `LEGAL_DATA_EFFICACIA` | data da cui valgono i documenti, es. `19/10/2026` |

Poi `docker compose up -d` (ricrea il container con le nuove variabili). Finché
ne manca anche una sola, nei testi compare `[da completare: …]` e l'app mostra
il banner **"Bozza da far verificare a un legale"**.

- **Fai rileggere i testi a un legale prima di aprire il servizio al pubblico.**
- Se cambi i testi in modo sostanziale, aggiorna `LEGAL_VERSION` in
  `backend/app/legal/__init__.py`: al login successivo ogni utente dovrà
  accettare di nuovo (chi rifiuta viene disconnesso).
- Se cambi hosting (es. un VPS) o aggiungi fornitori, aggiorna l'elenco dei
  sub-responsabili nei documenti e avvisa gli utenti (il DPA prevede 15 giorni).

## Quando arrivano clienti paganti

| Voce | Servizio | Costo indicativo |
|---|---|---|
| App | Render Starter / Railway | ~7 €/mese |
| Database con backup | Neon Launch / Supabase Pro | ~20–25 €/mese |
| Pagamenti | Stripe (abbonamenti) | % sulle transazioni |

**GDPR**: foto e indirizzi delle case sono dati personali → regioni UE
(Francoforte), informativa privacy, DPA con i fornitori.

## Aggiornare l'app

- Render: ogni push su `main` ridistribuisce da solo.
- Server di casa: `git pull && docker compose up -d --build`.

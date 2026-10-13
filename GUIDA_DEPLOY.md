# Guida: mettere online Pre-APE

Pre-APE è **un'unica immagine Docker** (`Dockerfile` alla radice) che contiene
l'app web Flutter **e** l'API FastAPI sullo stesso indirizzo. Le servono solo:

| Variabile | Cosa mettere |
|---|---|
| `DATABASE_URL` | stringa di connessione Postgres (`postgresql://utente:password@host/db`) |
| `SECRET_KEY` | stringa casuale lunga (firma dei login). Generala con `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `APP_ENV` | `production` |

Senza `SECRET_KEY` valida l'app **si rifiuta di partire** (protezione voluta).

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

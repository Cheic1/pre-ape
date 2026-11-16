# Changelog

Formato ispirato a [Keep a Changelog](https://keepachangelog.com/it/1.1.0/), versioni [SemVer](https://semver.org/lang/it/).
La versione è la stessa per app (`frontend/pubspec.yaml`) e backend (`backend/pyproject.toml`); il tag git è `vX.Y.Z`.

## [Non rilasciato]

## [1.1.0] – 2026-11-16

Interventi con incentivi e rientro, consulente AI facoltativo, planimetria catastale → disegno CAD, e un giro di correzioni.

### Aggiunto
- Planimetria catastale → disegno CAD: dal documento «planimetria» caricato nel sopralluogo si ottiene un DXF in metri (pianta 2D a layer `PA_*` + pareti 3D) e un OBJ, con anteprima 2D/3D nell'app. Il DWG si ottiene salvando il DXF dal proprio CAD. Con un modello AI con visione configurato (`LLM_*` nel `.env`) vengono letti anche scala, altezza e nomi dei vani; senza, resta il riconoscimento automatico.
- Interventi migliorativi: per ogni intervento la stima mostra ora l'incentivo (detrazione 50% abitazione principale / 36% altre unità, in 10 anni; caldaie a sola fonte fossile escluse), il costo netto, il rientro con incentivo e il flusso di cassa cumulato su 15 anni. Nuovo campo facoltativo `abitazione_principale` nei dati edificio (se manca si assume abitazione principale e lo si dichiara). Valori indicativi, da verificare.
- «Analisi consulente» nello step Risultati: un agente LLM (OpenAI-compatibile, es. freellmapi; `LLM_BASE_URL`, `LLM_MODEL`, `LLM_API_KEY` nel `.env`) sceglie e spiega gli interventi più convenienti, provando anche combinazioni con il motore di stima. Costi, incentivi, risparmi e rientro vengono sempre dal motore. Senza configurazione la scheda non compare.

- Pratiche di esempio per le demo: `python -m app.esempi` carica su un account demo sei sopralluoghi di fantasia (dalla classe G alla A4, uno in bozza con la planimetria di prova e il disegno CAD).

### Corretto
- Export CENED: un carattere di controllo nell'indirizzo o nei dati catastali (capita incollando testo da un PDF, es. la visura) rendeva l'XML illeggibile per CENED. Ora quei caratteri vengono tolti.
- «Usa la mia posizione» su un sopralluogo già salvato non segnava la modifica come da salvare: uscendo non compariva l'avviso, e la scheda e lo .zip CENED partivano dai dati vecchi senza salvare prima.
- Una modifica fatta mentre il salvataggio era in corso risultava salvata anche se non lo era.
- Dopo un aggiornamento dell'app il browser poteva continuare a usare la versione vecchia: ora tutti i file dell'app vengono riverificati a ogni apertura.
- Il limite di 16 MB sulle richieste valeva solo se il client dichiarava la dimensione: un invio "a pezzi" (chunked) veniva letto tutto in memoria.
- La registrazione bloccava il server per il calcolo della password (come già corretto per il login).
- Le richieste `HEAD` (usate dai monitor di uptime) sulle pagine dell'app e su `/health` rispondevano 405.
- Pannello amministratore: aprendo il sopralluogo di un altro utente (es. un geometra), la scheda CENED e lo .zip CENED davano «non disponibile (404)». Ora arrivano da `/admin/surveys/{id}/cened-sheet` e `/admin/surveys/{id}/cened-xml`, con la riga nel registro accessi.

## [1.0.0] – 2026-11-04

Prima release ufficiale: Pre-APE è pronto per i primi geometri su preape.cheic2.it.
La stima resta una **valutazione preliminare**, non sostituisce l'APE.

### Sopralluogo
- Account con email e password, elenco dei propri sopralluoghi con ricerca, salvataggio sul server.
- Wizard in 6 passi: dati generali (indirizzo con ricerca su mappa o GPS), edificio, involucro, impianti, foto guidate (EXIF rimossi), risultati.
- Dati catastali dell'immobile e caricamento dei documenti (visura, planimetria): i PDF di visura vengono letti in automatico; i documenti sono cifrati sul server (AES-256-GCM).

### Stima energetica
- Motore lato server: bilancio stagionale semplificato UNI/TS 11300, dati climatici dei comuni, classi A4…G rispetto all'edificio di riferimento del DM 26/06/2015.
- Risultati con classe stimata, EPgl,nren, spesa e CO₂ annue, trasmittanze, dati ancora da rilevare e interventi migliorativi con classe raggiungibile.
- Report scaricabile in HTML, stampabile in PDF dal browser.

### CENED (Regione Lombardia)
- Scheda CENED: i dati del sopralluogo nell'ordine delle schermate di CENED+2.0.
- Export pronto da importare: uno `.zip` con l'XML nel formato 1.2 (*File → Importa file XML 1.2*, verificato col motore CENED) o 2.0.
- Via e numero civico in campi separati, anche partendo dall'indirizzo di OpenStreetMap o da quello della visura.

### Amministrazione e privacy
- Pannello amministratore: utenti, sopralluoghi e documenti di tutti, con registro degli accessi.
- Informativa privacy, termini d'uso e DPA (art. 28 GDPR) con accettazione obbligatoria alla registrazione.

### Correzioni dell'ultimo giro di prova
- Il report non mostra più le coordinate segnaposto di Roma quando la posizione non è stata scelta, e non le salva sul server.
- L'intervento «Riqualificazione completa» elenca le voci in italiano (non più codici come `pompa_calore`).

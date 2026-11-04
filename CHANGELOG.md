# Changelog

Formato ispirato a [Keep a Changelog](https://keepachangelog.com/it/1.1.0/), versioni [SemVer](https://semver.org/lang/it/).
La versione è la stessa per app (`frontend/pubspec.yaml`) e backend (`backend/pyproject.toml`); il tag git è `vX.Y.Z`.

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

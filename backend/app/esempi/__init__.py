"""Pratiche di esempio per la demo di Pre-APE.

Sei sopralluoghi realistici ma **inventati** (clienti, indirizzi e dati
catastali di fantasia, comuni lombardi veri per avere zona climatica e gradi
giorno corretti), pensati per mostrare a un geometra tutta la gamma di casi:
dal condominio anni '60 con caldaia vecchia (classe bassa) alla villetta nuova
con pompa di calore e fotovoltaico (classe alta), fino a una pratica in bozza
con dati ancora da rilevare e la planimetria catastale di prova allegata.

Uso (dal container dell'app sul server, o in locale con l'API avviata)::

    python -m app.esempi --email demo@preape.it --password 'UnaPasswordLunga!'

Lo script passa dall'API (stdlib, nessuna dipendenza): crea l'account demo se
non esiste (accettando termini e DPA) oppure fa login, poi crea le pratiche
il cui titolo non è già presente. Si può rilanciare senza duplicare nulla.
Le stime (classe, EPgl, interventi) le calcola il server come sempre.
"""
from __future__ import annotations

from typing import Any, Dict, List

PREFISSO = "ESEMPIO – "

PRATICHE: List[Dict[str, Any]] = [
    {
        "title": PREFISSO + "Appartamento anni '60, Milano",
        "client_name": "Mario Rossi (cliente di esempio)",
        "notes": "Compravendita. Condominio 1962, 3° piano di 6, caldaia autonoma "
                 "a metano del 1998, serramenti originali in legno a vetro singolo. "
                 "Caso tipico da classe bassa: utile per mostrare gli interventi.",
        "address": "Via Esempio 12, 20133 Milano MI",
        "latitude": 45.4781, "longitude": 9.2270,
        "square_meters": 78, "avg_height": 3.0,
        "status": "completed",
        "building": {
            "comune": "Milano", "provincia": "MI",
            "tipologia": "appartamento", "anno_costruzione": 1962,
            "piano": "intermedio", "numero_piani": 6, "lati_esposti": 2,
            "orientamento": "est_ovest", "abitazione_principale": True,
            "muratura": "mattoni_forati", "spessore_muri": "30-40cm",
            "isolamento_pareti_cm": 0,
            "telaio": "Legno", "vetro": "Singolo", "superficie_finestrata": 11,
            "generatore": "caldaia_tradizionale", "combustibile": "metano",
            "anno_generatore": 1998, "potenza_kw": 24,
            "impianto": "autonomo", "terminali": "radiatori",
            "regolazione": "termostato_ambiente", "acs": "combinata",
            "raffrescamento": "nessuno", "vmc": "nessuna",
        },
        "cadastral": [{
            "comune": "Milano", "codice_comune": "F205", "provincia": "MI",
            "foglio": "999", "particella": "123", "subalterno": "15",
            "categoria": "A/3", "classe": "3", "consistenza": "4,5 vani",
            "superficie_mq": 82, "rendita_euro": 720.46,
            "indirizzo": "Via Esempio 12", "piano": "3",
        }],
    },
    {
        "title": PREFISSO + "Villetta 1985, Seriate",
        "client_name": "Giulia Bianchi (cliente di esempio)",
        "notes": "Locazione. Villetta singola su due piani, caldaia a condensazione "
                 "sostituita nel 2016, serramenti in PVC doppio vetro del 2005, "
                 "sottotetto non isolato.",
        "address": "Via dei Tigli 8, 24068 Seriate BG",
        "latitude": 45.6853, "longitude": 9.7249,
        "square_meters": 145, "avg_height": 2.7,
        "status": "completed",
        "building": {
            "comune": "Seriate", "provincia": "BG",
            "tipologia": "villetta", "anno_costruzione": 1985,
            "piano": "unico", "numero_piani": 2, "lati_esposti": 4,
            "orientamento": "sud", "abitazione_principale": True,
            "muratura": "laterizio_alveolato", "spessore_muri": "30-40cm",
            "isolamento_pareti_cm": 0,
            "copertura": "sottotetto", "isolamento_copertura_cm": 0,
            "pavimento": "cantina", "isolamento_pavimento_cm": 0,
            "telaio": "PVC", "vetro": "Doppio", "superficie_finestrata": 22,
            "generatore": "caldaia_condensazione", "combustibile": "metano",
            "anno_generatore": 2016, "potenza_kw": 28,
            "impianto": "autonomo", "terminali": "radiatori",
            "regolazione": "valvole_termostatiche", "acs": "combinata",
            "raffrescamento": "split", "vmc": "nessuna",
        },
        "cadastral": [{
            "comune": "Seriate", "codice_comune": "I628", "provincia": "BG",
            "foglio": "12", "particella": "4567", "subalterno": "2",
            "categoria": "A/7", "classe": "2", "consistenza": "8 vani",
            "superficie_mq": 160, "rendita_euro": 1280.00,
            "indirizzo": "Via dei Tigli 8", "piano": "T-1",
        }],
    },
    {
        "title": PREFISSO + "Villetta nuova con pompa di calore, Monza",
        "client_name": "Luca e Sara Verdi (clienti di esempio)",
        "notes": "Prima vendita. Costruzione 2021 con cappotto, pompa di calore aria-acqua, "
                 "pannelli radianti, fotovoltaico 6 kWp e VMC con recupero. "
                 "Caso da classe alta.",
        "address": "Via delle Betulle 3, 20900 Monza MB",
        "latitude": 45.5950, "longitude": 9.2900,
        "square_meters": 130, "avg_height": 2.7,
        "status": "completed",
        "building": {
            "comune": "Monza", "provincia": "MB",
            "tipologia": "villetta", "anno_costruzione": 2021,
            "piano": "unico", "numero_piani": 2, "lati_esposti": 4,
            "orientamento": "sud", "abitazione_principale": True,
            "muratura": "laterizio_alveolato", "spessore_muri": ">40cm",
            "isolamento_pareti_cm": 14,
            "copertura": "falda_abitata", "isolamento_copertura_cm": 20,
            "pavimento": "terreno", "isolamento_pavimento_cm": 10,
            "telaio": "PVC", "vetro": "Triplo", "superficie_finestrata": 24,
            "generatore": "pompa_calore_aria_acqua", "anno_generatore": 2021,
            "potenza_kw": 8,
            "impianto": "autonomo", "terminali": "pavimento",
            "regolazione": "climatica_valvole", "acs": "pompa_calore_acs",
            "raffrescamento": "pompa_calore", "fotovoltaico_kwp": 6,
            "vmc": "recupero",
        },
        "cadastral": [{
            "comune": "Monza", "codice_comune": "F704", "provincia": "MB",
            "foglio": "45", "particella": "890", "subalterno": "1",
            "categoria": "A/7", "classe": "4", "consistenza": "7 vani",
            "superficie_mq": 142, "rendita_euro": 1410.00,
            "indirizzo": "Via delle Betulle 3", "piano": "T-1",
        }],
    },
    {
        "title": PREFISSO + "Casa in pietra in montagna, Bormio",
        "client_name": "Anna Neri (cliente di esempio)",
        "notes": "Successione. Casa in pietra del 1930 in zona F, sottotetto isolato "
                 "nel 2012, stufa a pellet come unico riscaldamento, boiler elettrico "
                 "per l'acqua calda, serramenti in legno doppio vetro.",
        "address": "Via Esempio Alta 21, 23032 Bormio SO",
        "latitude": 46.4672, "longitude": 10.3701,
        "square_meters": 110, "avg_height": 2.5,
        "status": "completed",
        "building": {
            "comune": "Bormio", "provincia": "SO",
            "tipologia": "villetta", "anno_costruzione": 1930,
            "piano": "unico", "numero_piani": 2, "lati_esposti": 4,
            "orientamento": "misto", "abitazione_principale": False,
            "muratura": "pietra", "spessore_muri": ">40cm",
            "isolamento_pareti_cm": 0,
            "copertura": "sottotetto", "isolamento_copertura_cm": 10,
            "pavimento": "terreno", "isolamento_pavimento_cm": 0,
            "telaio": "Legno", "vetro": "Doppio", "superficie_finestrata": 12,
            "generatore": "stufa_pellet", "anno_generatore": 2012,
            "potenza_kw": 12,
            "impianto": "autonomo", "terminali": "stufa",
            "regolazione": "nessuna", "acs": "boiler_elettrico",
            "raffrescamento": "nessuno", "vmc": "nessuna",
        },
        "cadastral": [{
            "comune": "Bormio", "codice_comune": "B049", "provincia": "SO",
            "foglio": "7", "particella": "210", "subalterno": "",
            "categoria": "A/4", "classe": "1", "consistenza": "6 vani",
            "superficie_mq": 118, "rendita_euro": 340.86,
            "indirizzo": "Via Esempio Alta 21", "piano": "T-1",
        }],
    },
    {
        "title": PREFISSO + "Condominio con teleriscaldamento, Brescia",
        "client_name": "Paolo Gialli (cliente di esempio)",
        "notes": "Locazione. Appartamento all'ultimo piano in condominio del 1975 "
                 "allacciato al teleriscaldamento cittadino, valvole termostatiche, "
                 "serramenti in alluminio senza taglio termico, terrazzo poco isolato.",
        "address": "Viale Esempio 40, 25128 Brescia BS",
        "latitude": 45.5530, "longitude": 10.2210,
        "square_meters": 92, "avg_height": 2.8,
        "status": "completed",
        "building": {
            "comune": "Brescia", "provincia": "BS",
            "tipologia": "appartamento", "anno_costruzione": 1975,
            "piano": "ultimo", "numero_piani": 6, "lati_esposti": 3,
            "orientamento": "sud", "abitazione_principale": False,
            "muratura": "mattoni_forati", "spessore_muri": "30-40cm",
            "isolamento_pareti_cm": 0,
            "copertura": "terrazzo", "isolamento_copertura_cm": 6,
            "telaio": "Alluminio", "vetro": "Doppio", "superficie_finestrata": 14,
            "generatore": "teleriscaldamento",
            "impianto": "centralizzato", "terminali": "radiatori",
            "regolazione": "valvole_termostatiche", "acs": "boiler_elettrico",
            "raffrescamento": "split", "vmc": "nessuna",
        },
        "cadastral": [{
            "comune": "Brescia", "codice_comune": "B157", "provincia": "BS",
            "foglio": "150", "particella": "77", "subalterno": "28",
            "categoria": "A/2", "classe": "4", "consistenza": "5 vani",
            "superficie_mq": 98, "rendita_euro": 865.00,
            "indirizzo": "Viale Esempio 40", "piano": "6",
        }],
    },
    {
        "title": PREFISSO + "Bifamiliare da completare, Pavia",
        "client_name": "Elena Blu (cliente di esempio)",
        "notes": "Pratica in bozza: sopralluogo da completare. Mancano anno e potenza "
                 "della caldaia e i dati della copertura: la stima li riporta tra i "
                 "dati da rilevare. Allegata la planimetria catastale di prova, "
                 "da cui si genera il disegno CAD (DXF/OBJ).",
        "address": "Via Esempio 5, 27100 Pavia PV",
        "latitude": 45.1921, "longitude": 9.1592,
        "square_meters": 96, "avg_height": 2.9,
        "status": "draft",
        "building": {
            "comune": "Pavia", "provincia": "PV",
            "tipologia": "bifamiliare", "anno_costruzione": 1955,
            "piano": "terra", "numero_piani": 2, "lati_esposti": 3,
            "abitazione_principale": True,
            "muratura": "mattoni_pieni",
            "telaio": "Legno", "vetro": "Doppio",
            "generatore": "caldaia_tradizionale", "combustibile": "metano",
        },
        "cadastral": [{
            "comune": "Pavia", "codice_comune": "G388", "provincia": "PV",
            "foglio": "20", "particella": "333", "subalterno": "1",
            "categoria": "A/3", "classe": "2", "consistenza": "5 vani",
            "indirizzo": "Via Esempio 5", "piano": "T",
        }],
        "planimetria": "planimetria-esempio.pdf",
    },
]

"""Parser della visura catastale (app.core.catasto.visura).

Le fixture riproducono il testo che pypdf estrae dalle visure dell'Agenzia
delle Entrate (SISTER / servizi online): dati sintetici, nessuna persona reale.
"""
from app.core.catasto import CadastralUnit
from app.core.catasto.visura import parse_visura_pdf, parse_visura_text

# Visura attuale per immobile: una sola unità, Milano.
VISURA_SINGOLA = """\
Direzione Provinciale di Milano
Ufficio Provinciale - Territorio
Servizi Catastali
Visura attuale per immobile
Situazione degli atti informatizzati al 15/09/2026
Data: 15/09/2026 - Ora: 10.12.33
Visura n.: T123456 Pag: 1
Dati della richiesta Comune di MILANO ( Codice: F205)
Provincia di MILANO
Catasto Fabbricati Foglio: 351 Particella: 125 Sub.: 12
INTESTATO
1 ROSSI Mario nato a MILANO il 01/01/1960 RSSMRA60A01F205X* (1) Proprieta' per 1/1
Unità immobiliare dal 09/11/2015
N. DATI IDENTIFICATIVI DATI DI CLASSAMENTO DATI DERIVANTI DA
Sezione Urbana Foglio Particella Sub Zona Cens. Micro Zona Categoria Classe Consistenza Superficie Catastale Rendita
1 351 125 12 1 A/2 3 5,5 vani Totale: 95 m² Totale escluse aree scoperte**: 92 m² Euro 1.032,91 VARIAZIONE del 09/11/2015 - Inserimento in visura dei dati di superficie.
Indirizzo VIA ROMA n. 10 Piano 2
Notifica Partita Mod.58 -
"""

# Visura per soggetto: più unità (abitazione + box) nello stesso comune.
VISURA_PIU_UNITA = """\
Visura per soggetto
Situazione degli atti informatizzati al 15/09/2026
Dati della richiesta Denominazione: BIANCHI LUCIA
Terreni e Fabbricati siti nel comune di BERGAMO ( Codice: A794) Provincia di BERGAMO
Soggetto individuato BIANCHI Lucia nata a BERGAMO il 02/02/1970 BNCLCU70B42A794Y
1. Unità Immobiliari site nel Comune di BERGAMO(Codice A794) - Catasto dei Fabbricati
N. DATI IDENTIFICATIVI DATI DI CLASSAMENTO ALTRE INFORMAZIONI
Sezione Urbana Foglio Particella Sub Zona Cens. Micro Zona Categoria Classe Consistenza Superficie Catastale Rendita
1 12 340 5 A/3 2 4 vani Totale: 70 m2 Euro 309,87
Indirizzo VIA XX SETTEMBRE n. 4 Piano T-1
2 12 340 18 C/6 4 15 m² Totale: 17 m² Euro 46,48
Indirizzo VIA XX SETTEMBRE n. 4 Piano S1
"""

# Sezione urbana presente, classe/superficie/indirizzo mancanti.
VISURA_SEZIONE = """\
Visura attuale per immobile
Comune di VENEZIA ( Codice: L736)
Provincia di VENEZIA
Catasto Fabbricati Sezione Urbana: VE Foglio: 14 Particella: 2120 Sub.: 3
Unità immobiliare
Sezione Urbana Foglio Particella Sub Zona Cens. Micro Zona Categoria Classe Consistenza Superficie Catastale Rendita
1 VE 14 2120 3 A/4 Euro 412,00
"""


def _only(units):
    assert len(units) == 1, units
    return units[0]


class TestParseVisuraText:
    def test_single_unit(self):
        unit = _only(parse_visura_text(VISURA_SINGOLA))
        assert isinstance(unit, CadastralUnit)
        assert unit.comune == "Milano"
        assert unit.codice_comune == "F205"
        assert unit.provincia == "MI"
        assert unit.sezione_urbana is None
        assert (unit.foglio, unit.particella, unit.subalterno) == ("351", "125", "12")
        assert unit.categoria == "A/2"
        assert unit.classe == "3"
        assert unit.consistenza == "5,5 vani"
        assert unit.superficie_mq == 95
        assert unit.rendita_euro == 1032.91
        assert unit.indirizzo == "VIA ROMA n. 10"
        assert unit.piano == "2"

    def test_multiple_units(self):
        units = parse_visura_text(VISURA_PIU_UNITA)
        assert len(units) == 2
        casa, box = units
        assert casa.comune == "Bergamo" and casa.codice_comune == "A794"
        assert casa.provincia == "BG"
        assert (casa.foglio, casa.particella, casa.subalterno) == ("12", "340", "5")
        assert casa.categoria == "A/3" and casa.classe == "2"
        assert casa.consistenza == "4 vani"
        assert casa.superficie_mq == 70
        assert casa.rendita_euro == 309.87
        assert casa.piano == "T-1"
        assert (box.foglio, box.particella, box.subalterno) == ("12", "340", "18")
        assert box.categoria == "C/6" and box.classe == "4"
        assert box.consistenza == "15 m²"
        assert box.superficie_mq == 17
        assert box.rendita_euro == 46.48
        assert box.indirizzo == "VIA XX SETTEMBRE n. 4"
        assert box.piano == "S1"

    def test_sezione_urbana_and_missing_fields(self):
        unit = _only(parse_visura_text(VISURA_SEZIONE))
        assert unit.comune == "Venezia" and unit.provincia == "VE"
        assert unit.sezione_urbana == "VE"
        assert (unit.foglio, unit.particella, unit.subalterno) == ("14", "2120", "3")
        assert unit.categoria == "A/4"
        assert unit.classe is None
        assert unit.consistenza is None
        assert unit.superficie_mq is None
        assert unit.indirizzo is None
        assert unit.rendita_euro == 412.0

    def test_labeled_identifiers_without_table(self):
        text = (
            "Comune di MILANO ( Codice: F205)\nProvincia di MILANO\n"
            "Catasto Fabbricati Foglio: 7 Particella: 88 Sub.: 2\n"
        )
        unit = _only(parse_visura_text(text))
        assert (unit.foglio, unit.particella, unit.subalterno) == ("7", "88", "2")
        assert unit.codice_comune == "F205"

    def test_never_extracts_owners(self):
        for text in (VISURA_SINGOLA, VISURA_PIU_UNITA):
            dumped = str([u.model_dump() for u in parse_visura_text(text)])
            for secret in ("ROSSI", "Mario", "BIANCHI", "Lucia", "RSSMRA", "BNCLCU"):
                assert secret.lower() not in dumped.lower()

    def test_empty_or_unrelated_text(self):
        assert parse_visura_text("") == []
        assert parse_visura_text("Fattura n. 12 del 2026\nTotale Euro 100,00") == []


def _visura_pdf(text: str) -> bytes:
    from fpdf import FPDF

    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", size=7)
    for line in text.splitlines():
        pdf.cell(0, 4, line, new_x="LMARGIN", new_y="NEXT")
    return bytes(pdf.output())


class TestParseVisuraPdf:
    def test_generated_pdf(self):
        units = parse_visura_pdf(_visura_pdf(VISURA_PIU_UNITA))
        assert len(units) == 2
        assert units[0].categoria == "A/3"
        assert units[1].rendita_euro == 46.48

    def test_pdf_without_text(self):
        from fpdf import FPDF

        pdf = FPDF()
        pdf.add_page()  # pagina vuota = visura scansionata senza OCR
        assert parse_visura_pdf(bytes(pdf.output())) == []

    def test_garbage_bytes(self):
        assert parse_visura_pdf(b"%PDF-1.4 not really a pdf") == []

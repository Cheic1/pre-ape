"""Scheda CENED: funzione pura build_cened_sheet + endpoint GET /surveys/{id}/cened-sheet."""
import uuid
from datetime import datetime

from app.api.v1.documents import DocumentMeta, UploaderInfo
from app.core import energy
from app.core.cened.sheet import build_cened_sheet
from app.core.energy import BuildingInputs
from app.models.database import SessionLocal, Survey, SurveyDocument
from conftest import create_survey

SECTION_KEYS = ["edificio", "subalterni", "strutture_opache", "serramenti", "impianti", "documenti"]

FULL_BUILDING = {
    "comune": "Milano",
    "provincia": "MI",
    "tipologia": "appartamento",
    "anno_costruzione": 1965,
    "piano": "intermedio",
    "numero_piani": 6,
    "lati_esposti": 2,
    "orientamento": "sud",
    "muratura": "mattoni_forati",
    "spessore_muri": "30-40cm",
    "isolamento_pareti_cm": 0,
    "copertura": "sottotetto",
    "isolamento_copertura_cm": 0,
    "pavimento": "cantina",
    "isolamento_pavimento_cm": 0,
    "telaio": "PVC",
    "vetro": "Doppio basso emissivo",
    "superficie_finestrata": 12.5,
    "generatore": "caldaia_condensazione",
    "combustibile": "metano",
    "anno_generatore": 2018,
    "potenza_kw": 24,
    "impianto": "autonomo",
    "terminali": "radiatori",
    "regolazione": "valvole_termostatiche",
    "acs": "combinata",
    "solare_termico": False,
    "raffrescamento": "split",
    "fotovoltaico_kwp": 3.5,
    "vmc": "nessuna",
}

UNIT_1 = {
    "comune": "Milano", "codice_comune": "F205", "provincia": "MI",
    "sezione_urbana": "A", "foglio": "123", "particella": "45", "subalterno": "7",
    "categoria": "A/2", "indirizzo": "Via Roma 1", "piano": "3",
}
UNIT_2 = {
    "comune": "Milano", "codice_comune": "F205", "provincia": "MI",
    "foglio": "123", "particella": "45", "subalterno": "12", "categoria": "C/6",
}


def _survey(**fields) -> Survey:
    survey = Survey(**fields)
    if fields.get("building") is not None or fields.get("square_meters"):
        survey.energy_result = energy.compute(
            BuildingInputs.model_validate(fields.get("building") or {}),
            square_meters=fields.get("square_meters"),
            avg_height=fields.get("avg_height"),
            address=fields.get("address"),
        )
    return survey


def _rows(sheet, key):
    return {row.label: row for row in next(s for s in sheet.sections if s.key == key).rows}


def _full_survey() -> Survey:
    return _survey(
        id=uuid.uuid4(),
        address="Via Roma 1, Milano",
        square_meters=95.0,
        avg_height=2.7,
        building=FULL_BUILDING,
        cadastral=[UNIT_1, UNIT_2],
    )


class TestEmptySurvey:
    def test_all_rows_da_rilevare(self):
        sheet = build_cened_sheet(Survey(), [])
        assert [s.key for s in sheet.sections] == SECTION_KEYS
        rows = [row for section in sheet.sections for row in section.rows]
        assert rows
        for row in rows:
            assert row.status == "da_rilevare", row
            assert row.value is None
        assert "preliminare" in sheet.disclaimer
        assert sheet.survey_id is None

    def test_garbage_json_does_not_raise(self):
        survey = Survey(building={"muratura": "paglia", "x": 1}, cadastral=[{"foglio": "1", "bogus": 2}, "x"],
                        energy_result={"assunzioni": "nope"})
        sheet = build_cened_sheet(survey, [])
        assert [s.key for s in sheet.sections] == SECTION_KEYS


class TestCompleteSurvey:
    def test_sections_and_titles(self):
        sheet = build_cened_sheet(_full_survey(), [])
        assert [s.key for s in sheet.sections] == SECTION_KEYS
        assert all(s.title for s in sheet.sections)

    def test_edificio(self):
        rows = _rows(build_cened_sheet(_full_survey(), []), "edificio")
        assert rows["Comune"].value == "Milano"
        assert rows["Comune"].status == "ok"
        assert rows["Comune"].cened_field == "servizioDatiClimatici@codiceIstat"
        assert rows["Provincia"].value == "MI"
        assert rows["Zona climatica"].value == "E"
        assert rows["Gradi giorno"].value == "2404"
        assert rows["Anno di costruzione"].value == "1965"
        assert rows["Anno di costruzione"].cened_field == "datiEdificio@annoCostruzione"
        assert rows["Tipologia edilizia"].value == "Appartamento"
        assert rows["Superficie utile"].value == "95 m²"
        assert rows["Superficie utile"].cened_field == "geometria@superficieUtile"
        assert rows["Altezza media netta"].value == "2,70 m"
        assert all(r.status == "ok" for r in rows.values()), rows

    def test_strutture_e_serramenti(self):
        sheet = build_cened_sheet(_full_survey(), [])
        opache = _rows(sheet, "strutture_opache")
        assert opache["Muratura"].value == "Mattoni forati"
        assert opache["Spessore muri"].value == "30–40 cm"
        assert opache["Isolamento pareti"].value == "Nessuno"
        assert opache["Copertura"].value == "Sottotetto non riscaldato"
        assert opache["Pavimento verso"].value == "Cantina / locale non riscaldato"
        serr = _rows(sheet, "serramenti")
        assert serr["Telaio"].value == "PVC"
        assert serr["Vetro"].value == "Doppio basso emissivo"
        assert serr["Superficie finestrata"].value == "12,5 m²"
        for row in list(opache.values()) + list(serr.values()):
            assert row.status == "ok", row

    def test_impianti(self):
        rows = _rows(build_cened_sheet(_full_survey(), []), "impianti")
        assert rows["Generatore"].value == "Caldaia a condensazione"
        assert rows["Generatore"].cened_field == "gruppoGeneratoriCombustione@tipoGeneratoreCombustione"
        assert rows["Combustibile"].value == "Metano"
        assert rows["Potenza nominale"].value == "24 kW"
        assert rows["Potenza nominale"].cened_field == "generatoreCombustione@phi_h_gn_out_n"
        assert rows["Anno installazione generatore"].value == "2018"
        assert rows["Tipo di impianto"].value == "Autonomo"
        assert rows["Terminali di emissione"].value == "Radiatori"
        assert rows["Regolazione"].value == "Valvole termostatiche"
        assert rows["Acqua calda sanitaria"].value == "Combinata col riscaldamento"
        assert rows["Solare termico"].value == "No"
        assert rows["Raffrescamento"].value == "Split"
        assert rows["Fotovoltaico"].value == "3,5 kWp"
        assert rows["Fotovoltaico"].cened_field == "fotovoltaico@w_fv_punto"
        assert rows["Ventilazione meccanica"].value == "Assente (ventilazione naturale)"
        assert all(r.status == "ok" for r in rows.values()), rows

    def test_heat_pump_fields(self):
        building = {**FULL_BUILDING, "generatore": "pompa_calore_aria_acqua", "combustibile": None}
        rows = _rows(build_cened_sheet(_survey(building=building, square_meters=80), []), "impianti")
        assert rows["Generatore"].cened_field == "gruppoPompeCalore@tipologiaGeneratore"
        assert rows["Potenza nominale"].cened_field == "pompaCalore@phi_h_gn_out_n"
        assert "Combustibile" not in rows


class TestSubalterni:
    def test_multiple_units(self):
        rows = _rows(build_cened_sheet(_full_survey(), []), "subalterni")
        assert rows["Unità 1 · Subalterno"].value == "7"
        assert rows["Unità 1 · Subalterno"].cened_field == "subalterno@subalternoNumero"
        assert rows["Unità 1 · Foglio"].value == "123"
        assert rows["Unità 1 · Foglio"].cened_field == "datiEdificio@foglio"
        assert rows["Unità 1 · Particella"].cened_field == "datiEdificio@particella"
        assert rows["Unità 1 · Sezione urbana"].value == "A"
        assert rows["Unità 1 · Comune catastale"].value == "Milano (F205)"
        assert rows["Unità 1 · Comune catastale"].cened_field == "datiEdificio@comuneCatastale"
        assert rows["Unità 1 · Provincia catastale"].cened_field == "datiEdificio@provinciaCatastale"
        assert rows["Unità 1 · Categoria catastale"].value == "A/2"
        assert rows["Unità 1 · Indirizzo"].value == "Via Roma 1"
        dest = rows["Unità 1 · Destinazione d'uso (suggerita)"]
        assert dest.value.startswith("E.1(1)")
        assert dest.status == "stimato"
        assert dest.cened_field == "zona@destinazioneUso"
        # second unit: garage C/6 -> no residential suggestion, missing section
        assert rows["Unità 2 · Subalterno"].value == "12"
        assert rows["Unità 2 · Sezione urbana"].status == "da_rilevare"
        assert rows["Unità 2 · Destinazione d'uso (suggerita)"].status == "da_rilevare"
        assert rows["Unità 2 · Destinazione d'uso (suggerita)"].value is None

    def test_a10_not_residential(self):
        survey = _survey(cadastral=[{**UNIT_1, "categoria": "A/10"}])
        rows = _rows(build_cened_sheet(survey, []), "subalterni")
        assert rows["Unità 1 · Destinazione d'uso (suggerita)"].status == "da_rilevare"

    def test_a11_residential(self):
        survey = _survey(cadastral=[{**UNIT_1, "categoria": "A11"}])
        rows = _rows(build_cened_sheet(survey, []), "subalterni")
        assert rows["Unità 1 · Destinazione d'uso (suggerita)"].value.startswith("E.1(1)")


class TestStimato:
    def test_engine_defaults_marked(self):
        # only surface + address: the engine fills the rest with defaults
        survey = _survey(square_meters=80.0, building={"comune": "Milano", "provincia": "MI"})
        sheet = build_cened_sheet(survey, [])
        edificio = _rows(sheet, "edificio")
        assert edificio["Anno di costruzione"].status == "stimato"
        assert edificio["Anno di costruzione"].value == "1970"
        assert edificio["Tipologia edilizia"].status == "stimato"
        assert edificio["Superficie utile"].status == "ok"
        assert edificio["Altezza media netta"].status == "stimato"
        assert edificio["Altezza media netta"].value == "2,70 m"
        assert edificio["Comune"].status == "ok"
        impianti = _rows(sheet, "impianti")
        assert impianti["Generatore"].status == "stimato"
        assert impianti["Generatore"].value == "Caldaia tradizionale"
        assert impianti["Combustibile"].status == "stimato"
        assert impianti["Potenza nominale"].status == "da_rilevare"
        serr = _rows(sheet, "serramenti")
        assert serr["Vetro"].status == "stimato"
        assert serr["Vetro"].value == "Singolo"
        assert serr["Superficie finestrata"].status == "stimato"
        assert serr["Superficie finestrata"].value == "10,0 m²"

    def test_legacy_columns_are_ok(self):
        survey = Survey(window_frame="Alluminio", window_glass="Doppio", wall_thickness=">40cm",
                        generator_type="Caldaia a Condensazione", generator_year=2010,
                        generator_power_kw=28.0)
        sheet = build_cened_sheet(survey, [])
        assert _rows(sheet, "serramenti")["Telaio"].value == "Alluminio"
        assert _rows(sheet, "strutture_opache")["Spessore muri"].value == "Oltre 40 cm"
        impianti = _rows(sheet, "impianti")
        assert impianti["Generatore"].value == "Caldaia a condensazione"
        assert impianti["Generatore"].status == "ok"
        assert impianti["Anno installazione generatore"].value == "2010"
        assert impianti["Potenza nominale"].value == "28 kW"


class TestDocumentiSection:
    def test_documents_listed(self):
        doc = DocumentMeta(
            id=uuid.uuid4(), survey_id=uuid.uuid4(), kind="visura", filename="visura.pdf",
            mime_type="application/pdf", size_bytes=2048,
            uploaded_by=UploaderInfo(id=uuid.uuid4(), email="m@example.test", name="Mario Rossi"),
            created_at=datetime(2026, 10, 18, 9, 30),
        )
        rows = next(s for s in build_cened_sheet(Survey(), [doc]).sections if s.key == "documenti").rows
        assert len(rows) == 1
        assert rows[0].label == "Visura catastale"
        assert rows[0].status == "ok"
        assert "visura.pdf" in rows[0].value
        assert "Mario Rossi" in rows[0].value
        assert "18/10/2026" in rows[0].value


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------
def _url(survey_id: str) -> str:
    return f"/api/v1/surveys/{survey_id}/cened-sheet"


class TestEndpoint:
    def test_owner_gets_sheet(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers, square_meters=90, building=FULL_BUILDING,
                                  cadastral=[UNIT_1])
        response = client.get(_url(survey_id), headers=headers)
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["survey_id"] == survey_id
        assert "generated_at" in body and "preliminare" in body["disclaimer"]
        assert [s["key"] for s in body["sections"]] == SECTION_KEYS
        sub = next(s for s in body["sections"] if s["key"] == "subalterni")
        assert {"label": "Unità 1 · Subalterno", "value": "7",
                "cened_field": "subalterno@subalternoNumero", "status": "ok"} in sub["rows"]

    def test_other_user_404(self, client, auth_a, auth_b):
        headers_a, _ = auth_a
        headers_b, _ = auth_b
        survey_id = create_survey(client, headers_a)
        assert client.get(_url(survey_id), headers=headers_b).status_code == 404
        assert client.get(_url(str(uuid.uuid4())), headers=headers_a).status_code == 404

    def test_requires_auth(self, client, auth_a):
        headers, _ = auth_a
        survey_id = create_survey(client, headers)
        assert client.get(_url(survey_id)).status_code == 401

    def test_documents_listed(self, client, auth_a):
        headers, user_id = auth_a
        survey_id = create_survey(client, headers)
        with SessionLocal() as db:
            db.add(SurveyDocument(
                survey_id=uuid.UUID(survey_id), uploaded_by=uuid.UUID(user_id), kind="planimetria",
                filename="planimetria.png", mime_type="image/png", size_bytes=4,
                content=b"\x89PNG",
            ))
            db.commit()
        body = client.get(_url(survey_id), headers=headers).json()
        docs = next(s for s in body["sections"] if s["key"] == "documenti")["rows"]
        assert len(docs) == 1
        assert docs[0]["label"] == "Planimetria"
        assert "planimetria.png" in docs[0]["value"]
        assert "Test user_a" in docs[0]["value"]
        assert "content" not in str(body)

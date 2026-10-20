"""Export XML per CENED+2.0: build_calcolo_xml_20 / build_cened_xml_12 + endpoint.

La validazione usa gli schemi ufficiali CENED, che non stanno nel repo (licenza):
``CENED_XSD_DIR`` (default ``/tmp/cened_xsd/xml``, con ``calcolo.xsd``…) e
``CENED_DTD`` (default ``/tmp/cened12/cened_Versione-1-0-5.dtd`` o lo zip
``/tmp/cened12/v12.zip`` pubblicato su cened.it). Se mancano, quei test vengono
saltati e la CI resta verde.
"""
import io
import os
import re
import uuid
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

import pytest

from app.core import energy
from app.core.cened.xml_export import (
    NS_CALCOLO,
    NS_DATI,
    build_calcolo_xml_20,
    build_cened_xml_12,
)
from app.core.energy import BuildingInputs
from app.models.database import Survey
from conftest import create_survey

XSD_DIR = Path(os.environ.get("CENED_XSD_DIR", "/tmp/cened_xsd/xml"))
DTD_PATH = Path(os.environ.get("CENED_DTD", "/tmp/cened12/cened_Versione-1-0-5.dtd"))
DTD_ZIP = DTD_PATH.parent / "v12.zip"

C = f"{{{NS_CALCOLO}}}"
D = f"{{{NS_DATI}}}"

FULL_BUILDING = {
    "comune": "Milano", "provincia": "MI", "tipologia": "appartamento",
    "anno_costruzione": 1965, "piano": "intermedio", "numero_piani": 6,
    "muratura": "mattoni_forati", "spessore_muri": "30-40cm", "telaio": "PVC",
    "vetro": "Doppio", "superficie_finestrata": 12.5,
    "generatore": "caldaia_tradizionale", "combustibile": "metano",
    "anno_generatore": 2010, "potenza_kw": 24, "impianto": "autonomo",
    "terminali": "radiatori", "regolazione": "valvole_termostatiche", "acs": "combinata",
    "raffrescamento": "split", "fotovoltaico_kwp": 3.5, "vmc": "nessuna",
}
UNIT_FLAT = {"comune": "Milano", "codice_comune": "F205", "provincia": "MI", "sezione_urbana": "A",
             "foglio": "123", "particella": "45", "subalterno": "7", "categoria": "A/2",
             "indirizzo": "Via Roma 1", "piano": "3"}
UNIT_GARAGE = {"comune": "Milano", "provincia": "MI", "foglio": "123", "particella": "45",
               "subalterno": "12", "categoria": "C/6"}


def _survey(**fields) -> Survey:
    survey = Survey(id=uuid.uuid4(), **fields)
    survey.energy_result = energy.compute(
        BuildingInputs.model_validate(fields.get("building") or {}),
        square_meters=fields.get("square_meters"), avg_height=fields.get("avg_height"),
        address=fields.get("address"))
    return survey


def _full_survey(**overrides) -> Survey:
    building = {**FULL_BUILDING, **overrides.pop("building", {})}
    return _survey(address="Via Roma 1, Milano", square_meters=95.0, avg_height=2.7,
                   building=building, cadastral=[UNIT_FLAT, UNIT_GARAGE], **overrides)


def _empty_survey() -> Survey:
    return Survey(id=uuid.uuid4())


def _parse(content: bytes) -> ET.Element:
    assert content.startswith(b'<?xml version="1.0" encoding="UTF-8"?>')
    return ET.fromstring(content)


def _comment(content: bytes) -> str:
    match = re.search(rb"<!--(.*?)-->", content, re.S)
    assert match, "manca il commento iniziale"
    return match.group(1).decode("utf-8")


# ---------------------------------------------------------------------------
# Schemi ufficiali (fuori dal repo)
# ---------------------------------------------------------------------------
@pytest.fixture(scope="module")
def xsd():
    etree = pytest.importorskip("lxml.etree")
    if not (XSD_DIR / "calcolo.xsd").is_file():
        pytest.skip(f"calcolo.xsd CENED non disponibile in {XSD_DIR}")
    return etree.XMLSchema(etree.parse(str(XSD_DIR / "calcolo.xsd")))


def _dtd_text() -> str:
    if DTD_PATH.is_file():
        return DTD_PATH.read_text(encoding="utf-8")
    if DTD_ZIP.is_file():
        with zipfile.ZipFile(DTD_ZIP) as archive:
            name = next(n for n in archive.namelist() if n.endswith(".dtd"))
            return archive.read(name).decode("utf-8")
    pytest.skip(f"DTD CENED 1.2 non disponibile ({DTD_PATH})")


@pytest.fixture(scope="module")
def dtd():
    """DTD 1.0.5 della Regione. Alcuni modelli sono ``(A) | (B)`` con A e B
    permutazioni con prefisso comune: non deterministici per XML 1.0, libxml2
    li rifiuta. Si valida contro la prima alternativa (quella che il generatore
    segue)."""
    etree = pytest.importorskip("lxml.etree")
    text = _dtd_text()
    fixed = re.sub(r"<!ELEMENT (\w+) \((\([^()]*\))\s*\|\s*\([^()]*\)\)>",
                   lambda m: f"<!ELEMENT {m.group(1)} ({m.group(2)})>", text)
    return etree.DTD(io.StringIO(fixed))


def _assert_valid(validator, content: bytes):
    from lxml import etree

    doc = etree.fromstring(content)
    ok = validator.validate(doc)
    errors = [f"{e.line}: {e.message}" for e in validator.error_log]
    assert ok, "\n".join(errors)


# ---------------------------------------------------------------------------
# Formato 2.0
# ---------------------------------------------------------------------------
class TestCalcolo20:
    def test_empty_survey_well_formed(self):
        xml = build_calcolo_xml_20(_empty_survey())
        root = _parse(xml.content)
        assert root.tag == f"{C}calcolo"
        cert = root.find(f"{C}datiInput/{D}certificazione")
        assert cert is not None
        assert cert.find(f"{D}dizionario/{D}servizioDatiClimatici/{D}input").get("codiceIstat") == "ND"
        edificio = cert.find(f"{D}datiEdificio")
        assert edificio.get("foglio") == "ND" and edificio.get("particella") == "ND"
        assert len(edificio.findall(f"{D}subalterni/{D}subalterno")) == 1
        # nessun impianto inventato senza generatore rilevato
        assert edificio.find(f"{D}impianti") is None
        assert any("Superficie utile" in d for d in xml.defaults)
        assert any("Generatore" in m for m in xml.missing)

    def test_no_engine_or_licence_elements(self):
        content = build_calcolo_xml_20(_full_survey()).content
        root = _parse(content)
        assert [child.tag for child in root] == [f"{C}datiInput"]
        names = {el.tag.split("}")[-1] for el in root.iter()}
        assert not names & {"hash", "hashImport", "licenza", "valoriIntermedi", "datiOutput"}
        software = root.find(f"{C}datiInput/{D}certificazione/{D}software")
        assert software.get("nomeSoftware") == "Pre-APE"
        assert software.get("versioneMotore") is None
        assert not content.rstrip().endswith(b"-->")  # nessuna firma in coda

    def test_header_comment(self):
        xml = build_calcolo_xml_20(_full_survey())
        comment = _comment(xml.content)
        assert "stima preliminare" in comment
        assert "non e' un APE" in comment
        for item in xml.defaults + xml.missing:
            assert item.replace("--", "- -") in comment

    def test_full_survey_content(self):
        xml = build_calcolo_xml_20(_full_survey())
        cert = _parse(xml.content).find(f"{C}datiInput/{D}certificazione")
        assert cert.find(f"{D}dizionario/{D}servizioDatiClimatici/{D}input").get("codiceIstat") == "015146"
        edificio = cert.find(f"{D}datiEdificio")
        assert edificio.get("comune") == "015146" and edificio.get("provincia") == "015"
        assert edificio.get("comuneCatastale") == "015146"
        assert (edificio.get("foglio"), edificio.get("particella")) == ("123", "45")
        assert edificio.get("sezioneUrbana") == "A"
        assert edificio.get("annoCostruzione") == "1965"
        assert edificio.get("numeroPiani") == "6"
        subs = edificio.findall(f"{D}subalterni/{D}subalterno")
        assert [s.get("subalternoNumero") for s in subs] == ["7"]  # C/6 non climatizzato
        assert any("sub. 12" in m for m in xml.missing)
        zona = subs[0].find(f"{D}zone/{D}zona")
        assert zona.get("destinazioneUso") == "2" and zona.get("rafAttivo") == "true"
        geo = zona.find(f"{D}geometria")
        assert geo.get("superficieUtile") == "95.0" and geo.get("altezzaMediaNetta") == "2.7"
        assert geo.get("volumeNetto") == "256.5"
        term = zona.find(f"{D}sistemaRisc/{D}tipoTerminale")
        assert term.get("tipoTerminale") == "1" and term.get("tipoRegolazione") == "4"
        gruppo = edificio.find(f"{D}impianti/{D}centraliTermiche/{D}centraleTermica/"
                               f"{D}generatori/{D}gruppoGeneratoriCombustione")
        assert gruppo.get("tipoVettoreEnergetico") == "1"
        gen = gruppo.find(f"{D}generatoreCombustione")
        assert gen.get("phi_h_gn_out_n") == "24.0" and gen.get("annoInstallazioneImpianto") == "2010"
        assert any("Fotovoltaico" in m for m in xml.missing)

    def test_uncertain_generator_not_written(self):
        xml = build_calcolo_xml_20(_full_survey(building={"generatore": "pompa_calore_aria_acqua"}))
        root = _parse(xml.content)
        assert root.find(f".//{D}impianti") is None
        assert any("pompa calore aria acqua" in m for m in xml.missing)

    def test_multiple_heated_units_split_area(self):
        unit2 = {**UNIT_FLAT, "subalterno": "8", "superficie_mq": 40}
        xml = build_calcolo_xml_20(_survey(square_meters=100.0, building=FULL_BUILDING,
                                           cadastral=[UNIT_FLAT, unit2]))
        subs = _parse(xml.content).findall(f".//{D}subalterno")
        areas = [s.find(f"{D}zone/{D}zona/{D}geometria").get("superficieUtile") for s in subs]
        assert areas == ["50.0", "40.0"]
        assert any("ripartita" in d for d in xml.defaults)

    @pytest.mark.parametrize("make", [_empty_survey, _full_survey])
    def test_valid_against_xsd(self, xsd, make):
        _assert_valid(xsd, build_calcolo_xml_20(make()).content)

    @pytest.mark.parametrize("generatore", ["caldaia_condensazione", "teleriscaldamento",
                                            "stufa_pellet", "radiatori_elettrici"])
    def test_valid_against_xsd_other_generators(self, xsd, generatore):
        survey = _full_survey(building={"generatore": generatore, "terminali": "pavimento",
                                        "regolazione": "nessuna", "acs": "boiler_elettrico"})
        _assert_valid(xsd, build_calcolo_xml_20(survey).content)


# ---------------------------------------------------------------------------
# Formato 1.2
# ---------------------------------------------------------------------------
class TestCened12:
    def test_empty_survey_well_formed(self):
        xml = build_cened_xml_12(_empty_survey())
        root = _parse(xml.content)
        assert root.tag == "dati"
        assert b"<!DOCTYPE" not in xml.content  # il convertitore CENED non risolve DTD esterni
        assert root.findtext("anno_di_costruzione") == "1970"
        assert any("Anno di costruzione" in d for d in xml.defaults)
        assert root.find("ace/centrali_termiche/dati_centrale_termica/generatori/"
                         "generatore_tradizionale") is not None

    def test_full_survey_content(self):
        xml = build_cened_xml_12(_full_survey())
        root = _parse(xml.content)
        assert root.findtext("codice_istat") == "015146"
        assert root.findtext("provincia") == "MI"
        assert root.findtext("comune") == "Milano"
        assert (root.findtext("foglio"), root.findtext("particella")) == ("123", "45")
        assert root.findtext("software/nome") == "Pre-APE"
        assert "stima preliminare" in root.findtext("note_specifiche")
        subs = root.findall("ace/subalterni/dati_subalterno")
        assert [s.findtext("subalterno") for s in subs] == ["7"]
        energia = subs[0].find("zone_termiche/dati_zona_termica/energia_netta")
        assert energia.findtext("destinazione_uso") == "E.1(1)"
        assert energia.findtext("ambienti_riscaldati/superficie_utile") == "95.0"
        gen = root.find("ace/centrali_termiche/dati_centrale_termica/generatori/generatore_tradizionale")
        assert gen.findtext("combustibile") == "1"
        assert gen.findtext("potenza_termica_nominale") == "24.0"
        assert root.findtext("ace/pannelli_solari/dati_pannello_solare/potenza_di_picco") == "3.5"
        assert root.find("ace/risultati/classe").text is None  # nessun risultato inventato
        assert "stima preliminare" in _comment(xml.content)

    @pytest.mark.parametrize("make", [_empty_survey, _full_survey])
    def test_valid_against_dtd(self, dtd, make):
        _assert_valid(dtd, build_cened_xml_12(make()).content)

    @pytest.mark.parametrize("generatore", ["caldaia_condensazione", "pompa_calore_aria_acqua",
                                            "teleriscaldamento", "stufa_pellet",
                                            "radiatori_elettrici"])
    def test_valid_against_dtd_other_generators(self, dtd, generatore):
        survey = _full_survey(building={"generatore": generatore, "terminali": "split"})
        _assert_valid(dtd, build_cened_xml_12(survey).content)


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------
def _url(survey_id: str, fmt: str = None) -> str:
    url = f"/api/v1/surveys/{survey_id}/cened-xml"
    return url if fmt is None else f"{url}?format={fmt}"


class TestCenedXmlEndpoint:
    @pytest.mark.parametrize("fmt,suffix,root_tag", [
        (None, "cened20", f"{C}calcolo"), ("2.0", "cened20", f"{C}calcolo"), ("1.2", "cened12", "dati"),
    ])
    def test_owner_downloads(self, client, auth_a, fmt, suffix, root_tag):
        headers, _ = auth_a
        survey_id = create_survey(client, headers, square_meters=95, avg_height=2.7,
                                  building=FULL_BUILDING, cadastral=[UNIT_FLAT])
        response = client.get(_url(survey_id, fmt), headers=headers)
        assert response.status_code == 200, response.text
        assert response.headers["content-type"].startswith("application/xml")
        expected = f'attachment; filename="preape_{uuid.UUID(survey_id).hex[:8]}_{suffix}.xml"'
        assert response.headers["content-disposition"] == expected
        assert ET.fromstring(response.content).tag == root_tag

    def test_other_user_404(self, client, auth_a, auth_b):
        survey_id = create_survey(client, auth_a[0])
        assert client.get(_url(survey_id, "2.0"), headers=auth_b[0]).status_code == 404

    def test_unknown_survey_404(self, client, auth_a):
        assert client.get(_url(str(uuid.uuid4())), headers=auth_a[0]).status_code == 404

    @pytest.mark.parametrize("fmt", ["3.0", "xml", "12"])
    def test_bad_format_422(self, client, auth_a, fmt):
        survey_id = create_survey(client, auth_a[0])
        assert client.get(_url(survey_id, fmt), headers=auth_a[0]).status_code == 422

    def test_requires_auth(self, client, auth_a):
        survey_id = create_survey(client, auth_a[0])
        assert client.get(_url(survey_id)).status_code == 401

"""File XML del sopralluogo da *provare* a importare in CENED+2.0.

CENED+2.0 (Regione Lombardia) importa da «File → Importa file XML» due formati:

* ``build_calcolo_xml_20`` – ``calcolo.xml`` nel formato 2.0 (``calcolo.xsd`` /
  ``datiCalcolo.xsd``). Contiene solo ``datiInput``: niente ``valoriIntermedi``,
  ``datiOutput``, ``hash``, ``hashImport`` né ``licenza`` (sono prodotti dal
  motore CENED e firmati: non li falsifichiamo). Per questo CENED+2.0 lo
  rifiuta in ``CenedImportXML.verificaValidita``; serve comunque come dato
  strutturato e validabile contro lo schema.
* ``build_cened_xml_12`` – file ``dati`` nel vecchio formato CENED+ 1.2 (DTD
  ``cened_Versione-1-0-5.dtd`` pubblicato dalla Regione). CENED+2.0 lo converte
  col proprio motore (``Trasforma12In20Service``) prima della stessa verifica.

Entrambe le funzioni sono pure (ricevono il modello ``Survey``) e restituiscono
``CenedXml(content: bytes, defaults: list[str])``: ``defaults`` elenca i valori
che il formato richiede ma che il sopralluogo non contiene (valori prudenziali
documentati o default del motore di stima), ripetuti nel commento in testa al
file. Il file resta una **stima preliminare** da completare e calcolare in CENED
dal certificatore: non è un APE.

Codifiche CENED usate (verificate sui casi di test ufficiali TCS1/TCS2 e sulle
tabelle del convertitore 1.2→2.0): destinazioneUso 2 = E.1(1) abitazioni,
tipoAmbiente 99 = ambiente residenziale, tipoVettoreEnergetico 1 = metano,
tipoGeneratoreCombustione 2 = generatore a gas standard, tipoSistemaRisc 1 =
idronico, tipoTerminale 1/3/7 = radiatori/ventilconvettori/pannelli a pavimento,
tipoRegolazione 1/3/4/6 = solo caldaia/zona/ambiente/climatica+ambiente.
Ciò che non ha una codifica certa (pompe di calore, biomassa, teleriscaldamento,
GPL/gasolio, caldaie a condensazione nel 2.0) non viene scritto e finisce
nell'elenco «da inserire in CENED».

Gli XSD/DTD CENED non stanno nel repo (licenza): vedi ``tests/test_cened_xml.py``.
"""
from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from app.core.catasto import CadastralUnit
from app.core.cened.sheet import _parse_building, _parse_units
from app.core.energy import climate
from app.core.energy.engine import Resolved, resolve_inputs
from app.core.energy.inputs import BuildingInputs

NS_CALCOLO = "http://www.cened.it/cenedplus2/calcolo"
NS_DATI = "http://www.cened.it/cenedplus2/datiCalcolo"

SOFTWARE_NAME = "Pre-APE"
DISCLAIMER = (
    "Pre-APE - file di pre-sopralluogo (stima preliminare/indicativa, non e' un APE). "
    "Dati raccolti dal tecnico da completare e calcolare in CENED+2.0 dal certificatore. "
    "Non contiene risultati, hash o licenza del motore CENED."
)

# Codici CENED 2.0 (vedi docstring del modulo)
DEST_USO_E11 = 2
TIPO_AMBIENTE_RESIDENZIALE = 99
VETTORE_METANO = 1
TIPO_GEN_COMBUSTIONE_STANDARD = 2
TIPO_SISTEMA_RISC_IDRONICO = 1
TERMINALE_20 = {"radiatori": 1, "ventilconvettori": 3, "pavimento": 7}
# regolazione Pre-APE -> (tipoRegolazione, caratteristicaRegolazione)
REGOLAZIONE_20 = {
    "nessuna": (1, None),
    "termostato_ambiente": (3, 1),       # solo zona, on-off
    "valvole_termostatiche": (4, 2),     # solo ambiente, P banda 2 °C
    "climatica_valvole": (6, 2),         # climatica + ambiente
}
_RESIDENTIAL_A = {1, 2, 3, 4, 5, 6, 7, 8, 9, 11}


@dataclass
class CenedXml:
    content: bytes
    defaults: List[str] = field(default_factory=list)
    missing: List[str] = field(default_factory=list)  # dati non esportati: da inserire in CENED


# ---------------------------------------------------------------------------
# Dati comuni ai due formati
# ---------------------------------------------------------------------------
@dataclass
class _Unit:
    unit: CadastralUnit
    istat: Optional[str]
    area: float


class _Data:
    def __init__(self, survey):
        self.survey = survey
        self.b: BuildingInputs = _parse_building(getattr(survey, "building", None))
        g = lambda name: getattr(survey, name, None)  # noqa: E731
        self.address: Optional[str] = g("address")
        self.r: Resolved = resolve_inputs(
            self.b,
            square_meters=g("square_meters"),
            avg_height=g("avg_height"),
            address=self.address,
            latitude=g("latitude"),
            longitude=g("longitude"),
            legacy={k: g(k) for k in ("wall_thickness", "window_frame", "window_glass",
                                      "heating_type", "generator_type", "generator_year")},
        )
        self.assumed: Dict[str, Any] = {a["campo"]: a["valore"] for a in self.r.assunzioni}
        self.defaults: List[str] = []
        self.missing: List[str] = []
        self.power_kw: Optional[float] = (
            self.b.potenza_kw if self.b.potenza_kw is not None else g("generator_power_kw"))

        units = _parse_units(g("cadastral"))
        first = units[0] if units else None
        comune_name = self.b.comune or (self.r.comune or {}).get("comune") or (first.comune if first else None)
        provincia = self.b.provincia or (self.r.comune or {}).get("provincia") or (first.provincia if first else None)
        self.comune = climate.find(comune_name, provincia) if comune_name else None
        self.istat: Optional[str] = self.comune.istat if self.comune else None
        if self.istat is None:
            self.default("Comune/codice ISTAT", "non individuato (ND)")

        heated = [u for u in units if _is_heated(u.categoria)]
        skipped = [u for u in units if u not in heated]
        for u in skipped:
            self.missing.append(
                f"Unità catastale sub. {u.subalterno or '?'} (categoria {u.categoria}): "
                "non climatizzata presunta, non esportata")
        self.units: List[_Unit] = []
        rows = heated or [CadastralUnit()]
        for u in rows:
            istat = self.istat
            if u.comune:
                found = climate.find(u.comune, u.provincia)
                istat = found.istat if found else istat
            if len(rows) == 1:
                area = self.r.af
            elif u.superficie_mq:
                area = float(u.superficie_mq)
            else:
                area = self.r.af / len(rows)
                self.default(f"Superficie utile sub. {u.subalterno or '?'}",
                             f"{area:.2f} m² (superficie del sopralluogo ripartita)")
            self.units.append(_Unit(u, istat, round(area, 2)))
        if "square_meters" in self.assumed:
            self.default("Superficie utile", f"{self.r.af:g} m² (default stima)")
        if "avg_height" in self.assumed:
            self.default("Altezza media netta", f"{self.r.height:g} m (default stima)")
        if "anno_costruzione" in self.assumed:
            self.default("Anno di costruzione", f"{self.r.anno} (default stima)")

    def default(self, label: str, value: str) -> None:
        self.defaults.append(f"{label}: {value}")

    def first_unit(self) -> CadastralUnit:
        return self.units[0].unit

    def province_code(self, istat: Optional[str]) -> str:
        return istat[:3] if istat else ""


def _is_heated(categoria: Optional[str]) -> bool:
    """Residenziale (A/1…A/9, A/11) o categoria ignota -> zona climatizzata."""
    if not categoria:
        return True
    match = re.fullmatch(r"A\s*/?\s*(\d{1,2})", categoria.strip().upper())
    return bool(match and int(match.group(1)) in _RESIDENTIAL_A)


def _num(value: float) -> str:
    text = f"{float(value):.3f}".rstrip("0")
    return text + "0" if text.endswith(".") else text


def _survey_date(survey) -> str:
    when = getattr(survey, "created_at", None)
    if isinstance(when, datetime):
        return when.date().isoformat()
    return date.today().isoformat()


def _comment(defaults: List[str], missing: List[str], fmt: str) -> str:
    lines = [DISCLAIMER, f"Formato: {fmt}. Generato da {SOFTWARE_NAME} il {date.today().isoformat()}."]
    if defaults:
        lines.append("Valori di default (non rilevati, da verificare):")
        lines += [f" - {d}" for d in defaults]
    if missing:
        lines.append("Dati non esportati, da inserire in CENED:")
        lines += [f" - {m}" for m in missing]
    text = "\n".join(lines)
    text = text.replace("--", "- -")  # "--" non è ammesso nei commenti XML
    return f"<!--\n{text}\n-->\n"


def _serialize(root: ET.Element, comment: str) -> bytes:
    body = ET.tostring(root, encoding="unicode")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n' + comment + body + "\n").encode("utf-8")


# ---------------------------------------------------------------------------
# Formato 2.0 (calcolo.xsd)
# ---------------------------------------------------------------------------
ET.register_namespace("c", NS_CALCOLO)
ET.register_namespace("d", NS_DATI)


def _c(tag: str) -> str:
    return f"{{{NS_CALCOLO}}}{tag}"


def _d(tag: str) -> str:
    return f"{{{NS_DATI}}}{tag}"


def _sub(parent: ET.Element, tag: str, **attrs: Any) -> ET.Element:
    clean = {}
    for key, value in attrs.items():
        if value is None:
            continue
        if isinstance(value, bool):
            value = "true" if value else "false"
        elif isinstance(value, float):
            value = _num(value)
        clean[key] = str(value)
    return ET.SubElement(parent, _d(tag), clean)


def _heating_20(x: _Data) -> Optional[Dict[str, Any]]:
    """Generatore esportabile nel 2.0 (solo codifiche certe), altrimenti None."""
    r = x.r
    if "generatore" in x.assumed:
        x.missing.append("Generatore di calore (non rilevato)")
        return None
    if r.generatore != "caldaia_tradizionale" or r.combustibile != "metano":
        x.missing.append(f"Generatore: {r.generatore.replace('_', ' ')}"
                         + (f" a {r.combustibile}" if r.generatore.startswith("caldaia") else "")
                         + " (codifica CENED non certa: inserirlo in CENED)")
        return None
    if "combustibile" in x.assumed:
        x.default("Combustibile", "metano (default stima)")
    if "anno_generatore" in x.assumed:
        x.default("Anno installazione generatore", f"{r.anno_gen} (default stima)")
    return {"anno": max(1870, min(2100, r.anno_gen)), "power": x.power_kw}


def _terminal_20(x: _Data) -> Optional[Tuple[int, int, Optional[int]]]:
    r = x.r
    tipo = TERMINALE_20.get(r.terminali)
    if tipo is None:
        x.missing.append(f"Terminali di emissione: {r.terminali} (da inserire in CENED)")
        return None
    if "terminali" in x.assumed:
        x.default("Terminali", f"{r.terminali} (default stima)")
    regol, caratt = REGOLAZIONE_20[r.regolazione]
    if "regolazione" in x.assumed:
        x.default("Regolazione", f"{r.regolazione.replace('_', ' ')} (default stima)")
    return tipo, regol, caratt


def build_calcolo_xml_20(survey) -> CenedXml:
    """``calcolo.xml`` CENED+2.0 con i soli dati di input del sopralluogo."""
    x = _Data(survey)
    r = x.r
    first = x.first_unit()

    root = ET.Element(_c("calcolo"))
    cert = ET.SubElement(ET.SubElement(root, _c("datiInput")), _d("certificazione"))
    # Niente versioneMotore/Client/Database: il file non viene dal motore CENED.
    _sub(cert, "software", nomeSoftware=SOFTWARE_NAME, produttoreSoftware=SOFTWARE_NAME,
         dichiarazioneSoftware="File di pre-sopralluogo: stima preliminare, non calcolato dal motore CENED")
    _sub(cert, "configurazioneCalcolo", riferimentoNormativo="-",
         metodoCapacitaTermicaPuntuale=False, metodoEntalpiaPuntuale=False,
         metodoAnaliticoZNCTerreno=False, certificazione=True,
         metodoTabellareDistribuzioneACS=True, dispersioniProfiloLordo=True)
    x.default("Configurazione calcolo",
              "metodi semplificati/tabellari (capacità termica, ZNC/terreno non analitici)")
    clima = _sub(_sub(cert, "dizionario"), "servizioDatiClimatici", id=1)
    _sub(clima, "input", codiceIstat=x.istat or "ND")

    _sub(cert, "datiAnagrafici", noteApe=DISCLAIMER, proprietaPubblica=False, usoPubblico=False)
    x.default("Proprietà/uso pubblico", "no")

    heated_rooms = x.units
    edificio = _sub(
        cert, "datiEdificio",
        annoCostruzione=r.anno if 1800 <= r.anno <= 2100 else None,
        numeroPiani=x.b.numero_piani,
        provincia=x.province_code(x.istat), comune=x.istat or "",
        provinciaCatastale=x.province_code(heated_rooms[0].istat),
        comuneCatastale=heated_rooms[0].istat or "",
        sezioneUrbana=first.sezione_urbana,
        foglio=first.foglio or "ND", particella=first.particella or "ND",
        numeroSopralluoghi=1, piano=first.piano,
        indirizzo=first.indirizzo or x.address,
        destinazioneResidenziale=True, destinazioneNonResidenziale=False,
    )
    if not first.foglio or not first.particella:
        x.default("Foglio/particella", "ND (non indicati)")

    gen = _heating_20(x)
    term = _terminal_20(x) if gen else None
    with_heating = gen is not None and term is not None
    acs_combined = with_heating and r.acs == "combinata"
    if not acs_combined:
        x.missing.append(f"Acqua calda sanitaria: {r.acs.replace('_', ' ')} (da inserire in CENED)")
    if r.raffrescamento != "nessuno":
        x.missing.append(f"Raffrescamento: {r.raffrescamento.replace('_', ' ')} (da inserire in CENED)")
    if r.pv_kwp:
        x.missing.append(f"Fotovoltaico: {_num(r.pv_kwp)} kWp (da inserire in CENED)")
    if r.solare_termico:
        x.missing.append("Solare termico (da inserire in CENED)")
    if r.vmc != "nessuna":
        x.missing.append(f"Ventilazione meccanica: {r.vmc} (da inserire in CENED)")
    x.missing.append("Strutture opache, serramenti, dispersioni e ponti termici "
                     f"(valori della stima: muratura {r.muratura.replace('_', ' ')}, telaio {r.telaio}, "
                     f"vetro {r.vetro}): da descrivere in CENED")

    subalterni = _sub(edificio, "subalterni", numeroSubalterni=len(heated_rooms))
    x.default("Numero proprietari per subalterno", "1")
    x.default("Interventi eseguiti", "nessuno")
    x.default("Destinazione d'uso", "E.1(1) abitazioni (zona termica unica per subalterno)")
    for n, hu in enumerate(heated_rooms, start=1):
        unit = hu.unit
        sub = _sub(subalterni, "subalterno", id=n, periodoCostruzione=2, anno=r.anno,
                   interventiEseguiti=False, numeroProprietari=1,
                   subalternoNumero=unit.subalterno or "",
                   nomeSubalterno=f"Sub. {unit.subalterno}" if unit.subalterno else f"Unità {n}",
                   noteSubalterno=(f"Categoria catastale {unit.categoria}" if unit.categoria else None))
        zona = _sub(_sub(sub, "zone"), "zona", id=1, nome="Zona termica 1",
                    destinazioneUso=DEST_USO_E11, pubblico=False, acsAttivo=True,
                    riscAttivo=True, rafAttivo=r.raffrescamento != "nessuno",
                    ventAttivo=r.vmc != "nessuna")
        _sub(zona, "geometria", altezzaMediaNetta=float(r.height), superficieUtile=hu.area,
             superficieLorda=0.0, volumeNetto=round(hu.area * r.height, 2), volumeLordo=0.0)
        _sub(_sub(zona, "ambienti"), "ambiente", id=1, tipoAmbiente=TIPO_AMBIENTE_RESIDENZIALE,
             area=hu.area, nome="Ambiente unico")
        if acs_combined:
            _sub(zona, "sistemaAcs", id=1, rifSistemaAcs=1)
        if with_heating:
            tipo, regol, caratt = term
            risc = _sub(zona, "sistemaRisc", id=1, rifSistemaRisc=2)
            _sub(risc, "tipoTerminale", id=1, priorita=1, tipoTerminale=tipo,
                 tipoRegolazione=regol, caratteristicaRegolazione=caratt,
                 inerziaErogazione=1, nome=r.terminali.capitalize())
        _sub(_sub(sub, "proprietari"), "proprietario", idProprietario=1)
    if not heated_rooms[0].area:
        x.default("Superficie utile", "0")
    x.default("Superficie/volume lordi", "0 (da calcolare in CENED)")

    if with_heating:
        impianti = _sub(edificio, "impianti")
        sistemi = _sub(impianti, "sistemiImpiantistici")
        if acs_combined:
            _sub(_sub(sistemi, "sistemiAcs"), "sistema", id=1, ricircolo=False, accumulo=False,
                 circolazioneAcquaFredda=False, produzioneSeparata=False, rifCentraleTermica=1,
                 nome="ACS combinata")
            x.default("Sistema ACS", "senza ricircolo né accumulo")
        _sub(_sub(sistemi, "sistemiRisc", priorita=False, prioritaNormativa=False), "sistema",
             id=2, priorita=1, tipoSistemaRisc=TIPO_SISTEMA_RISC_IDRONICO, prioritaTerminali=False,
             rifCentraleTermica=1, nome="Riscaldamento idronico")
        centrale = _sub(_sub(impianti, "centraliTermiche"), "centraleTermica", id=1,
                        prioritaNormativa=False, collegamentoPrimarioCentrale=1,
                        proporzionamentoGeneratore=True, nome="Caldaia")
        gruppo = _sub(_sub(centrale, "generatori"), "gruppoGeneratoriCombustione",
                      id=1, tipoVettoreEnergetico=VETTORE_METANO, priorita=1,
                      tipoGeneratoreCombustione=TIPO_GEN_COMBUSTIONE_STANDARD, potenza12831=False,
                      nome="Generatore a metano")
        _sub(gruppo, "generatoreCombustione", id=1, prioritaGeneratore=1,
             phi_h_gn_out_n=float(gen["power"]) if gen["power"] else None,
             annoInstallazioneImpianto=gen["anno"], nome="Generatore 1")
        if not gen["power"]:
            x.missing.append("Potenza nominale del generatore")
        _sub(_sub(impianti, "centraliElettriche"), "centraleElettrica", id=1,
             prioritaNormativa=True, nome="Rete elettrica")
    _sub(_sub(edificio, "sopralluoghi"), "sopralluogo", idSopralluogo=1,
         dataSopralluogo=_survey_date(survey),
         descrizioneSopralluogo="Pre-sopralluogo Pre-APE (stima preliminare)")

    content = _serialize(root, _comment(x.defaults, x.missing, "CENED+2.0 calcolo.xml (solo datiInput)"))
    return CenedXml(content=content, defaults=x.defaults, missing=x.missing)


# ---------------------------------------------------------------------------
# Formato CENED+ 1.2 (cened_Versione-1-0-5.dtd)
# ---------------------------------------------------------------------------
Spec = Tuple[str, Any]  # (tag, testo | lista di Spec)


def _build(parent: Optional[ET.Element], spec: Spec) -> ET.Element:
    tag, content = spec
    el = ET.Element(tag) if parent is None else ET.SubElement(parent, tag)
    if isinstance(content, list):
        for child in content:
            _build(el, child)
    elif content is not None:
        el.text = str(content)
    return el


def _empty(*tags: str) -> List[Spec]:
    return [(t, "") for t in tags]


MONTHS = ("gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic")
# Pre-APE -> testi CENED 1.2 (tabelle del convertitore 1.2→2.0)
TERMINALE_12 = {
    "radiatori": "Radiatori su parete esterna isolata",
    "ventilconvettori": "Ventilconvettori (valori riferiti a tmedia acqua=45 Gradi)",
    "pavimento": "Pannelli annegati a pavimento",
}
REGOLAZIONE_12 = {
    "nessuna": ("", ""),
    "termostato_ambiente": ("Solo zona con regolatore", "On off"),
    "valvole_termostatiche": ("Solo ambiente con regolatore ", "P banda prop. 2 Gradi C"),
    "climatica_valvole": ("Climatica+ambiente con regolatore", "P banda prop. 2 Gradi C"),
}
COMBUSTIBILE_12 = {"metano": "1"}


def _no_storage() -> Spec:
    """Accumulo assente: forma estesa del DTD con campi vuoti (il convertitore
    CENED legge ``anno_installazione`` senza controllare null)."""
    return ("accumulo", _empty("anno_installazione", "dispersione_termica", "temperatura_media",
                               "ubicazione", *[f"temp_{m}" for m in MONTHS],
                               "superficie_serbatoio", "spessore_isolante",
                               "conduttivita_isolante", "volume", "coefficiente_perdita"))


def _surfaces(area: float, height: float) -> List[Spec]:
    return [("superficie_utile", _num(area)), ("superficie_lorda", ""),
            ("volume_netto", _num(round(area * height, 2))), ("volume_lordo", "")]


def _shading() -> List[Spec]:
    return [("ostruzioni", _empty("d", "h", "x")),
            ("aggetti_orizzontali", _empty("d", "h", "a")),
            ("aggetti_verticali", _empty("d", "h", "b"))]


def _zona_12(x: _Data, hu: _Unit) -> Spec:
    r = x.r
    raf_area = hu.area if r.raffrescamento != "nessuno" else 0.0
    energia = [
        ("destinazione_uso", "E.1(1)"), ("pubblico", "0"),
        ("altezza_media_netta", _num(r.height)),
        *_empty("intonaco", "isolamento", "parete_esterna", "pavimento",
                "capacita_termica_areica"),
        ("area_totale", _num(hu.area)),
        ("ambienti_riscaldati", _surfaces(hu.area, r.height)),
        ("ambienti_raffrescati", _surfaces(raf_area, r.height)),
        *_empty("fattore_di_occupazione", "valore_globale_apporti_interni"),
        ("ventilazione", _empty("tipo", "sottotipo", "controllo_umidita",
                                "temperatura_di_immissione", "alimentazione_batteria",
                                "perc_portata_aria_esterna", "ricambi_orari", "portata_di_rinnovo",
                                "efficienza_recuperatore", "tipo_recuperatore",
                                "temp_acqua_atomizzatore")),
        ("pareti", [("parete_opaca", [
            ("numero", "1"),
            ("descrizione_parete", f"Muratura {r.muratura.replace('_', ' ')} (da definire in CENED)"),
            *_empty("tipologia_componente", "tipo_parete", "grado_finitura"),
            ("strutture", [])])]),
        ("elementi", [("elemento_opaco", [
            ("numero", "1"), ("quantita", "1"), ("parete", "1"),
            *_empty("superficie", "esposizione", "inclinazione", "ambiente_circostante",
                    "zona_ambiente_circostante"),
            ("ponti_termici", []), *_shading()])]),
        ("serra_solare", [*_empty("volume_serra", "ricambi_serra", "apribile"),
                          ("serra_elementi", [])]),
        ("vapore_acqua", [*_empty("attivita", "fatt_pres_medio_giorno"), ("apparecchiature", [])]),
        ("acs", _empty("produzione", "tipo_attivita", "stelle", "nu")),
        ("ambienti_illuminazione", []),
        ("sistemi_controllo", _empty("esistenza_sistemi_mantenimento_valori_costanti",
                                     "tipo_sistema_ottimizzazione_luce_naturale",
                                     "tipo_sistema_funzione_presenza")),
        ("congruenza_dest_catasto_stato_fatto", ""),
    ]
    return ("dati_zona_termica", [("codice_posizione", "1"), ("cod_zona_termica", "1"),
                                  ("zona_termica", "Zona termica 1"), ("energia_netta", energia)])


def _generatore_12(x: _Data) -> Spec:
    r = x.r
    comb = COMBUSTIBILE_12.get(r.combustibile, "") if r.generatore.startswith("caldaia") else ""
    power = _num(x.power_kw) if x.power_kw else ""
    desc = r.generatore.replace("_", " ")
    head = [("codice_generatore", "1"), ("indice", "1"), ("descrizione", desc), ("combustibile", comb)]
    if r.generatore == "caldaia_condensazione":
        return ("generatore_condensazione", head + [
            *_empty("installazione_generatore", "rendimento", "temperatura_riferimento"),
            ("potenza_termica_nominale", power),
            *_empty("potenza_totale_elettrica_bruciatori", "potenza_totale_elettrica_pompe",
                    "ubicazione_generatore", "tipo_per_peso", "eta",
                    "tipo_perdite_camino_bruciatore_acceso", "tipo_perdite_camino_bruciatore_spento",
                    "temperatura_media_acqua", "temperatura_media_acqua_condizioni_test",
                    "perdite_nominali_attraverso_mantello",
                    "perdite_nominali_camino_bruciatore_spento",
                    "perdite_nominali_camino_bruciatore_acceso")])
    if r.generatore in ("pompa_calore_aria_acqua", "pompa_calore_geotermica", "split_aria_aria"):
        return ("pompa_calore", head[:3] + [("combustibile", "7"), ("tipo_scambio", ""),
                                           ("temperatura_nominale_evaporatore", ""),
                                           *[(f"cop_{m}", "") for m in MONTHS],
                                           ("potenza_elettrica", ""),
                                           ("potenza_termica_nominale", power)])
    if r.generatore == "teleriscaldamento":
        return ("teleriscaldamento", head + [
            ("potenza_termica_nominale", power),
            *_empty("fattore_di_perdita", "fattore_conversione_energia_primaria", "kss",
                    "ubicazione", "temperatura_media")])
    if r.generatore == "radiatori_elettrici":
        return ("generatore_infrarossi", head[:3] + [("combustibile", "7")])
    if r.generatore in ("caldaia_biomassa", "stufa_pellet", "stufa_legna"):
        return ("generatore_a_biomassa", head + [
            *_empty("funzionamento", "tipologia", "serbatoio_inerziale"),
            ("potenza_termica_nominale", power),
            *_empty("potenza_termica_di_progetto", "potenza_pieno_carico",
                    "potenza_carico_intermedio", "potenza_carico_nullo"),
            ("data_installazione", str(r.anno_gen)),
            *_empty("rendimento", "temperatura_di_ritorno", "installazione_esterno",
                    "camino_superiore_10_m", "temperatura_media_maggiore_65",
                    "generatore_monostadio", "camino_superiore_10_m_assenza_chiusura")])
    return ("generatore_tradizionale", head + [
        ("rendimento", ""), ("potenza_termica_nominale", power),
        *_empty("potenza_totale_elettrica_bruciatori", "potenza_totale_elettrica_pompe",
                "installazione_generatore", "ubicazione_generatore", "tipo_per_peso", "eta",
                "tipo_perdite_camino_bruciatore_acceso", "tipo_perdite_camino_bruciatore_spento",
                "temperatura_media_acqua", "perdite_nominali_attraverso_mantello",
                "perdite_nominali_camino_bruciatore_spento",
                "perdite_nominali_camino_bruciatore_acceso")])


def build_cened_xml_12(survey) -> CenedXml:
    """File ``dati`` CENED+ 1.2 (DTD 1.0.5) con i dati del sopralluogo."""
    x = _Data(survey)
    r = x.r
    first = x.first_unit()
    if "generatore" in x.assumed:
        x.default("Generatore", f"{r.generatore.replace('_', ' ')} (default stima)")
    if r.generatore.startswith("caldaia") and r.combustibile not in COMBUSTIBILE_12:
        x.missing.append(f"Combustibile: {r.combustibile} (codice CENED 1.2 non certo)")
    elif "combustibile" in x.assumed:
        x.default("Combustibile", "metano (default stima)")
    if not x.power_kw:
        x.missing.append("Potenza nominale del generatore")
    term_text = TERMINALE_12.get(r.terminali, "")
    if not term_text:
        x.missing.append(f"Terminali di emissione: {r.terminali} (da inserire in CENED)")
    regol, caratt = REGOLAZIONE_12[r.regolazione]
    x.missing.append("Strutture opache e serramenti (stratigrafie, superfici, esposizioni)")
    x.missing.append("Rendimenti, distribuzione, accumuli e risultati (calcolati da CENED)")
    x.default("Numero proprietari", "1")
    x.default("Destinazione d'uso", "E.1(1) abitazioni (zona termica unica per subalterno)")

    zones = [("dati_subalterno", [("subalterno", hu.unit.subalterno or ""),
                                  ("zone_termiche", [_zona_12(x, hu)])]) for hu in x.units]
    acs_combined = r.acs == "combinata"
    centrale = ("dati_centrale_termica", [
        ("centrale_termica", "1"), ("descrizione", "Centrale termica"),
        ("riscaldamento", "1"), ("climatizzazione_invernale", "1"),
        ("climatizzazione_estiva", "0"), ("ventilazione_pre_riscaldamento", "0"),
        ("raffrescamento", "0"), ("ventilazione_pre_raffrescamento", "0"),
        ("acqua_calda_sanitaria", "1" if acs_combined else "0"),
        _no_storage(),
        *_empty("tipo_funzionamento_generatori", "funzionamento_parallelo", "volume_totale",
                "fabbisogno_totale"),
        ("generatori", [_generatore_12(x)])])
    emissione = ("emissione", [("tipologia", term_text), ("rendimento", ""), ("descrizione_acs", "")])
    distribuzione = ("distribuzione", [
        ("tipologia", ""), ("isolamento", ""),
        ("tipo_impianto", "Autonomo" if r.impianto == "autonomo" else "Centralizzato"),
        *_empty("rendimento", "impianto_temp_variabile", "anno_installazione_acs",
                "circuito_primario")])
    sistema = ("dati_sistema_impiantistico", [
        ("sistema_impiantistico", "1"), ("descrizione", "Riscaldamento"), ("servizio", "1"),
        emissione,
        ("controllo", [("tipo_regolazione", regol), ("caratteristiche", caratt), ("rendimento", "")]),
        distribuzione,
        _no_storage(),
        ("tratti_rete", [])])
    ramificazione = ("dati_ramificazione", [
        ("ramificazione", "1"), ("codice_sistema", "1"), ("descrizione", "Ramificazione 1"),
        ("trattamento_aria", [("potenza_elettrica", "")]),
        emissione, distribuzione,
        ("distribuzione_av", [("potenza_elettrica", "")]),
        _no_storage()])
    associazioni = [("dati_associazione_zone_termiche", [
        ("associazione_zona_termica", str(n)), ("subalterno", hu.unit.subalterno or ""),
        ("zona_termica", "1"), ("ramificazione", "1"), ("sistema_impiantistico", "1"),
        ("centrale_termica", "1"), ("accumulo_centrale_termica", "")])
        for n, hu in enumerate(x.units, start=1)]
    pannelli: List[Spec] = []
    if r.pv_kwp:
        pannelli.append(("dati_pannello_solare", [
            ("pannello_solare", "1"), ("descrizione", "Fotovoltaico"), ("tipo_modulo", ""),
            *_empty("esposizione", "inclinazione", "superficie_captante"),
            ("potenza_di_picco", _num(r.pv_kwp)), ("potenza_ausiliari", ""),
            ("ventilazione_p", "")]))
    if r.solare_termico:
        x.missing.append("Solare termico (da inserire in CENED)")
    if r.raffrescamento != "nessuno":
        x.missing.append(f"Raffrescamento: {r.raffrescamento.replace('_', ' ')} (da inserire in CENED)")
    if not acs_combined:
        x.missing.append(f"Acqua calda sanitaria: {r.acs.replace('_', ' ')} (da inserire in CENED)")

    ace = ("ace", [
        ("subalterni", zones), ("centrali_combinate", ""),
        ("centrali_termiche", [centrale]), ("sistemi_impiantistici", [sistema]),
        ("ramificazioni", [ramificazione]), ("associazioni_zone_termiche", associazioni),
        ("superficie_utile_servita_collettori", ""), ("collettori_solari", []),
        ("superficie_utile_servita_pannelli", ""), ("esportazione_rete_nazionale", ""),
        ("pannelli_solari", pannelli),
        ("risultati", _empty("eph", "epw", "epl", "egh", "egw", "egl", "eghw", "eth", "etw",
                             "etc", "solare_riscaldamento", "solare_acs", "solare_fotovoltaico",
                             "classe", "key", "co2", "superficieutile", "superficieinvolucro",
                             "volumelordo", "rapportosv")),
        ("interventi_migliorativi", []),
    ])
    sigla = x.comune.provincia if x.comune else (first.provincia or "")
    dati = ("dati", [
        ("software", [("nome", SOFTWARE_NAME), ("versione", "1.0"), ("cod_posizione", "")]),
        *_empty("cod_certificatore", "rif_procedura", "protocollo"),
        ("provincia", sigla),
        ("comune", x.comune.nome if x.comune else (first.comune or "")),
        ("codice_istat", x.istat or ""),
        ("indirizzo", first.indirizzo or x.address or ""), ("ncivico", ""),
        ("sezione_amministrativa", ""), ("sezione_urbana", first.sezione_urbana or ""),
        ("foglio", first.foglio or ""), ("particella", first.particella or ""),
        ("proprietario", _empty("nome", "cognome", "ragione_sociale")),
        ("responsabile", _empty("nome", "cognome", "ragione_sociale")),
        *_empty("tipo_ace", "progettista_architettonico",
                "progettista_impianto_climatizzazione", "direttore_lavori", "costruttore"),
        ("anno_di_costruzione", str(r.anno)),
        ("numero_piani", str(x.b.numero_piani or r.n_piani)),
        ("interventi_dopo_1976", []),
        *_empty("calcolo_ponte_termico", "calcolo_ft", "calcolo_capacita",
                "note_involucro", "note_impianti", "note_fonti_rinnovabili"),
        ("note_specifiche", DISCLAIMER),
        ("zone_ambiente_circostante", []),
        ace,
    ])
    root = _build(None, dati)
    content = _serialize(root, _comment(x.defaults, x.missing, "CENED+ 1.2 (DTD 1.0.5)"))
    return CenedXml(content=content, defaults=x.defaults, missing=x.missing)

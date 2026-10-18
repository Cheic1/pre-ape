"""Scheda CENED: i dati del sopralluogo nell'ordine delle schermate di CENED+2.0.

``build_cened_sheet(survey, documents)`` è pura (nessun accesso al DB): riceve
il modello ``Survey`` e la lista di ``DocumentMeta`` già serializzati.

Ogni riga ha uno ``status``:

* ``ok`` – dato rilevato dal tecnico (campo ``building``, colonne del
  sopralluogo, colonne "legacy" del primo MVP, dati catastali);
* ``stimato`` – valore di default usato dal motore di stima e riportato in
  ``energy_result.assunzioni`` (o suggerimento derivato, es. destinazione d'uso
  dalla categoria catastale): va verificato;
* ``da_rilevare`` – manca (``value`` = null).

``cened_field`` è ``elemento@attributo`` di ``datiCalcolo.xsd`` di CENED+2.0
quando la corrispondenza è chiara, altrimenti null. Gli XSD non stanno nel repo
(licenza): la mappatura è la base per un futuro generatore di ``calcolo.xml``.
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Iterable, List, Literal, Optional, Sequence
from uuid import UUID

from pydantic import BaseModel, ValidationError

from app.core.catasto import CadastralUnit
from app.core.energy import climate
from app.core.energy.engine import BOILERS, GENERATOR_LABEL, _LEGACY_GENERATOR, _LEGACY_HEATING
from app.core.energy.inputs import BuildingInputs

RowStatus = Literal["ok", "stimato", "da_rilevare"]

DISCLAIMER = (
    "Stima preliminare/indicativa: scheda di supporto per ricopiare i dati del "
    "sopralluogo in CENED+2.0, nell'ordine delle sue schermate. Non è un APE né un "
    "file importabile in CENED. Le righe «stimato» sono valori tipici usati dalla "
    "stima e vanno verificati; quelle «da rilevare» mancano."
)


class CenedRow(BaseModel):
    label: str
    value: Optional[str] = None
    cened_field: Optional[str] = None
    status: RowStatus


class CenedSection(BaseModel):
    key: str
    title: str
    rows: List[CenedRow]


class CenedSheet(BaseModel):
    survey_id: Optional[UUID] = None
    generated_at: datetime
    disclaimer: str
    sections: List[CenedSection]


# ---------------------------------------------------------------------------
# Etichette leggibili (codici di app.core.energy.inputs)
# ---------------------------------------------------------------------------
TIPOLOGIA_LABEL = {
    "appartamento": "Appartamento",
    "villetta": "Villetta / casa isolata",
    "bifamiliare": "Bifamiliare",
    "schiera": "Villetta a schiera",
}
PIANO_LABEL = {
    "terra": "Piano terra",
    "intermedio": "Piano intermedio",
    "ultimo": "Ultimo piano",
    "unico": "Unico piano (edificio indipendente)",
}
ORIENTAMENTO_LABEL = {"sud": "Sud", "est_ovest": "Est-ovest", "nord": "Nord", "misto": "Misto"}
MURATURA_LABEL = {
    "pietra": "Pietra",
    "mattoni_pieni": "Mattoni pieni",
    "mattoni_forati": "Mattoni forati",
    "blocchi_cemento": "Blocchi di cemento",
    "cemento_armato": "Cemento armato",
    "laterizio_alveolato": "Laterizio alveolato",
    "legno": "Legno",
}
SPESSORE_LABEL = {"<30cm": "Meno di 30 cm", "30-40cm": "30–40 cm", ">40cm": "Oltre 40 cm"}
COPERTURA_LABEL = {
    "terrazzo": "Terrazzo / tetto piano",
    "sottotetto": "Sottotetto non riscaldato",
    "falda_abitata": "Falda con sottotetto abitato",
}
PAVIMENTO_LABEL = {
    "terreno": "Terreno",
    "cantina": "Cantina / locale non riscaldato",
    "esterno": "Esterno (porticato, pilotis)",
}
TELAIO_LABEL = {
    "Legno": "Legno",
    "PVC": "PVC",
    "Alluminio": "Alluminio",
    "Alluminio TT": "Alluminio a taglio termico",
    "Ferro": "Ferro",
}
VETRO_LABEL = {v: v for v in ("Singolo", "Doppio", "Doppio basso emissivo", "Triplo")}
COMBUSTIBILE_LABEL = {"metano": "Metano", "gpl": "GPL", "gasolio": "Gasolio"}
IMPIANTO_LABEL = {"autonomo": "Autonomo", "centralizzato": "Centralizzato"}
TERMINALI_LABEL = {
    "radiatori": "Radiatori",
    "pavimento": "Pannelli radianti a pavimento",
    "ventilconvettori": "Ventilconvettori",
    "split": "Split (unità interne)",
    "stufa": "Stufa (emissione diretta)",
}
REGOLAZIONE_LABEL = {
    "nessuna": "Nessuna regolazione",
    "termostato_ambiente": "Termostato ambiente",
    "valvole_termostatiche": "Valvole termostatiche",
    "climatica_valvole": "Climatica + valvole termostatiche",
}
ACS_LABEL = {
    "combinata": "Combinata col riscaldamento",
    "boiler_elettrico": "Boiler elettrico",
    "scaldabagno_gas": "Scaldabagno a gas",
    "pompa_calore_acs": "Pompa di calore per ACS",
}
RAFFRESCAMENTO_LABEL = {"nessuno": "Nessuno", "split": "Split", "pompa_calore": "Pompa di calore"}
VMC_LABEL = {
    "nessuna": "Assente (ventilazione naturale)",
    "semplice": "VMC a semplice flusso",
    "recupero": "VMC con recupero di calore",
}
DOCUMENT_KIND_LABEL = {
    "visura": "Visura catastale",
    "planimetria": "Planimetria",
    "mappa": "Estratto di mappa",
    "altro": "Altro documento",
}

# Generatore -> (campo del tipo di generatore, elemento del singolo generatore)
# nel ramo centraleTermica/generatori di datiCalcolo.xsd.
GENERATOR_CENED: Dict[str, tuple] = {
    "caldaia_tradizionale": ("gruppoGeneratoriCombustione@tipoGeneratoreCombustione", "generatoreCombustione"),
    "caldaia_condensazione": ("gruppoGeneratoriCombustione@tipoGeneratoreCombustione", "generatoreCombustione"),
    "pompa_calore_aria_acqua": ("gruppoPompeCalore@tipologiaGeneratore", "pompaCalore"),
    "pompa_calore_geotermica": ("gruppoPompeCalore@tipologiaGeneratore", "pompaCalore"),
    "split_aria_aria": ("gruppoPompeCalore@tipologiaGeneratore", "pompaCalore"),
    "caldaia_biomassa": ("gruppoGeneratoriBiomassa@tipologiaGeneratore", "generatoreBiomassa"),
    "stufa_pellet": ("gruppoGeneratoriBiomassa@tipologiaGeneratore", "generatoreBiomassa"),
    "stufa_legna": ("gruppoGeneratoriBiomassa@tipologiaGeneratore", "generatoreBiomassa"),
    "teleriscaldamento": (None, "reteTeleriscaldamento"),
    "radiatori_elettrici": (None, "generatoreEffettoJoule"),
}

DEST_USO_RESIDENZIALE = "E.1(1) – Abitazioni a carattere continuativo"
_RESIDENTIAL_A = {1, 2, 3, 4, 5, 6, 7, 8, 9, 11}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _num(value: float, decimals: Optional[int] = None) -> str:
    """Italian number: 95.0 -> "95", 12.5 -> "12,5", (2.7, 2) -> "2,70"."""
    value = float(value)
    if decimals is None:
        if value == int(value):
            return str(int(value))
        text = f"{value:.2f}".rstrip("0")
    else:
        text = f"{value:.{decimals}f}"
    return text.replace(".", ",")


def _humanize(shown: Any, labels: Optional[Dict[str, str]] = None) -> str:
    """Engine assumption value (``valore``) -> readable Italian text."""
    if isinstance(shown, bool):
        return "Sì" if shown else "No"
    if isinstance(shown, (int, float)):
        return _num(shown)
    text = str(shown).strip()
    if labels:
        for key in (text, text.replace(" ", "_")):
            if key in labels:
                return labels[key]
    text = re.sub(r"(\d)\.(\d)", r"\1,\2", text)
    return text[:1].upper() + text[1:]


def _row(label: str, value: Optional[str], field: Optional[str], status: RowStatus) -> CenedRow:
    if value is None or value == "":
        return CenedRow(label=label, value=None, cened_field=field, status="da_rilevare")
    return CenedRow(label=label, value=value, cened_field=field, status=status)


def _parse_building(raw: Any) -> BuildingInputs:
    if not isinstance(raw, dict):
        return BuildingInputs()
    try:
        return BuildingInputs.model_validate(raw)
    except ValidationError:
        valid = {}
        for key, value in raw.items():  # keep what still validates
            try:
                BuildingInputs.model_validate({key: value})
                valid[key] = value
            except ValidationError:
                pass
        return BuildingInputs.model_validate(valid)


def _parse_units(raw: Any) -> List[CadastralUnit]:
    units = []
    for item in raw if isinstance(raw, list) else []:
        if not isinstance(item, dict):
            continue
        known = {k: v for k, v in item.items() if k in CadastralUnit.model_fields}
        try:
            units.append(CadastralUnit.model_validate(known))
        except ValidationError:
            continue
    return units


def _assumptions(result: Any) -> Dict[str, Any]:
    items = result.get("assunzioni") if isinstance(result, dict) else None
    out = {}
    for item in items if isinstance(items, list) else []:
        if isinstance(item, dict) and item.get("campo"):
            out[item["campo"]] = item.get("valore")
    return out


class _Ctx:
    def __init__(self, survey):
        self.survey = survey
        self.b = _parse_building(getattr(survey, "building", None))
        result = getattr(survey, "energy_result", None)
        self.result = result if isinstance(result, dict) else {}
        self.assumed = _assumptions(self.result)
        clima = self.result.get("clima")
        self.clima = clima if isinstance(clima, dict) else {}
        comune = self.clima.get("comune")
        self.clima_comune = comune if isinstance(comune, dict) else {}
        self.units = _parse_units(getattr(survey, "cadastral", None))

    def legacy(self, name: str):
        return getattr(self.survey, name, None)

    def pick(
        self,
        label: str,
        field: Optional[str],
        value: Any,
        fmt: Callable[[Any], str],
        assumption: Optional[str] = None,
        labels: Optional[Dict[str, str]] = None,
    ) -> CenedRow:
        """Rilevato -> ok; altrimenti default del motore -> stimato; altrimenti da_rilevare."""
        if value is not None and value != "":
            return _row(label, fmt(value), field, "ok")
        if assumption and assumption in self.assumed and self.assumed[assumption] is not None:
            return _row(label, _humanize(self.assumed[assumption], labels), field, "stimato")
        return _row(label, None, field, "da_rilevare")


def _label_fmt(labels: Dict[str, str]) -> Callable[[Any], str]:
    return lambda v: labels.get(v, _humanize(v))


def _cm(v: Any) -> str:
    return "Nessuno" if v == 0 else f"{_num(v)} cm"


# ---------------------------------------------------------------------------
# Sezioni
# ---------------------------------------------------------------------------
def _edificio(c: _Ctx) -> CenedSection:
    b = c.b
    first_unit = c.units[0] if c.units else None
    comune = b.comune or c.clima_comune.get("comune") or (first_unit.comune if first_unit else None)
    provincia = (b.provincia or c.clima_comune.get("provincia")
                 or (first_unit.provincia if first_unit else None))
    found = climate.find(comune, provincia) if comune else None
    zone_assumed = "comune" in c.assumed

    if b.zona_climatica:
        zona = _row("Zona climatica", b.zona_climatica, "servizioDatiClimatici@zonaClimatica", "ok")
    elif c.clima.get("zona"):
        zona = _row("Zona climatica", str(c.clima["zona"]), "servizioDatiClimatici@zonaClimatica",
                    "stimato" if zone_assumed else "ok")
    else:
        zona = _row("Zona climatica", c.legacy("climate_zone"), "servizioDatiClimatici@zonaClimatica", "ok")

    if b.gradi_giorno:
        gg = _row("Gradi giorno", str(b.gradi_giorno), "servizioDatiClimatici@gg", "ok")
    elif c.clima.get("gradi_giorno") is not None:
        gg = _row("Gradi giorno", _num(c.clima["gradi_giorno"]), "servizioDatiClimatici@gg",
                  "stimato" if zone_assumed or "gradi_giorno" in c.assumed else "ok")
    else:
        gg = _row("Gradi giorno", None, "servizioDatiClimatici@gg", "da_rilevare")

    rows = [
        _row("Comune", comune, "servizioDatiClimatici@codiceIstat", "ok"),
        _row("Codice ISTAT comune", found.istat if found else None, "datiEdificio@comune", "ok"),
        _row("Provincia", provincia, "datiEdificio@provincia", "ok"),
        _row("Indirizzo", c.legacy("address"), "datiEdificio@indirizzo", "ok"),
        zona,
        gg,
        c.pick("Anno di costruzione", "datiEdificio@annoCostruzione", b.anno_costruzione, str,
               "anno_costruzione"),
        c.pick("Tipologia edilizia", "campiApe@tipologiaEdilizia", b.tipologia,
               _label_fmt(TIPOLOGIA_LABEL), "tipologia", TIPOLOGIA_LABEL),
        c.pick("Posizione dell'alloggio", None, b.piano, _label_fmt(PIANO_LABEL), "piano", PIANO_LABEL),
        c.pick("Numero di piani", "datiEdificio@numeroPiani", b.numero_piani, str, "numero_piani"),
        c.pick("Lati esposti all'esterno", None, b.lati_esposti, str, "lati_esposti"),
        c.pick("Orientamento prevalente finestre", None, b.orientamento,
               _label_fmt(ORIENTAMENTO_LABEL), "orientamento", ORIENTAMENTO_LABEL),
        c.pick("Superficie utile", "geometria@superficieUtile", c.legacy("square_meters"),
               lambda v: f"{_num(v)} m²", "square_meters"),
        c.pick("Altezza media netta", "geometria@altezzaMediaNetta", c.legacy("avg_height"),
               lambda v: f"{_num(v, 2)} m", "avg_height"),
    ]
    return CenedSection(key="edificio", title="Edificio e localizzazione", rows=rows)


def _residential_use(categoria: Optional[str]) -> Optional[str]:
    if not categoria:
        return None
    match = re.fullmatch(r"A\s*/?\s*(\d{1,2})", categoria.strip().upper())
    if match and int(match.group(1)) in _RESIDENTIAL_A:
        return DEST_USO_RESIDENZIALE
    return None


def _subalterni(c: _Ctx) -> CenedSection:
    rows: List[CenedRow] = []
    for n, unit in enumerate(c.units or [CadastralUnit()], start=1):
        p = f"Unità {n} · "
        comune = unit.comune
        if comune and unit.codice_comune:
            comune = f"{comune} ({unit.codice_comune})"
        elif not comune:
            comune = unit.codice_comune
        rows += [
            _row(p + "Comune catastale", comune, "datiEdificio@comuneCatastale", "ok"),
            _row(p + "Provincia catastale", unit.provincia, "datiEdificio@provinciaCatastale", "ok"),
            _row(p + "Sezione urbana", unit.sezione_urbana, "datiEdificio@sezioneUrbana", "ok"),
            _row(p + "Foglio", unit.foglio, "datiEdificio@foglio", "ok"),
            _row(p + "Particella", unit.particella, "datiEdificio@particella", "ok"),
            _row(p + "Subalterno", unit.subalterno, "subalterno@subalternoNumero", "ok"),
            _row(p + "Categoria catastale", unit.categoria, None, "ok"),
            _row(p + "Piano", unit.piano, "datiEdificio@piano", "ok"),
            _row(p + "Indirizzo", unit.indirizzo, "datiEdificio@indirizzo", "ok"),
            _row(p + "Destinazione d'uso (suggerita)", _residential_use(unit.categoria),
                 "zona@destinazioneUso", "stimato"),
        ]
    return CenedSection(key="subalterni", title="Subalterni e dati catastali", rows=rows)


def _strutture(c: _Ctx) -> CenedSection:
    b = c.b
    rows = [
        c.pick("Muratura", "campiApe@tipoStruttura", b.muratura, _label_fmt(MURATURA_LABEL),
               "muratura", MURATURA_LABEL),
        c.pick("Spessore muri", None, b.spessore_muri or c.legacy("wall_thickness"),
               _label_fmt(SPESSORE_LABEL), "spessore_muri", SPESSORE_LABEL),
        c.pick("Isolamento pareti", None, b.isolamento_pareti_cm, _cm, "isolamento_pareti_cm"),
        c.pick("Copertura", "campiApe@tipoCopertura", b.copertura, _label_fmt(COPERTURA_LABEL),
               "copertura", COPERTURA_LABEL),
        c.pick("Isolamento copertura", None, b.isolamento_copertura_cm, _cm, "isolamento_copertura_cm"),
        c.pick("Pavimento verso", None, b.pavimento, _label_fmt(PAVIMENTO_LABEL),
               "pavimento", PAVIMENTO_LABEL),
        c.pick("Isolamento pavimento", None, b.isolamento_pavimento_cm, _cm, "isolamento_pavimento_cm"),
    ]
    return CenedSection(key="strutture_opache", title="Strutture opache", rows=rows)


def _serramenti(c: _Ctx) -> CenedSection:
    b = c.b
    rows = [
        c.pick("Telaio", "serramenti@tipoTelaio2", b.telaio or c.legacy("window_frame"),
               _label_fmt(TELAIO_LABEL), "telaio", TELAIO_LABEL),
        c.pick("Vetro", "serramenti@tipoVetro2", b.vetro or c.legacy("window_glass"),
               _label_fmt(VETRO_LABEL), "vetro", VETRO_LABEL),
        c.pick("Superficie finestrata", None, b.superficie_finestrata,
               lambda v: f"{_num(v)} m²", "superficie_finestrata"),
    ]
    return CenedSection(key="serramenti", title="Serramenti", rows=rows)


def _generator_code(c: _Ctx) -> Optional[str]:
    code = (c.b.generatore
            or _LEGACY_GENERATOR.get(c.legacy("generator_type") or "")
            or _LEGACY_HEATING.get(c.legacy("heating_type") or ""))
    if code:
        return code
    shown = c.assumed.get("generatore")
    if isinstance(shown, str):
        candidate = shown.strip().replace(" ", "_")
        if candidate in GENERATOR_LABEL:
            return candidate
    return None


def _impianti(c: _Ctx) -> CenedSection:
    b = c.b
    code = _generator_code(c)
    explicit_gen = (b.generatore or _LEGACY_GENERATOR.get(c.legacy("generator_type") or "")
                    or _LEGACY_HEATING.get(c.legacy("heating_type") or ""))
    type_field, gen_elem = GENERATOR_CENED.get(code, (None, None))

    def gen_attr(attr: str) -> Optional[str]:
        return f"{gen_elem}@{attr}" if gen_elem else None

    rows = [c.pick("Generatore", type_field, explicit_gen, _label_fmt(GENERATOR_LABEL),
                   "generatore", GENERATOR_LABEL)]
    if code is None or code in BOILERS:
        rows.append(c.pick("Combustibile", "gruppoGeneratoriCombustione@tipoVettoreEnergetico",
                           b.combustibile, _label_fmt(COMBUSTIBILE_LABEL), "combustibile",
                           COMBUSTIBILE_LABEL))
    potenza = b.potenza_kw if b.potenza_kw is not None else c.legacy("generator_power_kw")
    rows += [
        c.pick("Potenza nominale", gen_attr("phi_h_gn_out_n"), potenza, lambda v: f"{_num(v)} kW"),
        c.pick("Anno installazione generatore", gen_attr("annoInstallazioneImpianto"),
               b.anno_generatore or c.legacy("generator_year"), str, "anno_generatore"),
        c.pick("Tipo di impianto", None, b.impianto, _label_fmt(IMPIANTO_LABEL)),
        c.pick("Terminali di emissione", "tipoTerminale@tipoTerminale", b.terminali,
               _label_fmt(TERMINALI_LABEL), "terminali", TERMINALI_LABEL),
        c.pick("Regolazione", "tipoTerminale@tipoRegolazione", b.regolazione,
               _label_fmt(REGOLAZIONE_LABEL), "regolazione", REGOLAZIONE_LABEL),
        c.pick("Acqua calda sanitaria", "sistema@produzioneSeparata", b.acs,
               _label_fmt(ACS_LABEL), "acs", ACS_LABEL),
        c.pick("Solare termico", None, b.solare_termico, lambda v: "Sì" if v else "No"),
        c.pick("Raffrescamento", "zona@rafAttivo", b.raffrescamento,
               _label_fmt(RAFFRESCAMENTO_LABEL), "raffrescamento", RAFFRESCAMENTO_LABEL),
        c.pick("Fotovoltaico", "fotovoltaico@w_fv_punto", b.fotovoltaico_kwp,
               lambda v: "Assente" if v == 0 else f"{_num(v)} kWp"),
        c.pick("Ventilazione meccanica", "zona@ventAttivo", b.vmc, _label_fmt(VMC_LABEL)),
    ]
    return CenedSection(key="impianti", title="Impianti", rows=rows)


def _documenti(documents: Iterable[Any]) -> CenedSection:
    rows = []
    for doc in documents:
        when = doc.created_at.strftime("%d/%m/%Y %H:%M") if doc.created_at else None
        parts = [doc.filename]
        if doc.uploaded_by is not None:
            parts.append(f"caricato da {doc.uploaded_by.name}")
        if when:
            parts.append(f"il {when} (UTC)")
        rows.append(_row(DOCUMENT_KIND_LABEL.get(doc.kind, "Documento"), " — ".join(parts), None, "ok"))
    if not rows:
        rows.append(_row("Documenti catastali", None, None, "da_rilevare"))
    return CenedSection(key="documenti", title="Documenti allegati", rows=rows)


def build_cened_sheet(survey, documents: Sequence[Any] = ()) -> CenedSheet:
    """Scheda CENED del sopralluogo (pura: ``survey`` = modello ``Survey``,
    ``documents`` = lista di ``DocumentMeta``)."""
    c = _Ctx(survey)
    return CenedSheet(
        survey_id=getattr(survey, "id", None),
        generated_at=datetime.now(timezone.utc),
        disclaimer=DISCLAIMER,
        sections=[
            _edificio(c),
            _subalterni(c),
            _strutture(c),
            _serramenti(c),
            _impianti(c),
            _documenti(documents),
        ],
    )

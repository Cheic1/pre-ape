"""Stima della prestazione energetica (residenziale) per il pre-sopralluogo.

Metodo
------
* Classificazione come da DM 26/06/2015 (Linee guida APE, All. 1): indice
  EPgl,nren dell'immobile confrontato con EPgl,nren,rif,standard(2019/21)
  dell'edificio di riferimento (stessa geometria, trasmittanze dell'App. A del
  DM "requisiti minimi" per la zona climatica, dotazioni impiantistiche
  standard). Scala A4…G sul rapporto tra i due.
* Fabbisogni: bilancio stagionale semplificato derivato dalla UNI/TS 11300-1
  (dispersioni per trasmissione e ventilazione sui gradi giorno del DPR 412/93,
  apporti interni del prospetto residenziale, apporti solari, fattore di
  utilizzazione degli apporti secondo UNI EN ISO 13790).
* Impianti: rendimenti di emissione, regolazione, distribuzione e generazione
  come valori tipici della UNI/TS 11300-2/-4 per le tipologie selezionabili;
  ACS con il fabbisogno convenzionale (UNI/TS 11300-2:2019).
* Fattori di conversione in energia primaria (DM 26/06/2015 All. 1, Tab. 1).

È una **stima preliminare**: geometria e trasmittanze sono ricavate da pochi
dati di sopralluogo e da abachi per epoca costruttiva. Non sostituisce l'APE,
che va redatto da un certificatore con software conforme UNI/TS 11300.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from typing import Dict, List, Optional, Tuple

from . import climate
from .inputs import BuildingInputs

ENGINE_VERSION = "2026.10-1"

ENERGY_CLASS_LETTERS = ["A4", "A3", "A2", "A1", "B", "C", "D", "E", "F", "G"]
# Upper bound of EPgl,nren / EPgl,nren,rif,standard for each class (best → worst).
CLASS_UPPER_RATIO = [0.40, 0.60, 0.80, 1.00, 1.20, 1.50, 2.00, 2.60, 3.50, math.inf]

THETA_INT = 20.0       # °C, temperatura interna di progetto (DPR 412/93)
RHO_C_AIR = 0.34       # Wh/(m³K)
LAMBDA_INSULATION = 0.035  # W/(mK), isolante tipo (EPS/lana minerale)

# --- Fattori di conversione in energia primaria (DM 26/06/2015, All.1 Tab.1)
F_P = {  # vettore: (f_P,nren, f_P,ren)
    "metano": (1.05, 0.0),
    "gpl": (1.05, 0.0),
    "gasolio": (1.07, 0.0),
    "elettricita": (1.95, 0.47),
    "biomassa": (0.20, 0.80),
    "teleriscaldamento": (1.50, 0.0),
}
# Emissioni CO2 (kg/kWh di energia fornita), valori di riferimento nazionali
CO2 = {"metano": 0.1969, "gpl": 0.2253, "gasolio": 0.2642, "elettricita": 0.4332,
       "biomassa": 0.0, "teleriscaldamento": 0.25}
# Prezzi medi indicativi al consumatore (€/kWh di energia fornita)
PRICE = {"metano": 0.12, "gpl": 0.15, "gasolio": 0.155, "elettricita": 0.27,
         "biomassa": 0.08, "teleriscaldamento": 0.13}
# kWh per unità commerciale (per mostrare i consumi come in bolletta)
UNIT = {"metano": ("Smc", 9.6), "gpl": ("litri", 6.5), "gasolio": ("litri", 10.0),
        "elettricita": ("kWh", 1.0), "biomassa": ("kg", 4.8),
        "teleriscaldamento": ("kWh", 1.0)}

# --- Edificio di riferimento (DM 26/06/2015 requisiti minimi, App. A, 2019/21)
U_REF = {  # zona: (pareti, copertura, pavimento, finestre) W/m²K
    "A": (0.43, 0.35, 0.44, 3.00), "B": (0.43, 0.35, 0.44, 3.00),
    "C": (0.34, 0.33, 0.38, 2.20), "D": (0.29, 0.26, 0.29, 1.80),
    "E": (0.26, 0.22, 0.26, 1.40), "F": (0.24, 0.20, 0.24, 1.10),
}
REF_ETA_U_H, REF_ETA_GN_H = 0.81, 0.95  # gas, riscaldamento
REF_ETA_U_W, REF_ETA_GN_W = 0.70, 0.85  # gas, ACS
REF_ETA_U_C, REF_EER_C = 0.81, 2.50     # elettrico, raffrescamento
REF_G_WINDOW = 0.60

# --- Clima semplificato per zona
ORIENT_WINTER = {"sud": 1.45, "est_ovest": 0.95, "nord": 0.5, "misto": 1.0}
ORIENT_SUMMER = {"sud": 1.0, "est_ovest": 1.2, "nord": 0.75, "misto": 1.0}
# Fabbisogno ideale di raffrescamento di un alloggio tipo, kWh/(m² anno)
COOLING_BASE = {"A": 32, "B": 28, "C": 24, "D": 18, "E": 12, "F": 6}
PV_YIELD = {"A": 1450, "B": 1420, "C": 1380, "D": 1320, "E": 1220, "F": 1150}
PV_WINTER_SHARE = {"A": 0.25, "B": 0.27, "C": 0.30, "D": 0.33, "E": 0.36, "F": 0.38}
SOLAR_THERMAL_SHARE = {"A": 0.65, "B": 0.62, "C": 0.58, "D": 0.55, "E": 0.50, "F": 0.45}
PDC_ZONE_ADJ = {"A": 0.3, "B": 0.3, "C": 0.2, "D": 0.0, "E": -0.2, "F": -0.5}

# --- Abachi involucro (UNI/TS 11300-1 App. B, UNI 10351: valori tipici)
U_WALL = {  # muratura: (<30cm, 30-40cm, >40cm) senza isolamento
    "pietra": (2.6, 2.1, 1.7),
    "mattoni_pieni": (1.75, 1.35, 1.1),
    "mattoni_forati": (1.4, 1.15, 0.95),
    "blocchi_cemento": (2.0, 1.6, 1.3),
    "cemento_armato": (2.8, 2.3, 1.9),
    "laterizio_alveolato": (0.9, 0.6, 0.45),
    "legno": (0.35, 0.3, 0.25),
}
THICKNESS_INDEX = {"<30cm": 0, "30-40cm": 1, ">40cm": 2}
U_ROOF_BARE = 1.8    # solaio/copertura in laterocemento non isolato
U_FLOOR_BARE = 1.6
B_ROOF = {"terrazzo": 1.0, "sottotetto": 0.8, "falda_abitata": 1.0}
B_FLOOR = {"terreno": 0.5, "cantina": 0.5, "esterno": 1.0}
U_GLASS = {"Singolo": 5.7, "Doppio": 2.9, "Doppio basso emissivo": 1.3, "Triplo": 0.7}
G_GLASS = {"Singolo": 0.85, "Doppio": 0.75, "Doppio basso emissivo": 0.60, "Triplo": 0.50}
U_FRAME = {"Legno": 1.8, "PVC": 1.6, "Alluminio": 7.0, "Alluminio TT": 2.6, "Ferro": 7.0}

# --- Impianti (UNI/TS 11300-2/-4, valori tipici)
ETA_EMISSION = {"radiatori": 0.95, "pavimento": 0.98, "ventilconvettori": 0.96,
                "split": 0.97, "stufa": 0.90}
ETA_REGULATION = {"nessuna": 0.82, "termostato_ambiente": 0.93,
                  "valvole_termostatiche": 0.97, "climatica_valvole": 0.99}
HEAT_PUMPS = {"pompa_calore_aria_acqua", "pompa_calore_geotermica", "split_aria_aria"}
BOILERS = {"caldaia_tradizionale", "caldaia_condensazione"}
LOCAL_HEATERS = {"stufa_pellet", "stufa_legna", "split_aria_aria", "radiatori_elettrici"}

GENERATOR_LABEL = {
    "caldaia_tradizionale": "Caldaia tradizionale",
    "caldaia_condensazione": "Caldaia a condensazione",
    "pompa_calore_aria_acqua": "Pompa di calore aria-acqua",
    "pompa_calore_geotermica": "Pompa di calore geotermica",
    "split_aria_aria": "Pompa di calore aria-aria (split)",
    "caldaia_biomassa": "Caldaia a biomassa/pellet",
    "stufa_pellet": "Stufa a pellet",
    "stufa_legna": "Stufa/camino a legna",
    "teleriscaldamento": "Teleriscaldamento",
    "radiatori_elettrici": "Radiatori elettrici",
}

# Valori degli interventi (costi indicativi IVA inclusa)
COST_WALL_M2, COST_ROOF_M2, COST_FLOOR_M2, COST_WINDOW_M2 = 130.0, 110.0, 50.0, 650.0
COST_PV_KWP, COST_SOLAR_THERMAL, COST_CONDENSING = 1700.0, 4000.0, 3500.0

# Legacy values written by the first MVP wizard (flat survey columns).
_LEGACY_HEATING = {
    "Pompa di Calore": "pompa_calore_aria_acqua",
    "Condensazione": "caldaia_condensazione",
    "Pellet": "stufa_pellet",
    "Gas": "caldaia_tradizionale",
}
_LEGACY_GENERATOR = {
    "Caldaia a Condensazione": "caldaia_condensazione",
    "Caldaia Tradizionale": "caldaia_tradizionale",
    "Stufa a Pellet": "stufa_pellet",
    "Pompa Calore Aria-Aria": "split_aria_aria",
}


# ---------------------------------------------------------------------------
# Resolved inputs (defaults applied, every assumption recorded)
# ---------------------------------------------------------------------------
@dataclass
class Resolved:
    af: float
    height: float
    zone: str
    gg: int
    comune: Optional[dict]
    tipologia: str
    anno: int
    piano: str
    n_piani: int
    lati: int
    orientamento: str
    muratura: str
    spessore: str
    ins_wall: int
    copertura: str
    ins_roof: int
    pavimento: str
    ins_floor: int
    telaio: str
    vetro: str
    a_win_input: Optional[float]
    generatore: str
    combustibile: str
    anno_gen: int
    impianto: str
    terminali: str
    regolazione: str
    acs: str
    solare_termico: bool
    raffrescamento: str
    pv_kwp: float
    vmc: str
    assunzioni: List[dict] = field(default_factory=list)


def _default_insulation(year: int) -> Tuple[int, int, int]:
    """Spessore isolante tipico (pareti, copertura, pavimento) per epoca:
    L. 373/76, L. 10/91, D.Lgs. 192/05, DM 26/06/2015."""
    if year < 1977:
        return 0, 0, 0
    if year < 1992:
        return 2, 3, 0
    if year < 2006:
        return 4, 6, 2
    if year < 2016:
        return 6, 8, 4
    return 10, 14, 8


def resolve_inputs(
    b: BuildingInputs,
    *,
    square_meters: Optional[float] = None,
    avg_height: Optional[float] = None,
    address: Optional[str] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    legacy: Optional[dict] = None,
) -> Resolved:
    legacy = legacy or {}
    notes: List[dict] = []

    def assume(key: str, label: str, value, shown=None):
        notes.append({"campo": key, "descrizione": label, "valore": shown if shown is not None else value})
        return value

    af = square_meters if square_meters and square_meters > 0 else assume(
        "square_meters", "Superficie utile", 80.0, "80 m²")
    height = avg_height if avg_height and avg_height > 0 else assume(
        "avg_height", "Altezza netta interpiano", 2.7, "2,70 m")

    # Clima
    com = None
    if b.comune:
        com = climate.find(b.comune, b.provincia)
    if com is None:
        com = climate.resolve(address, latitude, longitude)
    if b.gradi_giorno:
        gg = b.gradi_giorno
        zone = b.zona_climatica or climate.zone_for_gg(gg)
    elif com is not None:
        gg, zone = com.gradi_giorno, com.zona
        if b.zona_climatica and b.zona_climatica != zone:
            zone = b.zona_climatica
            gg = climate.ZONE_DEFAULT_GG[zone]
    elif b.zona_climatica:
        zone = b.zona_climatica
        gg = assume("gradi_giorno", "Gradi giorno (valore tipico di zona)", climate.ZONE_DEFAULT_GG[zone])
    else:
        zone = assume("comune", "Zona climatica (comune non individuato)", "E", "zona E")
        gg = climate.ZONE_DEFAULT_GG["E"]

    tipologia = b.tipologia or assume("tipologia", "Tipologia edilizia", "appartamento", "appartamento")
    anno = b.anno_costruzione or assume("anno_costruzione", "Anno di costruzione", 1970)
    is_flat = tipologia == "appartamento"
    if is_flat:
        piano = b.piano or assume("piano", "Posizione dell'alloggio", "intermedio", "piano intermedio")
        n_piani = 1
    else:
        piano = "unico"
        n_piani = b.numero_piani or assume("numero_piani", "Numero di piani riscaldati", 2)
    default_sides = {"appartamento": 2, "schiera": 2, "bifamiliare": 3, "villetta": 4}[tipologia]
    lati = b.lati_esposti or assume("lati_esposti", "Lati esposti all'esterno", default_sides)
    orientamento = b.orientamento or assume("orientamento", "Orientamento prevalente finestre", "misto", "misto")

    def_muratura = ("mattoni_pieni" if anno < 1946 else
                    "mattoni_forati" if anno < 1992 else "laterizio_alveolato")
    muratura = b.muratura or assume("muratura", "Tipo di muratura", def_muratura, def_muratura.replace("_", " "))
    spessore = b.spessore_muri or legacy.get("wall_thickness") or assume(
        "spessore_muri", "Spessore muri", ">40cm" if anno < 1946 else "30-40cm")
    di_wall, di_roof, di_floor = _default_insulation(anno)
    ins_wall = b.isolamento_pareti_cm if b.isolamento_pareti_cm is not None else assume(
        "isolamento_pareti_cm", "Isolamento pareti (tipico dell'epoca)", di_wall, f"{di_wall} cm")
    copertura = b.copertura or ("sottotetto")
    ins_roof = b.isolamento_copertura_cm if b.isolamento_copertura_cm is not None else di_roof
    pavimento = b.pavimento or ("cantina" if is_flat else "terreno")
    ins_floor = b.isolamento_pavimento_cm if b.isolamento_pavimento_cm is not None else di_floor
    roof_exposed = piano in ("ultimo", "unico")
    floor_exposed = piano in ("terra", "unico")
    if roof_exposed and b.copertura is None:
        assume("copertura", "Tipo di copertura", "sottotetto", "sottotetto non riscaldato")
    if roof_exposed and b.isolamento_copertura_cm is None:
        assume("isolamento_copertura_cm", "Isolamento copertura (tipico dell'epoca)", di_roof, f"{di_roof} cm")
    if floor_exposed and b.pavimento is None:
        assume("pavimento", "Pavimento verso", pavimento, pavimento)
    if floor_exposed and b.isolamento_pavimento_cm is None:
        assume("isolamento_pavimento_cm", "Isolamento pavimento (tipico dell'epoca)", di_floor, f"{di_floor} cm")

    telaio = b.telaio or legacy.get("window_frame") or assume("telaio", "Telaio infissi", "Legno")
    if telaio not in U_FRAME:
        telaio = "Legno"
    vetro = b.vetro or legacy.get("window_glass") or assume(
        "vetro", "Vetro infissi", "Singolo" if anno < 1991 else "Doppio")
    if vetro not in U_GLASS:
        vetro = "Doppio"
    if b.superficie_finestrata is None:
        assume("superficie_finestrata", "Superficie finestrata (1/8 della superficie utile)",
               None, f"{af / 8:.1f} m²")

    generatore = b.generatore or _LEGACY_GENERATOR.get(legacy.get("generator_type") or "") \
        or _LEGACY_HEATING.get(legacy.get("heating_type") or "")
    if not generatore:
        generatore = assume("generatore", "Generatore di calore", "caldaia_tradizionale", "caldaia tradizionale")
    combustibile = b.combustibile or "metano"
    if generatore in BOILERS and b.combustibile is None:
        assume("combustibile", "Combustibile", "metano")
    anno_gen = b.anno_generatore or legacy.get("generator_year") or assume(
        "anno_generatore", "Anno installazione generatore", max(anno, 2005))
    impianto = b.impianto or ("autonomo")
    if generatore in LOCAL_HEATERS:
        def_term = "split" if generatore == "split_aria_aria" else "stufa" if generatore.startswith("stufa") else "radiatori"
    else:
        def_term = "radiatori"
    terminali = b.terminali or assume("terminali", "Terminali di emissione", def_term)
    regolazione = b.regolazione or assume("regolazione", "Regolazione", "termostato_ambiente", "termostato ambiente")
    acs = b.acs or assume("acs", "Produzione acqua calda sanitaria",
                          "boiler_elettrico" if generatore in LOCAL_HEATERS else "combinata",
                          "boiler elettrico" if generatore in LOCAL_HEATERS else "combinata col riscaldamento")
    raffrescamento = b.raffrescamento or assume("raffrescamento", "Raffrescamento", "nessuno")

    return Resolved(
        af=float(af), height=float(height), zone=zone, gg=int(gg),
        comune=com.as_dict() if com is not None else None,
        tipologia=tipologia, anno=int(anno), piano=piano, n_piani=int(n_piani), lati=int(lati),
        orientamento=orientamento, muratura=muratura, spessore=spessore, ins_wall=int(ins_wall),
        copertura=copertura, ins_roof=int(ins_roof), pavimento=pavimento, ins_floor=int(ins_floor),
        telaio=telaio, vetro=vetro, a_win_input=b.superficie_finestrata,
        generatore=generatore, combustibile=combustibile, anno_gen=int(anno_gen),
        impianto=impianto, terminali=terminali, regolazione=regolazione, acs=acs,
        solare_termico=bool(b.solare_termico), raffrescamento=raffrescamento,
        pv_kwp=float(b.fotovoltaico_kwp or 0.0), vmc=b.vmc or "nessuna",
        assunzioni=notes,
    )


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------
def _u_insulated(u0: float, cm: float) -> float:
    if cm <= 0:
        return u0
    return 1.0 / (1.0 / u0 + (cm / 100.0) / LAMBDA_INSULATION)


def window_u(telaio: str, vetro: str) -> float:
    """Uw ≈ 75% vetro + 25% telaio + ponte del distanziatore (UNI EN ISO 10077-1)."""
    spacer = 0.0 if vetro == "Singolo" else 0.2
    return 0.75 * U_GLASS[vetro] + 0.25 * U_FRAME[telaio] + spacer


@dataclass
class Geometry:
    af: float
    volume: float
    a_wall: float
    a_win: float
    a_roof: float
    a_floor: float
    a_stair: float = 0.0

    @property
    def a_disp(self) -> float:
        return self.a_wall + self.a_win + self.a_roof + self.a_floor

    def as_dict(self) -> dict:
        return {
            "superficie_utile": round(self.af, 1),
            "volume_netto": round(self.volume, 1),
            "pareti_opache": round(self.a_wall, 1),
            "superfici_finestrate": round(self.a_win, 1),
            "copertura": round(self.a_roof, 1),
            "pavimento": round(self.a_floor, 1),
            "verso_vano_scala": round(self.a_stair, 1),
            "superficie_disperdente": round(self.a_disp, 1),
        }


def geometry(r: Resolved) -> Geometry:
    a_plan = r.af / r.n_piani
    perimeter = 4.3 * math.sqrt(a_plan)  # pianta rettangolare ~1:1,5, lievemente articolata
    gross_wall = perimeter * (r.lati / 4.0) * (r.height + 0.3) * r.n_piani
    a_win = r.a_win_input if r.a_win_input is not None else r.af / 8.0
    a_win = min(a_win, 0.6 * gross_wall)
    return Geometry(
        af=r.af,
        volume=r.af * r.height,
        a_wall=max(gross_wall - a_win, 0.0),
        a_win=a_win,
        a_roof=a_plan if r.piano in ("ultimo", "unico") else 0.0,
        a_floor=a_plan if r.piano in ("terra", "unico") else 0.0,
        # alloggio in condominio: una porzione di perimetro confina col vano scala
        a_stair=0.15 * perimeter * (r.height + 0.3) if r.tipologia == "appartamento" else 0.0,
    )


@dataclass
class Envelope:
    u_wall: float
    u_roof: float
    u_floor: float
    u_win: float
    g_win: float
    thermal_bridge: float  # ΔU W/m²K sulle superfici opache

    def as_dict(self) -> dict:
        return {"pareti": round(self.u_wall, 2), "copertura": round(self.u_roof, 2),
                "pavimento": round(self.u_floor, 2), "finestre": round(self.u_win, 2)}


def envelope(r: Resolved) -> Envelope:
    u0 = U_WALL[r.muratura][THICKNESS_INDEX.get(r.spessore, 1)]
    u_wall = _u_insulated(u0, r.ins_wall)
    return Envelope(
        u_wall=u_wall,
        u_roof=_u_insulated(U_ROOF_BARE, r.ins_roof),
        u_floor=_u_insulated(U_FLOOR_BARE, r.ins_floor),
        u_win=window_u(r.telaio, r.vetro),
        g_win=G_GLASS[r.vetro],
        # ponti termici: forfettario più alto per pareti non isolate a cappotto
        thermal_bridge=0.05 if r.ins_wall >= 6 else 0.15,
    )


def _utilization(gains: float, losses: float, tau_h: float) -> float:
    """Fattore di utilizzazione degli apporti (UNI EN ISO 13790, metodo mensile)."""
    if losses <= 0:
        return 0.0
    gamma = gains / losses
    a = 1.0 + tau_h / 15.0
    if abs(gamma - 1.0) < 1e-6:
        return a / (a + 1.0)
    return (1.0 - gamma ** a) / (1.0 - gamma ** (a + 1.0))


# Profilo di temperatura esterna media mensile (UNI 10349, località tipo zona E),
# traslato per ogni comune in modo da riprodurne i gradi giorno DPR 412/93.
_T_PROFILE = [1.7, 4.2, 9.2, 13.0, 17.3, 21.6, 24.0, 23.1, 18.9, 13.3, 7.6, 3.1]
# Irraggiamento giornaliero su parete verticale (media degli orientamenti)
# a ~45°N, kWh/(m² giorno), scalato per latitudine tramite la zona climatica.
_SOLAR_PROFILE = [1.3, 1.8, 2.3, 2.6, 0, 0, 0, 0, 0, 2.0, 1.3, 1.0]
_SOLAR_ZONE_FACTOR = {"A": 1.35, "B": 1.3, "C": 1.2, "D": 1.12, "E": 1.0, "F": 0.95}
# Giorni di ciascun mese (gen…dic) compresi nel periodo di riscaldamento
# (DPR 412/93 art. 9; zona F: 5 ottobre – 22 aprile convenzionale).
SEASON_DAYS = {
    "A": [31, 28, 15, 0, 0, 0, 0, 0, 0, 0, 0, 31],
    "B": [31, 28, 31, 0, 0, 0, 0, 0, 0, 0, 0, 31],
    "C": [31, 28, 31, 0, 0, 0, 0, 0, 0, 0, 16, 31],
    "D": [31, 28, 31, 15, 0, 0, 0, 0, 0, 0, 30, 31],
    "E": [31, 28, 31, 15, 0, 0, 0, 0, 0, 17, 30, 31],
    "F": [31, 28, 31, 22, 0, 0, 0, 0, 0, 27, 30, 31],
}
# Ombreggiamento (ostruzioni urbane, aggetti, tende) × fattore di incidenza
SOLAR_SHADING = 0.6 * 0.9


def monthly_temperatures(zone: str, gg: float) -> List[float]:
    days = SEASON_DAYS[zone]
    tot = sum(days)
    raw = sum(d * (THETA_INT - t) for d, t in zip(days, _T_PROFILE))
    shift = (raw - gg) / tot
    return [t + shift for t in _T_PROFILE]


def heating_need(r: Resolved, geo: Geometry, env: Envelope, *, n_air: float,
                 b_roof: float, b_floor: float) -> dict:
    """Fabbisogno ideale per il riscaldamento, metodo mensile UNI/TS 11300-1."""
    tb = env.thermal_bridge
    h_tr = (
        geo.a_wall * (env.u_wall + tb)
        + geo.a_stair * (env.u_wall + tb) * 0.6  # verso vano scala non riscaldato
        + geo.a_win * env.u_win
        + geo.a_roof * (env.u_roof + tb) * b_roof
        + geo.a_floor * (env.u_floor + tb) * b_floor
    )
    h_ve = RHO_C_AIR * n_air * geo.volume
    phi_int = 450.0 if r.af > 120 else 7.987 * r.af - 0.0353 * r.af ** 2  # W, §13.1.1
    sol_unit = (geo.a_win * (1 - 0.25) * env.g_win * SOLAR_SHADING
                * _SOLAR_ZONE_FACTOR[r.zone] * ORIENT_WINTER[r.orientamento])
    c_m = (25.0 if r.muratura == "legno" else 45.0) * r.af  # Wh/K, capacità areica media
    tau = c_m / max(h_tr + h_ve, 1e-6)
    temps = monthly_temperatures(r.zone, r.gg)
    q_tr = q_ve = q_int = q_sol = q_nd = 0.0
    for days, t_e, sol in zip(SEASON_DAYS[r.zone], temps, _SOLAR_PROFILE):
        if days == 0:
            continue
        kh = max(THETA_INT - t_e, 0.0) * 24 * days / 1000
        m_tr, m_ve = h_tr * kh, h_ve * kh
        m_int = phi_int * 24 * days / 1000
        m_sol = sol_unit * sol * days
        eta = _utilization(m_int + m_sol, m_tr + m_ve, tau)
        q_tr += m_tr
        q_ve += m_ve
        q_int += m_int
        q_sol += m_sol
        q_nd += max(m_tr + m_ve - eta * (m_int + m_sol), 0.0)
    eta_avg = (q_tr + q_ve - q_nd) / (q_int + q_sol) if (q_int + q_sol) > 0 else 0.0
    return {"q_tr": q_tr, "q_ve": q_ve, "q_int": q_int, "q_sol": q_sol,
            "eta_gn": eta_avg, "q_h_nd": q_nd, "h_tr": h_tr, "h_ve": h_ve}


def dhw_need(af: float) -> float:
    """Fabbisogno ACS residenziale (UNI/TS 11300-2:2019), kWh/anno."""
    if af <= 35:
        litres = 50.0
    elif af <= 50:
        litres = 2.667 * af - 43.33
    elif af <= 200:
        litres = 1.067 * af + 36.67
    else:
        litres = 250.0
    return 1.162 * litres * (40 - 15) * 365 / 1000


def cooling_need(r: Resolved, geo: Geometry, *, reference: bool = False) -> float:
    ratio = geo.a_win / max(r.af, 1.0)
    window_factor = min(max(0.7 + 2.4 * ratio, 0.6), 1.8)
    orient = 1.0 if reference else ORIENT_SUMMER[r.orientamento]
    shading = 0.8 if reference else 1.0
    return COOLING_BASE[r.zone] * r.af * window_factor * orient * shading


def _heat_carrier(r: Resolved) -> str:
    g = r.generatore
    if g in BOILERS:
        return r.combustibile
    if g in HEAT_PUMPS or g == "radiatori_elettrici":
        return "elettricita"
    if g in ("caldaia_biomassa", "stufa_pellet", "stufa_legna"):
        return "biomassa"
    return "teleriscaldamento"


def generation_efficiency(r: Resolved) -> float:
    g, y, t = r.generatore, r.anno_gen, r.terminali
    if g == "caldaia_tradizionale":
        return 0.80 if y < 1990 else 0.86 if y < 2005 else 0.90
    if g == "caldaia_condensazione":
        return (1.02 if t == "pavimento" else 0.97) - (0.02 if y < 2010 else 0.0)
    if g == "pompa_calore_aria_acqua":
        base = {"pavimento": 3.6, "ventilconvettori": 3.2}.get(t, 2.7)
        return max(base + PDC_ZONE_ADJ[r.zone] - (0.4 if y < 2010 else 0.0), 1.5)
    if g == "pompa_calore_geotermica":
        base = {"pavimento": 4.2, "ventilconvettori": 3.8}.get(t, 3.3)
        return base - (0.3 if y < 2010 else 0.0)
    if g == "split_aria_aria":
        return max(3.6 + PDC_ZONE_ADJ[r.zone] - (0.6 if y < 2012 else 0.0), 1.5)
    if g == "caldaia_biomassa":
        return 0.85 if y >= 2010 else 0.78
    if g == "stufa_pellet":
        return 0.87 if y >= 2010 else 0.82
    if g == "stufa_legna":
        return 0.70 if y >= 2000 else 0.55
    if g == "teleriscaldamento":
        return 0.97
    return 1.0  # radiatori elettrici (effetto Joule)


def heating_subsystems(r: Resolved) -> float:
    eta_e = ETA_EMISSION[r.terminali]
    eta_rg = ETA_REGULATION[r.regolazione]
    if r.generatore in LOCAL_HEATERS:
        eta_d = 1.0
    elif r.impianto == "centralizzato":
        eta_d = 0.88 if r.anno < 1977 else 0.92
    else:
        eta_d = 0.97
    return eta_e * eta_rg * eta_d


def _dhw_system(r: Resolved) -> Tuple[str, float, float, List[str]]:
    """(vettore, rendimento di generazione o COP, rendimento d'utenza, note)."""
    notes: List[str] = []
    mode = r.acs
    if mode == "combinata":
        g = r.generatore
        if g in BOILERS:
            eta = 0.93 if g == "caldaia_condensazione" else generation_efficiency(r) - 0.05
            return r.combustibile, eta, 0.85, notes
        if g in ("pompa_calore_aria_acqua", "pompa_calore_geotermica"):
            return "elettricita", 2.6 if g == "pompa_calore_aria_acqua" else 3.0, 0.85, notes
        if g == "caldaia_biomassa":
            return "biomassa", 0.80, 0.85, notes
        if g == "teleriscaldamento":
            return "teleriscaldamento", 0.95, 0.85, notes
        notes.append("Il generatore scelto non produce ACS: considerato un boiler elettrico.")
        mode = "boiler_elettrico"
    if mode == "boiler_elettrico":
        return "elettricita", 1.0, 0.75, notes
    if mode == "scaldabagno_gas":
        fuel = r.combustibile if r.combustibile in ("metano", "gpl") else "metano"
        return fuel, 0.80, 0.95, notes
    return "elettricita", 2.8, 0.85, notes  # pompa di calore dedicata ACS


def _class_for_ratio(ratio: float) -> str:
    for letter, upper in zip(ENERGY_CLASS_LETTERS, CLASS_UPPER_RATIO):
        if ratio <= upper:
            return letter
    return "G"


def score_for_ratio(ratio: float) -> float:
    """0–100 (100 = A4), coerente con la classe: round(score/100*9) = indice
    della classe contato da G. Serve al tachimetro del client."""
    idx_best = ENERGY_CLASS_LETTERS.index(_class_for_ratio(ratio))
    hi = CLASS_UPPER_RATIO[idx_best]
    lo = CLASS_UPPER_RATIO[idx_best - 1] if idx_best > 0 else 0.0
    if math.isinf(hi):
        frac = min(max((5.0 - ratio) / 1.5, 0.0), 1.0)
    else:
        frac = min(max((hi - ratio) / (hi - lo), 0.0), 1.0)
    k = 9 - idx_best  # G = 0 … A4 = 9
    score = (k - 0.5 + 0.001 + 0.998 * frac) / 9 * 100
    return round(min(max(score, 0.0), 100.0), 2)


# ---------------------------------------------------------------------------
# Full calculation
# ---------------------------------------------------------------------------
def _evaluate(r: Resolved) -> dict:
    geo = geometry(r)
    env = envelope(r)
    zone = r.zone

    # Ventilazione
    if r.vmc == "recupero":
        n_air, fan_flow, sfp = 0.4 * 0.25 + 0.1, 0.4 * geo.volume, 0.45
    elif r.vmc == "semplice":
        n_air, fan_flow, sfp = 0.5, 0.4 * geo.volume, 0.25
    else:
        n_air, fan_flow, sfp = 0.3, 0.0, 0.0
    e_v = fan_flow * sfp * 8760 / 1000  # kWh elettrici ventilatori

    heat = heating_need(r, geo, env, n_air=n_air,
                        b_roof=B_ROOF[r.copertura], b_floor=B_FLOOR[r.pavimento])
    q_h_nd = heat["q_h_nd"]

    # Riscaldamento
    eta_u = heating_subsystems(r)
    eta_gn = generation_efficiency(r)
    carrier_h = _heat_carrier(r)
    delivered: Dict[str, float] = {}

    def add(carrier: str, kwh: float):
        delivered[carrier] = delivered.get(carrier, 0.0) + kwh

    q_h_out = q_h_nd / eta_u
    e_h = q_h_out / eta_gn
    ren_ambient = q_h_out - e_h if r.generatore in HEAT_PUMPS else 0.0
    hydronic = r.terminali in ("radiatori", "pavimento", "ventilconvettori") and r.generatore not in HEAT_PUMPS
    aux_h = q_h_out * (0.015 if hydronic else 0.02 if r.generatore == "stufa_pellet" else 0.0)
    add(carrier_h, e_h)
    el_heating = (e_h if carrier_h == "elettricita" else 0.0) + aux_h

    # ACS
    q_w_nd = dhw_need(r.af)
    carrier_w, eta_w_gn, eta_w_u, dhw_notes = _dhw_system(r)
    solar_share = SOLAR_THERMAL_SHARE[zone] if r.solare_termico else 0.0
    q_w_out = q_w_nd * (1 - solar_share) / eta_w_u
    e_w = q_w_out / eta_w_gn
    ren_solar = q_w_nd * solar_share
    is_dhw_hp = carrier_w == "elettricita" and eta_w_gn > 1.0
    ren_ambient += (q_w_out - e_w) if is_dhw_hp else 0.0
    add(carrier_w, e_w)
    aux_w = 50.0 if r.solare_termico else 0.0
    el_other = (e_w if carrier_w == "elettricita" else 0.0) + aux_w

    # Raffrescamento
    q_c_nd, e_c = 0.0, 0.0
    if r.raffrescamento != "nessuno":
        q_c_nd = cooling_need(r, geo)
        seer = 4.2 if r.raffrescamento == "split" else 3.5
        if r.raffrescamento == "split" and r.generatore == "split_aria_aria" and r.anno_gen < 2012:
            seer = 3.0
        e_c = q_c_nd / (0.90 * seer)
        el_other += e_c
    el_other += e_v
    add("elettricita", aux_h + aux_w + e_c + e_v)

    # Fotovoltaico: compensazione mensile semplificata (solo usi dell'edificio)
    pv_prod = r.pv_kwp * PV_YIELD[zone]
    winter = pv_prod * PV_WINTER_SHARE[zone]
    pv_used_h = min(el_heating, 0.5 * winter)
    pv_used_o = min(el_other, 0.6 * (pv_prod - pv_used_h))
    pv_used = pv_used_h + pv_used_o

    # Energia primaria
    def ep(carrier: str, kwh: float) -> Tuple[float, float]:
        f_nren, f_ren = F_P[carrier]
        return kwh * f_nren, kwh * f_ren

    nren = ren = 0.0
    for carrier, kwh in delivered.items():
        a, b = ep(carrier, kwh)
        nren += a
        ren += b
    nren -= pv_used * F_P["elettricita"][0]
    ren += pv_used * (1.0 - F_P["elettricita"][1]) + ren_ambient + ren_solar

    af = r.af
    ep_h_nren = (ep(carrier_h, e_h)[0] + aux_h * F_P["elettricita"][0]) / af
    ep_w_nren = (ep(carrier_w, e_w)[0] + aux_w * F_P["elettricita"][0]) / af
    ep_c_nren = e_c * F_P["elettricita"][0] / af
    ep_v_nren = e_v * F_P["elettricita"][0] / af
    ep_gl_nren = max(nren / af, 0.0)
    ep_gl_ren = ren / af

    # Edificio di riferimento (DM 26/06/2015, dotazioni standard 2019/21)
    uw, ur, uf, uwin = U_REF[zone]
    env_ref = Envelope(u_wall=uw, u_roof=ur, u_floor=uf, u_win=uwin,
                       g_win=REF_G_WINDOW, thermal_bridge=0.0)
    r_ref = replace(r, orientamento="misto")
    heat_ref = heating_need(r_ref, geo, env_ref, n_air=0.3,
                            b_roof=B_ROOF[r.copertura], b_floor=B_FLOOR[r.pavimento])
    q_h_nd_lim = heat_ref["q_h_nd"]
    ref_h = q_h_nd_lim / (REF_ETA_U_H * REF_ETA_GN_H) * F_P["metano"][0]
    ref_w = q_w_nd / (REF_ETA_U_W * REF_ETA_GN_W) * F_P["metano"][0]
    ref_c = 0.0
    if r.raffrescamento != "nessuno":
        ref_c = cooling_need(r, geo, reference=True) / (REF_ETA_U_C * REF_EER_C) * F_P["elettricita"][0]
    ep_ref = (ref_h + ref_w + ref_c) / af

    ratio = ep_gl_nren / ep_ref if ep_ref > 0 else 0.0
    energy_class = _class_for_ratio(ratio)
    h_ratio = q_h_nd / q_h_nd_lim if q_h_nd_lim > 0 else 0.0
    winter_quality = "alta" if h_ratio <= 1.0 else "media" if h_ratio <= 1.7 else "bassa"

    grid_el = max(delivered.get("elettricita", 0.0) - pv_used, 0.0)
    consumption = []
    cost = co2 = 0.0
    for carrier, kwh in sorted(delivered.items()):
        billed = grid_el if carrier == "elettricita" else kwh
        unit, per_unit = UNIT[carrier]
        consumption.append({
            "vettore": carrier,
            "kwh": round(billed),
            "quantita": round(billed / per_unit),
            "unita": unit,
            "costo_eur": round(billed * PRICE[carrier]),
        })
        cost += billed * PRICE[carrier]
        co2 += billed * CO2[carrier]

    return {
        "geo": geo, "env": env, "heat": heat, "ratio": ratio,
        "energy_class": energy_class,
        "ep": {
            "h_nd": round(q_h_nd / af, 1),
            "w_nd": round(q_w_nd / af, 1),
            "c_nd": round(q_c_nd / af, 1),
            "h_nren": round(ep_h_nren, 1),
            "w_nren": round(ep_w_nren, 1),
            "c_nren": round(ep_c_nren, 1),
            "v_nren": round(ep_v_nren, 1),
            "fv_nren": round(-pv_used * F_P["elettricita"][0] / af, 1),
            "gl_nren": round(ep_gl_nren, 1),
            "gl_ren": round(ep_gl_ren, 1),
            "gl_tot": round(ep_gl_nren + ep_gl_ren, 1),
        },
        "reference": {
            "gl_nren_rif_standard": round(ep_ref, 1),
            "h_nd_lim": round(q_h_nd_lim / af, 1),
        },
        "winter_quality": winter_quality,
        "consumption": consumption,
        "cost": cost,
        "co2": co2,
        "pv": {"produzione_kwh": round(pv_prod), "autoconsumo_kwh": round(pv_used)},
        "system": {
            "eta_h_u": round(eta_u, 3),
            "eta_h_gn": round(eta_gn, 2),
            "eta_h_globale": round(eta_u * eta_gn, 2),
            "vettore_riscaldamento": carrier_h,
            "vettore_acs": carrier_w,
            "quota_solare_acs": solar_share,
        },
        "notes": dhw_notes,
    }


def _improvements(r: Resolved, base: dict) -> List[dict]:
    geo: Geometry = base["geo"]
    env: Envelope = base["env"]
    zone = r.zone
    uw_ref, ur_ref, uf_ref, uwin_ref = U_REF[zone]
    roof_access = r.piano in ("ultimo", "unico")
    options: List[Tuple[str, str, Resolved, float]] = []

    if env.u_wall > uw_ref + 0.05 and geo.a_wall > 0:
        cm = 12 if zone in ("E", "F") else 10 if zone == "D" else 8
        options.append(("cappotto", f"Isolamento a cappotto delle pareti ({cm} cm)",
                        replace(r, ins_wall=r.ins_wall + cm), geo.a_wall * COST_WALL_M2))
    if roof_access and geo.a_roof > 0 and env.u_roof > ur_ref + 0.05:
        cm = 16 if zone in ("E", "F") else 12
        options.append(("copertura", f"Isolamento della copertura/sottotetto ({cm} cm)",
                        replace(r, ins_roof=r.ins_roof + cm), geo.a_roof * COST_ROOF_M2))
    if geo.a_floor > 0 and env.u_floor > uf_ref + 0.05:
        options.append(("pavimento", "Isolamento del solaio verso terreno/cantina (8 cm)",
                        replace(r, ins_floor=r.ins_floor + 8), geo.a_floor * COST_FLOOR_M2))
    if env.u_win > uwin_ref + 0.2:
        vetro = "Triplo" if zone == "F" else "Doppio basso emissivo"
        options.append(("infissi", f"Sostituzione infissi (PVC, vetro {vetro.lower()})",
                        replace(r, telaio="PVC", vetro=vetro), geo.a_win * COST_WINDOW_M2))
    if r.generatore not in HEAT_PUMPS:
        term = r.terminali if r.terminali in ("radiatori", "pavimento", "ventilconvettori") else "radiatori"
        options.append(("pompa_calore", "Pompa di calore aria-acqua in sostituzione del generatore",
                        replace(r, generatore="pompa_calore_aria_acqua", anno_gen=2026, terminali=term,
                                regolazione="valvole_termostatiche",
                                acs="combinata" if r.acs in ("combinata", "boiler_elettrico") else r.acs),
                        min(5000 + 100 * r.af, 25000)))
    if r.generatore == "caldaia_tradizionale":
        options.append(("condensazione", "Caldaia a condensazione + valvole termostatiche",
                        replace(r, generatore="caldaia_condensazione", anno_gen=2026,
                                regolazione="valvole_termostatiche"), COST_CONDENSING))
    elif r.regolazione in ("nessuna", "termostato_ambiente") and r.terminali == "radiatori":
        options.append(("valvole", "Valvole termostatiche e regolazione climatica",
                        replace(r, regolazione="climatica_valvole"), 80 * max(r.af / 12, 4)))
    if roof_access and r.pv_kwp <= 0:
        kwp = 3.0 if r.tipologia == "appartamento" else min(6.0, max(3.0, round(r.af / 30)))
        options.append(("fotovoltaico", f"Impianto fotovoltaico da {kwp:g} kWp",
                        replace(r, pv_kwp=kwp), kwp * COST_PV_KWP))
    if roof_access and not r.solare_termico and r.acs != "pompa_calore_acs":
        options.append(("solare_termico", "Solare termico per l'acqua calda sanitaria",
                        replace(r, solare_termico=True), COST_SOLAR_THERMAL))

    out: List[dict] = []
    base_ep, base_cost = base["ep"]["gl_nren"], base["cost"]
    for key, label, variant, invest in options:
        res = _evaluate(variant)
        saving_ep = base_ep - res["ep"]["gl_nren"]
        if saving_ep <= 0.5:
            continue
        saving_eur = base_cost - res["cost"]
        out.append({
            "codice": key,
            "intervento": label,
            "classe": res["energy_class"],
            "ep_gl_nren": res["ep"]["gl_nren"],
            "riduzione_ep_pct": round(100 * saving_ep / base_ep, 1) if base_ep else 0.0,
            "risparmio_annuo_eur": round(saving_eur),
            "investimento_eur": round(invest, -2),
            "tempo_ritorno_anni": round(invest / saving_eur, 1) if saving_eur > 50 else None,
            "_variant": variant,
        })
    out.sort(key=lambda x: -x["riduzione_ep_pct"])

    # Scenario combinato: involucro + impianto migliore + rinnovabili
    if len(out) >= 2:
        combo = r
        invest = 0.0
        chosen = []
        has_hp = any(o["codice"] == "pompa_calore" for o in out)
        for o in out:
            if o["codice"] in ("condensazione", "valvole") and has_hp:
                continue
            v = o["_variant"]
            combo = _merge(combo, v, r)
            invest += o["investimento_eur"]
            chosen.append(o["codice"])
        res = _evaluate(combo)
        saving_ep = base_ep - res["ep"]["gl_nren"]
        saving_eur = base_cost - res["cost"]
        out.append({
            "codice": "riqualificazione_globale",
            "intervento": "Riqualificazione completa (" + ", ".join(chosen) + ")",
            "classe": res["energy_class"],
            "ep_gl_nren": res["ep"]["gl_nren"],
            "riduzione_ep_pct": round(100 * saving_ep / base_ep, 1) if base_ep else 0.0,
            "risparmio_annuo_eur": round(saving_eur),
            "investimento_eur": round(invest, -2),
            "tempo_ritorno_anni": round(invest / saving_eur, 1) if saving_eur > 50 else None,
            "classi_guadagnate": _class_gain(base["energy_class"], res["energy_class"]),
        })
    for o in out:
        o.pop("_variant", None)
        o.setdefault("classi_guadagnate", _class_gain(base["energy_class"], o["classe"]))
    return out


def _merge(acc: Resolved, variant: Resolved, original: Resolved) -> Resolved:
    """Apply the fields ``variant`` changed w.r.t. ``original`` on top of ``acc``."""
    changes = {k: getattr(variant, k) for k in variant.__dataclass_fields__
               if k != "assunzioni" and getattr(variant, k) != getattr(original, k)}
    return replace(acc, **changes)


def _class_gain(before: str, after: str) -> int:
    return ENERGY_CLASS_LETTERS.index(before) - ENERGY_CLASS_LETTERS.index(after)


def compute(
    building: Optional[BuildingInputs] = None,
    *,
    square_meters: Optional[float] = None,
    avg_height: Optional[float] = None,
    address: Optional[str] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    legacy: Optional[dict] = None,
    with_improvements: bool = True,
) -> dict:
    r = resolve_inputs(
        building or BuildingInputs(),
        square_meters=square_meters, avg_height=avg_height, address=address,
        latitude=latitude, longitude=longitude, legacy=legacy,
    )
    base = _evaluate(r)
    result = {
        "versione": ENGINE_VERSION,
        "metodo": ("Stima preliminare: classificazione DM 26/06/2015 su edificio di riferimento, "
                   "fabbisogni con bilancio stagionale semplificato UNI/TS 11300. "
                   "Non sostituisce l'APE."),
        "classe": base["energy_class"],
        "punteggio": score_for_ratio(base["ratio"]),
        "rapporto_ep": round(base["ratio"], 3),
        "clima": {
            "zona": r.zone,
            "gradi_giorno": r.gg,
            "giorni_riscaldamento": climate.HEATING_DAYS[r.zone],
            "comune": r.comune,
        },
        "geometria": base["geo"].as_dict(),
        "trasmittanze": base["env"].as_dict(),
        "trasmittanze_limite": dict(zip(("pareti", "copertura", "pavimento", "finestre"), U_REF[r.zone])),
        "fabbisogni": {k: round(v) for k, v in base["heat"].items() if k.startswith("q_")},
        "ep": base["ep"],
        "riferimento": base["reference"],
        "qualita_involucro_invernale": base["winter_quality"],
        "impianto": {**base["system"], "generatore": GENERATOR_LABEL[r.generatore]},
        "consumi": base["consumption"],
        "costo_annuo_eur": round(base["cost"]),
        "co2_kg_anno": round(base["co2"]),
        "co2_kg_m2": round(base["co2"] / r.af, 1),
        "fotovoltaico": base["pv"],
        "assunzioni": r.assunzioni,
        "note": base["notes"],
    }
    result["interventi"] = _improvements(r, base) if with_improvements else []
    return result

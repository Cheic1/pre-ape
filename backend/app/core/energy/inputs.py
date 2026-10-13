"""Energy-model inputs collected during the pre-survey (``survey.building``).

Every field is optional: what the technician leaves blank is filled with a
documented default (by construction year, building type, climate zone…) and
reported back in ``EnergyResult.assunzioni`` so it can be completed later.
"""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field

Tipologia = Literal["appartamento", "villetta", "bifamiliare", "schiera"]
Piano = Literal["terra", "intermedio", "ultimo", "unico"]
Orientamento = Literal["sud", "est_ovest", "nord", "misto"]
Muratura = Literal[
    "pietra", "mattoni_pieni", "mattoni_forati", "blocchi_cemento",
    "cemento_armato", "laterizio_alveolato", "legno",
]
Spessore = Literal["<30cm", "30-40cm", ">40cm"]
Copertura = Literal["terrazzo", "sottotetto", "falda_abitata"]
Pavimento = Literal["terreno", "cantina", "esterno"]
Telaio = Literal["Legno", "PVC", "Alluminio", "Alluminio TT", "Ferro"]
Vetro = Literal["Singolo", "Doppio", "Doppio basso emissivo", "Triplo"]
Generatore = Literal[
    "caldaia_tradizionale", "caldaia_condensazione", "pompa_calore_aria_acqua",
    "pompa_calore_geotermica", "split_aria_aria", "caldaia_biomassa",
    "stufa_pellet", "stufa_legna", "teleriscaldamento", "radiatori_elettrici",
]
Combustibile = Literal["metano", "gpl", "gasolio"]
Impianto = Literal["autonomo", "centralizzato"]
Terminali = Literal["radiatori", "pavimento", "ventilconvettori", "split", "stufa"]
Regolazione = Literal["nessuna", "termostato_ambiente", "valvole_termostatiche", "climatica_valvole"]
Acs = Literal["combinata", "boiler_elettrico", "scaldabagno_gas", "pompa_calore_acs"]
Raffrescamento = Literal["nessuno", "split", "pompa_calore"]
Vmc = Literal["nessuna", "semplice", "recupero"]
Zona = Literal["A", "B", "C", "D", "E", "F"]


class BuildingInputs(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # Localizzazione (zona/GG sovrascrivono il dato del comune)
    comune: Optional[str] = Field(default=None, max_length=120)
    provincia: Optional[str] = Field(default=None, max_length=2)
    zona_climatica: Optional[Zona] = None
    gradi_giorno: Optional[int] = Field(default=None, ge=0, le=6000)

    # Edificio
    tipologia: Optional[Tipologia] = None
    anno_costruzione: Optional[int] = Field(default=None, ge=1800, le=2100)
    piano: Optional[Piano] = None
    numero_piani: Optional[int] = Field(default=None, ge=1, le=6)
    lati_esposti: Optional[int] = Field(default=None, ge=1, le=4)
    orientamento: Optional[Orientamento] = None

    # Involucro
    muratura: Optional[Muratura] = None
    spessore_muri: Optional[Spessore] = None
    isolamento_pareti_cm: Optional[int] = Field(default=None, ge=0, le=40)
    copertura: Optional[Copertura] = None
    isolamento_copertura_cm: Optional[int] = Field(default=None, ge=0, le=40)
    pavimento: Optional[Pavimento] = None
    isolamento_pavimento_cm: Optional[int] = Field(default=None, ge=0, le=40)
    telaio: Optional[Telaio] = None
    vetro: Optional[Vetro] = None
    superficie_finestrata: Optional[float] = Field(default=None, ge=0, le=2000)

    # Impianti
    generatore: Optional[Generatore] = None
    combustibile: Optional[Combustibile] = None
    anno_generatore: Optional[int] = Field(default=None, ge=1950, le=2100)
    potenza_kw: Optional[float] = Field(default=None, ge=0, le=2000)
    impianto: Optional[Impianto] = None
    terminali: Optional[Terminali] = None
    regolazione: Optional[Regolazione] = None
    acs: Optional[Acs] = None
    solare_termico: Optional[bool] = None
    raffrescamento: Optional[Raffrescamento] = None
    fotovoltaico_kwp: Optional[float] = Field(default=None, ge=0, le=200)
    vmc: Optional[Vmc] = None

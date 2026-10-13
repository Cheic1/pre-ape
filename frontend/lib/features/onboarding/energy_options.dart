/// Valori ammessi per gli input del calcolo energetico.
///
/// I `value` sono quelli dello schema `BuildingInputs` del backend
/// (`backend/app/core/energy/inputs.py`, `extra="forbid"`, Literal): vanno
/// tenuti allineati, il server rifiuta con 422 qualunque altro valore.
library;

import 'package:flutter/material.dart';

class Opt {
  const Opt(this.value, this.label, {this.hint, this.icon});

  final Object value;
  final String label;
  final String? hint;
  final IconData? icon;
}

const tipologiaOpts = [
  Opt('appartamento', 'Appartamento', icon: Icons.apartment),
  Opt('villetta', 'Villetta', hint: 'isolata', icon: Icons.house),
  Opt('bifamiliare', 'Bifamiliare', icon: Icons.holiday_village),
  Opt('schiera', 'A schiera', icon: Icons.home_work),
];

const pianoOpts = [
  Opt('terra', 'Piano terra'),
  Opt('intermedio', 'Intermedio'),
  Opt('ultimo', 'Ultimo piano'),
  Opt('unico', 'Cielo-terra'),
];

const orientamentoOpts = [
  Opt('sud', 'Sud'),
  Opt('est_ovest', 'Est / Ovest'),
  Opt('nord', 'Nord'),
  Opt('misto', 'Misto'),
];

const latiOpts = [Opt(1, '1'), Opt(2, '2'), Opt(3, '3'), Opt(4, '4')];
const pianiOpts = [Opt(1, '1'), Opt(2, '2'), Opt(3, '3'), Opt(4, '4')];

const murOpts = [
  Opt('pietra', 'Pietra'),
  Opt('mattoni_pieni', 'Mattoni pieni'),
  Opt('mattoni_forati', 'Forati / cassa vuota'),
  Opt('blocchi_cemento', 'Blocchi cemento'),
  Opt('cemento_armato', 'Pannelli c.a.'),
  Opt('laterizio_alveolato', 'Laterizio alveolato'),
  Opt('legno', 'Legno'),
];

const spessoreOpts = [
  Opt('<30cm', 'Sottile', hint: '< 30 cm'),
  Opt('30-40cm', 'Medio', hint: '30 – 40 cm'),
  Opt('>40cm', 'Spesso', hint: '> 40 cm'),
];

const isolamentoOpts = [
  Opt(0, 'Nessuno'),
  Opt(3, '3 cm'),
  Opt(6, '6 cm'),
  Opt(10, '10 cm'),
  Opt(14, '14+ cm'),
];

const coperturaOpts = [
  Opt('sottotetto', 'Sottotetto freddo'),
  Opt('terrazzo', 'Terrazzo / piana'),
  Opt('falda_abitata', 'Mansarda abitata'),
];

const pavimentoOpts = [
  Opt('cantina', 'Cantina / garage'),
  Opt('terreno', 'Contro terra'),
  Opt('esterno', 'Su pilotis / portico'),
];

const telaioOpts = [
  Opt('Legno', 'Legno'),
  Opt('PVC', 'PVC'),
  Opt('Alluminio TT', 'Alluminio TT', hint: 'taglio termico'),
  Opt('Alluminio', 'Alluminio'),
  Opt('Ferro', 'Ferro'),
];

const vetroOpts = [
  Opt('Singolo', 'Singolo'),
  Opt('Doppio', 'Doppio'),
  Opt('Doppio basso emissivo', 'Doppio basso-emissivo'),
  Opt('Triplo', 'Triplo'),
];

const generatoreOpts = [
  Opt('caldaia_tradizionale', 'Caldaia tradizionale', icon: Icons.local_fire_department),
  Opt('caldaia_condensazione', 'Caldaia a condensazione', icon: Icons.whatshot),
  Opt('pompa_calore_aria_acqua', 'Pompa di calore aria-acqua', icon: Icons.heat_pump),
  Opt('pompa_calore_geotermica', 'Pompa di calore geotermica', icon: Icons.terrain),
  Opt('split_aria_aria', 'Climatizzatori (split)', icon: Icons.ac_unit),
  Opt('caldaia_biomassa', 'Caldaia a pellet/biomassa', icon: Icons.forest),
  Opt('stufa_pellet', 'Stufa a pellet', icon: Icons.fireplace),
  Opt('stufa_legna', 'Stufa / camino a legna', icon: Icons.fireplace_outlined),
  Opt('teleriscaldamento', 'Teleriscaldamento', icon: Icons.hub),
  Opt('radiatori_elettrici', 'Radiatori elettrici', icon: Icons.electric_bolt),
];

const combustibileOpts = [
  Opt('metano', 'Metano'),
  Opt('gpl', 'GPL'),
  Opt('gasolio', 'Gasolio'),
];

const impiantoOpts = [
  Opt('autonomo', 'Autonomo'),
  Opt('centralizzato', 'Centralizzato'),
];

const terminaliOpts = [
  Opt('radiatori', 'Radiatori'),
  Opt('pavimento', 'Pannelli a pavimento'),
  Opt('ventilconvettori', 'Ventilconvettori'),
  Opt('split', 'Split'),
  Opt('stufa', 'Stufa / locale'),
];

const regolazioneOpts = [
  Opt('nessuna', 'Nessuna', hint: 'solo caldaia'),
  Opt('termostato_ambiente', 'Termostato ambiente'),
  Opt('valvole_termostatiche', 'Valvole termostatiche'),
  Opt('climatica_valvole', 'Climatica + valvole'),
];

const acsOpts = [
  Opt('combinata', 'Dal generatore', hint: 'combinata'),
  Opt('boiler_elettrico', 'Boiler elettrico'),
  Opt('scaldabagno_gas', 'Scaldabagno a gas'),
  Opt('pompa_calore_acs', 'Pompa di calore ACS'),
];

const raffrescamentoOpts = [
  Opt('nessuno', 'Nessuno'),
  Opt('split', 'Split / climatizzatori'),
  Opt('pompa_calore', 'Pompa di calore'),
];

const vmcOpts = [
  Opt('nessuna', 'Naturale'),
  Opt('semplice', 'VMC semplice flusso'),
  Opt('recupero', 'VMC con recupero'),
];

const zonaOpts = [
  Opt('A', 'A'), Opt('B', 'B'), Opt('C', 'C'),
  Opt('D', 'D'), Opt('E', 'E'), Opt('F', 'F'),
];

/// Opzioni per chiave di `building` (report e badge "valore assunto").
const Map<String, List<Opt>> kBuildingOptions = {
  'tipologia': tipologiaOpts,
  'piano': pianoOpts,
  'orientamento': orientamentoOpts,
  'lati_esposti': latiOpts,
  'numero_piani': pianiOpts,
  'muratura': murOpts,
  'spessore_muri': spessoreOpts,
  'isolamento_pareti_cm': isolamentoOpts,
  'copertura': coperturaOpts,
  'isolamento_copertura_cm': isolamentoOpts,
  'pavimento': pavimentoOpts,
  'isolamento_pavimento_cm': isolamentoOpts,
  'telaio': telaioOpts,
  'vetro': vetroOpts,
  'generatore': generatoreOpts,
  'combustibile': combustibileOpts,
  'impianto': impiantoOpts,
  'terminali': terminaliOpts,
  'regolazione': regolazioneOpts,
  'acs': acsOpts,
  'raffrescamento': raffrescamentoOpts,
  'vmc': vmcOpts,
  'zona_climatica': zonaOpts,
};

/// Etichetta leggibile di un valore (`null` → `—`).
String optionLabel(String key, Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Sì' : 'No';
  for (final o in kBuildingOptions[key] ?? const <Opt>[]) {
    if (o.value == value) return o.label;
  }
  return '$value';
}

/// Generatori senza combustibile da scegliere.
bool usesFuel(Object? generatore) =>
    generatore == null ||
    generatore == 'caldaia_tradizionale' ||
    generatore == 'caldaia_condensazione';

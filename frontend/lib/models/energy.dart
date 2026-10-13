/// Risultato della stima energetica calcolata dal server
/// (`POST /api/v1/estimate` e campo `energy_result` del sopralluogo).
///
/// Il backend (`app/core/energy`) è l'unica fonte del calcolo: qui ci sono
/// solo i tipi per leggerlo. [raw] conserva il JSON completo (report).
library;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.round() ?? 0;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];

/// Comune con dati climatici (DPR 412/93).
class ComuneInfo {
  const ComuneInfo({
    required this.comune,
    required this.provincia,
    required this.zona,
    required this.gradiGiorno,
    this.regione,
    this.altitudine,
  });

  factory ComuneInfo.fromJson(Map<String, dynamic> j) => ComuneInfo(
        comune: j['comune'] as String? ?? '',
        provincia: j['provincia'] as String? ?? '',
        regione: j['regione'] as String?,
        zona: j['zona'] as String? ?? '',
        gradiGiorno: _i(j['gradi_giorno']),
        altitudine: (j['altitudine'] as num?)?.toInt(),
      );

  final String comune;
  final String provincia;
  final String? regione;
  final String zona;
  final int gradiGiorno;
  final int? altitudine;

  String get label => provincia.isEmpty ? comune : '$comune ($provincia)';
}

/// Dato non rilevato e sostituito da un valore tipico.
class Assumption {
  const Assumption(this.campo, this.descrizione, this.valore);

  factory Assumption.fromJson(Map<String, dynamic> j) => Assumption(
        j['campo'] as String? ?? '',
        j['descrizione'] as String? ?? '',
        '${j['valore'] ?? ''}',
      );

  /// Chiave del campo (`square_meters` o una chiave di `building`).
  final String campo;
  final String descrizione;
  final String valore;
}

/// Intervento migliorativo simulato.
class Improvement {
  const Improvement({
    required this.codice,
    required this.intervento,
    required this.classe,
    required this.epGlNren,
    required this.riduzioneEpPct,
    required this.risparmioAnnuoEur,
    required this.investimentoEur,
    required this.classiGuadagnate,
    this.tempoRitornoAnni,
  });

  factory Improvement.fromJson(Map<String, dynamic> j) => Improvement(
        codice: j['codice'] as String? ?? '',
        intervento: j['intervento'] as String? ?? '',
        classe: j['classe'] as String? ?? '',
        epGlNren: _d(j['ep_gl_nren']),
        riduzioneEpPct: _d(j['riduzione_ep_pct']),
        risparmioAnnuoEur: _i(j['risparmio_annuo_eur']),
        investimentoEur: _i(j['investimento_eur']),
        classiGuadagnate: _i(j['classi_guadagnate']),
        tempoRitornoAnni: (j['tempo_ritorno_anni'] as num?)?.toDouble(),
      );

  final String codice;
  final String intervento;
  final String classe;
  final double epGlNren;
  final double riduzioneEpPct;
  final int risparmioAnnuoEur;
  final int investimentoEur;
  final int classiGuadagnate;
  final double? tempoRitornoAnni;

  bool get isGlobal => codice == 'riqualificazione_globale';
}

/// Consumo annuo per vettore energetico.
class Consumption {
  const Consumption(this.vettore, this.kwh, this.quantita, this.unita, this.costoEur);

  factory Consumption.fromJson(Map<String, dynamic> j) => Consumption(
        j['vettore'] as String? ?? '',
        _i(j['kwh']),
        _i(j['quantita']),
        j['unita'] as String? ?? '',
        _i(j['costo_eur']),
      );

  final String vettore;
  final int kwh;
  final int quantita;
  final String unita;
  final int costoEur;

  String get label => switch (vettore) {
        'metano' => 'Gas metano',
        'gpl' => 'GPL',
        'gasolio' => 'Gasolio',
        'elettricita' => 'Energia elettrica',
        'biomassa' => 'Biomassa',
        'teleriscaldamento' => 'Teleriscaldamento',
        _ => vettore,
      };
}

class EnergyResult {
  const EnergyResult(this.raw);

  factory EnergyResult.fromJson(Map<String, dynamic> json) => EnergyResult(json);

  final Map<String, dynamic> raw;

  String get classe => raw['classe'] as String? ?? 'G';
  double get punteggio => _d(raw['punteggio']);
  double get rapportoEp => _d(raw['rapporto_ep']);
  String get metodo => raw['metodo'] as String? ?? '';

  Map<String, dynamic> get _clima => _m(raw['clima']);
  String get zona => _clima['zona'] as String? ?? '';
  int get gradiGiorno => _i(_clima['gradi_giorno']);
  ComuneInfo? get comune =>
      _clima['comune'] is Map ? ComuneInfo.fromJson(_m(_clima['comune'])) : null;

  Map<String, dynamic> get ep => _m(raw['ep']);
  double epValue(String key) => _d(ep[key]);
  double get epGlNren => epValue('gl_nren');
  double get epGlRen => epValue('gl_ren');
  double get epRifStandard =>
      _d(_m(raw['riferimento'])['gl_nren_rif_standard']);
  String get qualitaInvernale =>
      raw['qualita_involucro_invernale'] as String? ?? '';

  Map<String, dynamic> get trasmittanze => _m(raw['trasmittanze']);
  Map<String, dynamic> get trasmittanzeLimite => _m(raw['trasmittanze_limite']);
  Map<String, dynamic> get geometria => _m(raw['geometria']);
  Map<String, dynamic> get impianto => _m(raw['impianto']);
  Map<String, dynamic> get fotovoltaico => _m(raw['fotovoltaico']);

  int get costoAnnuoEur => _i(raw['costo_annuo_eur']);
  int get co2KgAnno => _i(raw['co2_kg_anno']);
  double get co2KgM2 => _d(raw['co2_kg_m2']);

  List<Consumption> get consumi =>
      _l(raw['consumi']).map(Consumption.fromJson).toList(growable: false);
  List<Improvement> get interventi =>
      _l(raw['interventi']).map(Improvement.fromJson).toList(growable: false);
  List<Assumption> get assunzioni =>
      _l(raw['assunzioni']).map(Assumption.fromJson).toList(growable: false);
  List<String> get note => (raw['note'] as List?)?.cast<String>() ?? const [];
}

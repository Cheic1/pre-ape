/// Wire DTO di catasto, documenti allegati e scheda CENED (API v1).
///
/// Contratto: `docs/superpowers/specs/2026-10-18-catasto-admin-cened-design.md`
/// (sezioni 1 e 3). Riesportati da `survey.dart`.
library;

/// Numero massimo di unità catastali per sopralluogo (`MAX_CADASTRAL_UNITS`).
const int kMaxCadastralUnits = 20;

/// Un'unità immobiliare come appare in visura (schema `CadastralUnit`, lato
/// server `extra="forbid"`: [toJson] emette **solo** le chiavi di [keys] e
/// omette i `null`, come il resto del wire).
class CadastralUnit {
  const CadastralUnit({
    this.comune,
    this.codiceComune,
    this.provincia,
    this.sezioneUrbana,
    this.foglio,
    this.particella,
    this.subalterno,
    this.categoria,
    this.classe,
    this.consistenza,
    this.superficieMq,
    this.renditaEuro,
    this.indirizzo,
    this.piano,
  });

  /// Chiavi del contratto, nell'ordine di visualizzazione.
  static const List<String> keys = [
    'comune',
    'codice_comune',
    'provincia',
    'sezione_urbana',
    'foglio',
    'particella',
    'subalterno',
    'categoria',
    'classe',
    'consistenza',
    'superficie_mq',
    'rendita_euro',
    'indirizzo',
    'piano',
  ];

  /// Chiavi numeriche (le altre sono stringhe).
  static const Set<String> numericKeys = {'superficie_mq', 'rendita_euro'};

  /// Lunghezze massime lato server per le chiavi testuali.
  static const Map<String, int> maxLength = {
    'comune': 120,
    'codice_comune': 4,
    'provincia': 2,
    'sezione_urbana': 10,
    'foglio': 10,
    'particella': 20,
    'subalterno': 10,
    'categoria': 10,
    'classe': 10,
    'consistenza': 50,
    'indirizzo': 512,
    'piano': 50,
  };

  factory CadastralUnit.fromJson(Map<String, dynamic> json) {
    String? s(String k) {
      final v = json[k];
      if (v == null) return null;
      final t = v.toString().trim();
      return t.isEmpty ? null : t;
    }

    double? d(String k) => (json[k] as num?)?.toDouble();

    return CadastralUnit(
      comune: s('comune'),
      codiceComune: s('codice_comune'),
      provincia: s('provincia'),
      sezioneUrbana: s('sezione_urbana'),
      foglio: s('foglio'),
      particella: s('particella'),
      subalterno: s('subalterno'),
      categoria: s('categoria'),
      classe: s('classe'),
      consistenza: s('consistenza'),
      superficieMq: d('superficie_mq'),
      renditaEuro: d('rendita_euro'),
      indirizzo: s('indirizzo'),
      piano: s('piano'),
    );
  }

  final String? comune;

  /// Codice catastale (Belfiore) del comune, es. `F205`.
  final String? codiceComune;
  final String? provincia;
  final String? sezioneUrbana;
  final String? foglio;
  final String? particella;
  final String? subalterno;

  /// Es. `A/2`.
  final String? categoria;
  final String? classe;

  /// Es. `5,5 vani`.
  final String? consistenza;
  final double? superficieMq;
  final double? renditaEuro;
  final String? indirizzo;
  final String? piano;

  /// Valore per chiave di contratto (null se assente o chiave sconosciuta).
  Object? operator [](String key) => toJson()[key];

  /// Nessun dato inserito.
  bool get isEmpty => toJson().isEmpty;

  /// Copia con [key] impostata a [value] (null/stringa vuota = cancella).
  /// Le chiavi fuori contratto vengono ignorate.
  CadastralUnit withField(String key, Object? value) {
    if (!keys.contains(key)) return this;
    final json = Map<String, dynamic>.of(toJson());
    if (value == null || (value is String && value.trim().isEmpty)) {
      json.remove(key);
    } else {
      json[key] = value;
    }
    return CadastralUnit.fromJson(json);
  }

  /// Stessa particella/subalterno (identificativo catastale completo).
  bool sameParcelAs(CadastralUnit other) =>
      foglio != null &&
      particella != null &&
      foglio == other.foglio &&
      particella == other.particella &&
      subalterno == other.subalterno &&
      sezioneUrbana == other.sezioneUrbana;

  /// Unisce [other] su questa unità: i valori non nulli di [other] vincono.
  CadastralUnit mergedWith(CadastralUnit other) =>
      CadastralUnit.fromJson({...toJson(), ...other.toJson()});

  /// Serializzazione a `snake_case`, solo chiavi del contratto, senza `null`.
  Map<String, Object?> toJson() => <String, Object?>{
        if (comune != null) 'comune': comune,
        if (codiceComune != null) 'codice_comune': codiceComune,
        if (provincia != null) 'provincia': provincia,
        if (sezioneUrbana != null) 'sezione_urbana': sezioneUrbana,
        if (foglio != null) 'foglio': foglio,
        if (particella != null) 'particella': particella,
        if (subalterno != null) 'subalterno': subalterno,
        if (categoria != null) 'categoria': categoria,
        if (classe != null) 'classe': classe,
        if (consistenza != null) 'consistenza': consistenza,
        if (superficieMq != null) 'superficie_mq': superficieMq,
        if (renditaEuro != null) 'rendita_euro': renditaEuro,
        if (indirizzo != null) 'indirizzo': indirizzo,
        if (piano != null) 'piano': piano,
      };

  /// Identificativo leggibile, es. `Fg. 12 Part. 345 Sub. 6`.
  String get label {
    final parts = [
      if (sezioneUrbana != null) 'Sez. $sezioneUrbana',
      if (foglio != null) 'Fg. $foglio',
      if (particella != null) 'Part. $particella',
      if (subalterno != null) 'Sub. $subalterno',
    ];
    return parts.isEmpty ? 'Unità senza identificativo' : parts.join(' ');
  }

  @override
  bool operator ==(Object other) =>
      other is CadastralUnit && _mapEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(
      CadastralUnit.keys.map((k) => toJson()[k]));

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// Tipi di documento accettati da `POST /surveys/{id}/documents`.
const Map<String, String> kDocumentKinds = {
  'visura': 'Visura catastale',
  'planimetria': 'Planimetria',
  'mappa': 'Estratto di mappa',
  'altro': 'Altro',
};

/// Chi ha caricato il documento (null se l'utente è stato eliminato).
class UploaderInfo {
  const UploaderInfo({required this.id, required this.email, required this.name});

  factory UploaderInfo.fromJson(Map<String, dynamic> json) => UploaderInfo(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  final String id;
  final String email;
  final String name;

  String get display => name.isNotEmpty ? name : email;
}

/// Metadati di un documento allegato (mai il contenuto).
class DocumentMeta {
  const DocumentMeta({
    required this.id,
    required this.surveyId,
    required this.kind,
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.uploadedBy,
    this.extracted,
  });

  factory DocumentMeta.fromJson(Map<String, dynamic> json) => DocumentMeta(
        id: json['id'] as String,
        surveyId: json['survey_id'] as String,
        kind: json['kind'] as String? ?? 'altro',
        filename: json['filename'] as String? ?? '',
        mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        uploadedBy: json['uploaded_by'] is Map<String, dynamic>
            ? UploaderInfo.fromJson(json['uploaded_by'] as Map<String, dynamic>)
            : null,
        extracted: (json['extracted'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(CadastralUnit.fromJson)
            .toList(growable: false),
      );

  final String id;
  final String surveyId;

  /// `visura` | `planimetria` | `mappa` | `altro`.
  final String kind;
  final String filename;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final UploaderInfo? uploadedBy;

  /// Unità proposte dal parser della visura (solo `kind == visura` PDF;
  /// null negli altri casi, lista vuota se nulla è stato riconosciuto).
  final List<CadastralUnit>? extracted;

  String get kindLabel => kDocumentKinds[kind] ?? kind;
}

/// Stati di una riga della scheda CENED.
abstract final class CenedStatus {
  static const ok = 'ok';
  static const stimato = 'stimato';
  static const daRilevare = 'da_rilevare';
}

class CenedRow {
  const CenedRow({
    required this.label,
    required this.status,
    this.value,
    this.cenedField,
  });

  factory CenedRow.fromJson(Map<String, dynamic> json) => CenedRow(
        label: json['label'] as String? ?? '',
        value: json['value'],
        cenedField: json['cened_field'] as String?,
        status: json['status'] as String? ?? CenedStatus.daRilevare,
      );

  final String label;

  /// Stringa o numero; null quando `da_rilevare`.
  final Object? value;

  /// Nome elemento/attributo in `datiCalcolo.xsd` (null se non mappato).
  final String? cenedField;

  /// [CenedStatus.ok] | [CenedStatus.stimato] | [CenedStatus.daRilevare].
  final String status;

  bool get missing => status == CenedStatus.daRilevare || value == null;
  bool get estimated => status == CenedStatus.stimato;

  /// Valore leggibile (numeri all'italiana, `—` se mancante).
  String get displayValue {
    final v = value;
    if (v == null) return '—';
    if (v is num) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return v.toString().replaceAll('.', ',');
    }
    if (v is bool) return v ? 'Sì' : 'No';
    return v.toString();
  }
}

class CenedSection {
  const CenedSection({required this.key, required this.title, required this.rows});

  factory CenedSection.fromJson(Map<String, dynamic> json) => CenedSection(
        key: json['key'] as String? ?? '',
        title: json['title'] as String? ?? '',
        rows: (json['rows'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CenedRow.fromJson)
            .toList(growable: false),
      );

  /// `edificio` | `subalterni` | `strutture_opache` | `serramenti` |
  /// `impianti` | `documenti`.
  final String key;
  final String title;
  final List<CenedRow> rows;
}

/// Risposta di `GET /surveys/{id}/cened-sheet`.
class CenedSheet {
  const CenedSheet({
    required this.surveyId,
    required this.disclaimer,
    required this.sections,
    this.generatedAt,
  });

  factory CenedSheet.fromJson(Map<String, dynamic> json) => CenedSheet(
        surveyId: json['survey_id'] as String? ?? '',
        generatedAt: json['generated_at'] is String
            ? DateTime.tryParse(json['generated_at'] as String)
            : null,
        disclaimer: json['disclaimer'] as String? ?? '',
        sections: (json['sections'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CenedSection.fromJson)
            .toList(growable: false),
      );

  final String surveyId;
  final DateTime? generatedAt;
  final String disclaimer;
  final List<CenedSection> sections;

  int get missingCount =>
      sections.fold(0, (n, s) => n + s.rows.where((r) => r.missing).length);
}

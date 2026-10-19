/// Documento legale servito da `GET /api/v1/legal/{doc}`.
library;

/// Identificativi dei documenti legali (path `/legal/{doc}`).
class LegalDoc {
  static const privacy = 'privacy';
  static const termini = 'termini';
  static const dpa = 'dpa';

  /// Titolo breve usato nei link prima di scaricare il documento.
  static String label(String doc) => switch (doc) {
        privacy => 'Informativa privacy',
        termini => "Termini d'uso",
        dpa => 'Accordo sul trattamento dei dati',
        _ => doc,
      };
}

class LegalDocument {
  const LegalDocument({
    required this.doc,
    required this.title,
    required this.version,
    required this.markdown,
    required this.complete,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) => LegalDocument(
        doc: json['doc'] as String? ?? '',
        title: json['title'] as String? ?? '',
        version: json['version'] as String? ?? '',
        markdown: json['markdown'] as String? ?? '',
        complete: json['complete'] as bool? ?? false,
      );

  final String doc;
  final String title;
  final String version;
  final String markdown;

  /// False finché il gestore non ha compilato tutti i dati: l'app mostra il
  /// banner "bozza".
  final bool complete;
}

/// DTO del pannello amministratore (`/api/v1/admin/*`), contratto nella spec
/// `docs/superpowers/specs/2026-10-18-catasto-admin-cened-design.md` §2.
library;

/// `AdminUser`: utente con conteggi (ordinati per email dal server).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    this.createdAt,
    this.lastLogin,
    this.surveyCount = 0,
    this.documentCount = 0,
    this.isAdmin = false,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        createdAt: _date(json['created_at']),
        lastLogin: _date(json['last_login']),
        surveyCount: (json['survey_count'] as num?)?.toInt() ?? 0,
        documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
        isAdmin: json['is_admin'] as bool? ?? false,
      );

  final String id;
  final String email;
  final String name;
  final DateTime? createdAt;
  final DateTime? lastLogin;
  final int surveyCount;
  final int documentCount;
  final bool isAdmin;
}

/// Chi ha caricato un documento (`UploaderInfo`).
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
}

/// Metadati di un documento catastale (mai il contenuto).
///
/// NB: `models/survey.dart` avrà un suo `DocumentMeta` (catasto); i due
/// verranno unificati al merge. Qui `extracted` resta grezzo: il pannello
/// admin non lo mostra.
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
        extracted: json['extracted'] as List<dynamic>?,
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
  final List<dynamic>? extracted;

  String get kindLabel => switch (kind) {
        'visura' => 'Visura',
        'planimetria' => 'Planimetria',
        'mappa' => 'Estratto di mappa',
        _ => 'Altro',
      };
}

/// Riga del registro accessi (`AuditEntry`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    this.adminEmail,
    this.targetType,
    this.targetId,
    this.detail,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'].toString(),
        adminEmail: json['admin_email'] as String?,
        action: json['action'] as String? ?? '',
        targetType: json['target_type'] as String?,
        targetId: json['target_id']?.toString(),
        detail: json['detail'],
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String? adminEmail;
  final String action;
  final String? targetType;
  final String? targetId;

  /// Oggetto JSON libero scritto dal server (es. `{"email": …, "count": 3}`).
  final Object? detail;
  final DateTime createdAt;

  /// `detail` leggibile: `chiave: valore` separati da " · ".
  String get detailText {
    final d = detail;
    if (d == null) return '';
    if (d is Map) {
      return d.entries
          .where((e) => e.value != null && e.value.toString().isNotEmpty)
          .map((e) {
        final v = e.value is List ? (e.value as List).join(', ') : e.value;
        return '${_detailLabels[e.key] ?? e.key}: $v';
      }).join(' · ');
    }
    return d.toString();
  }

  static const _detailLabels = <String, String>{
    'email': 'email',
    'owner_email': 'proprietario',
    'count': 'elementi',
    'survey_count': 'sopralluoghi',
    'fields': 'campi',
    'title': 'titolo',
    'address': 'indirizzo',
    'filename': 'file',
    'kind': 'tipo',
    'survey_id': 'sopralluogo',
  };

  /// Etichetta italiana dell'azione registrata.
  String get actionLabel => switch (action) {
        'list_users' => 'Elenco utenti',
        'list_user_surveys' => 'Elenco sopralluoghi utente',
        'view_survey' => 'Apertura sopralluogo',
        'update_survey' => 'Modifica sopralluogo',
        'delete_survey' => 'Eliminazione sopralluogo',
        'list_documents' => 'Elenco documenti',
        'download_document' => 'Download documento',
        'delete_document' => 'Eliminazione documento',
        'delete_user' => 'Eliminazione utente',
        _ => action,
      };
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// `gg/mm/aaaa hh:mm` in ora locale.
String formatAdminDate(DateTime? d) {
  if (d == null) return '—';
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

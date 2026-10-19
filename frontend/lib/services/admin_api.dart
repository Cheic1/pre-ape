/// Client per il pannello amministratore (`/api/v1/admin/*`).
///
/// Stessa base URL, stesso JWT e stessa mappatura degli errori di
/// [ApiClient] (il token è letto dal client principale ad ogni chiamata, così
/// login/logout restano in un solo posto). In più: 403 → [ForbiddenException]
/// (utente autenticato ma non amministratore).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../features/admin/admin_models.dart';
import '../models/survey.dart' show SurveyCreate, SurveyRead, SurveySummary;
import 'api_client.dart';

/// 403 – l'utente non è (più) amministratore.
class ForbiddenException extends ApiException {
  ForbiddenException(String message, {Object? detail})
      : super(403, message, detail: detail);
}

/// Bytes + metadati di un documento scaricato.
class DownloadedFile {
  const DownloadedFile({
    required this.bytes,
    required this.mimeType,
    this.filename,
  });

  final Uint8List bytes;
  final String mimeType;

  /// Nome dal `Content-Disposition` (null se assente).
  final String? filename;
}

class AdminApi {
  AdminApi({
    required this.baseUrl,
    String? Function()? token,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  })  : _token = token ?? (() => null),
        _client = client ?? http.Client();

  /// Condivide base URL, JWT e timeout con il client principale.
  factory AdminApi.from(ApiClient api, {http.Client? client}) => AdminApi(
        baseUrl: api.baseUrl,
        token: () => api.token,
        client: client,
        timeout: api.timeout,
      );

  static const String _prefix = '/api/v1/admin';

  final String baseUrl;
  final Duration timeout;
  final String? Function() _token;
  final http.Client _client;

  String? get token => _token();

  // ── Utenti ──────────────────────────────────────────────────────────

  /// `GET /admin/users`.
  Future<List<AdminUser>> listUsers() async =>
      _list(await _json('GET', '$_prefix/users'), AdminUser.fromJson);

  /// `GET /admin/users/{id}/surveys`.
  Future<List<SurveySummary>> listUserSurveys(String userId) async => _list(
      await _json('GET', '$_prefix/users/$userId/surveys'),
      SurveySummary.fromJson);

  /// `DELETE /admin/users/{id}?confirm_email=…` → 204 (422 email errata,
  /// 409 se stesso).
  Future<void> deleteUser(String userId, {required String confirmEmail}) async {
    final q = Uri.encodeQueryComponent(confirmEmail);
    await _json('DELETE', '$_prefix/users/$userId?confirm_email=$q');
  }

  // ── Sopralluoghi ────────────────────────────────────────────────────

  /// `GET /admin/surveys/{id}`.
  Future<SurveyRead> getSurvey(String id) async =>
      SurveyRead.fromJson(_map(await _json('GET', '$_prefix/surveys/$id')));

  /// `PUT /admin/surveys/{id}` (body `SurveyUpdate`, ricalcola la stima).
  Future<SurveyRead> updateSurvey(String id, SurveyCreate body) async =>
      SurveyRead.fromJson(_map(
          await _json('PUT', '$_prefix/surveys/$id', body: body.toJson())));

  /// `DELETE /admin/surveys/{id}` → 204.
  Future<void> deleteSurvey(String id) async {
    await _json('DELETE', '$_prefix/surveys/$id');
  }

  // ── Documenti ───────────────────────────────────────────────────────

  /// `GET /admin/surveys/{id}/documents`.
  Future<List<DocumentMeta>> listDocuments(String surveyId) async => _list(
      await _json('GET', '$_prefix/surveys/$surveyId/documents'),
      DocumentMeta.fromJson);

  /// `GET /admin/documents/{id}/content` → bytes.
  Future<DownloadedFile> downloadDocument(String docId) async {
    final response = await _send('GET', '$_prefix/documents/$docId/content');
    return DownloadedFile(
      bytes: response.bodyBytes,
      mimeType: response.headers['content-type'] ?? 'application/octet-stream',
      filename: _filenameFrom(response.headers['content-disposition']),
    );
  }

  /// `DELETE /admin/documents/{id}` → 204.
  Future<void> deleteDocument(String docId) async {
    await _json('DELETE', '$_prefix/documents/$docId');
  }

  // ── Registro accessi ────────────────────────────────────────────────

  /// `GET /admin/audit?limit=&offset=` (più recenti prima).
  Future<List<AuditEntry>> listAudit({int limit = 100, int offset = 0}) async =>
      _list(await _json('GET', '$_prefix/audit?limit=$limit&offset=$offset'),
          AuditEntry.fromJson);

  // ── Transport ───────────────────────────────────────────────────────

  static List<T> _list<T>(
      Object? json, T Function(Map<String, dynamic>) parse) {
    if (json is! List) {
      throw ApiException(200, 'Risposta inattesa dal server');
    }
    return json
        .whereType<Map<String, dynamic>>()
        .map(parse)
        .toList(growable: false);
  }

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw ApiException(200, 'Risposta inattesa dal server');
  }

  Future<Object?> _json(String method, String path, {Object? body}) async {
    final response = await _send(method, path, body: body);
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body) as Object?;
    } on FormatException {
      throw ApiException(
          response.statusCode, 'Risposta non JSON dal server ($method $path)');
    }
  }

  /// Esegue la richiesta; ritorna solo risposte 2xx, altrimenti lancia.
  Future<http.Response> _send(String method, String path,
      {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final t = _token();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
    final encoded = body == null ? null : jsonEncode(body);
    final Future<http.Response> pending = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'PUT' => _client.put(uri, headers: headers, body: encoded),
      'DELETE' => _client.delete(uri, headers: headers),
      _ => throw ApiException(0, 'Metodo non supportato: $method'),
    };

    final http.Response response;
    try {
      response = await pending.timeout(timeout);
    } on TimeoutException {
      throw ApiTimeoutException(
          'Nessuna risposta da $baseUrl$path entro ${timeout.inSeconds}s');
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Errore di rete: ${e.message}');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw _exceptionFor(response);
  }

  static ApiException _exceptionFor(http.Response response) {
    Object? payload;
    try {
      payload = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      payload = null;
    }
    final Object? detail = payload is Map ? payload['detail'] : payload;
    final status = response.statusCode;
    final message = _messageFor(status, detail);
    return switch (status) {
      401 => UnauthorizedException(message, detail: detail),
      403 => ForbiddenException(message, detail: detail),
      404 => NotFoundException(message, detail: detail),
      422 => ValidationException(message, detail: detail),
      _ => ApiException(status, message, detail: detail),
    };
  }

  static String _messageFor(int status, Object? detail) {
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List) {
      final errors = detail
          .whereType<Map>()
          .map((e) => e['msg']?.toString() ?? e.toString())
          .join('; ');
      if (errors.isNotEmpty) return errors;
    }
    return 'Errore HTTP $status';
  }

  /// `attachment; filename*=UTF-8''nome%20file.pdf` → `nome file.pdf`.
  static String? _filenameFrom(String? header) {
    if (header == null) return null;
    final star = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
        .firstMatch(header);
    if (star != null) {
      try {
        return Uri.decodeComponent(star.group(1)!.trim());
      } on ArgumentError {
        return star.group(1);
      }
    }
    final plain = RegExp(r'filename="?([^";]+)"?').firstMatch(header);
    return plain?.group(1);
  }
}

/// [ApiClient] che, per il wizard aperto da un amministratore sul sopralluogo
/// di un altro utente, legge e salva tramite `/admin/surveys/{id}`.
/// Le altre chiamate (stima, comuni…) restano quelle normali.
class AdminSurveyClient extends ApiClient {
  AdminSurveyClient(this.admin, {super.client})
      : super(baseUrl: admin.baseUrl, timeout: admin.timeout) {
    setToken(admin.token);
  }

  final AdminApi admin;

  @override
  String? get token => admin.token;

  @override
  bool get isAuthenticated => admin.token != null;

  @override
  Future<SurveyRead> getSurvey(String id) => admin.getSurvey(id);

  @override
  Future<SurveyRead> updateSurvey(String id, SurveyCreate body) =>
      admin.updateSurvey(id, body);

  /// Un amministratore non crea sopralluoghi a nome di altri.
  @override
  Future<SurveyRead> createSurvey(SurveyCreate body) => Future.error(
      ApiException(0, 'Modalità amministratore: creazione non consentita'));
}

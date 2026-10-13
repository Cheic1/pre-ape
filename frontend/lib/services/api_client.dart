/// HTTP client per l'API Pre-APE v1 – contratto: `docs/openapi.snapshot.json`.
///
/// * JWT in memoria (`_token`); la persistenza tra sessioni è compito di
///   `AuthNotifier` (shared_preferences) che lo ripristina con [setToken].
/// * Header `Authorization: Bearer <token>` su ogni chiamata autenticata.
/// * Timeout unico su ogni chiamata → [ApiTimeoutException].
/// * Error mapping del dettaglio FastAPI `{"detail": ...}`:
///   401 → [UnauthorizedException], 404 → [NotFoundException],
///   422 → [ValidationException], altro → [ApiException].
///
/// Il client è iniettabile (`http.Client`): i test usano `MockClient` e non
/// toccano la rete.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/energy.dart';
import '../models/survey.dart';

/// Base class di ogni errore di API: `statusCode` 0 = nessuna risposta
/// (timeout o rete), altrimenti lo status HTTP reale.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.detail});

  final int statusCode;
  final String message;

  /// Payload `detail` del backend (stringa, lista di errori di validazione...).
  final Object? detail;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 401 – token assente/invalido/scaduto.
class UnauthorizedException extends ApiException {
  UnauthorizedException(String message, {Object? detail})
      : super(401, message, detail: detail);
}

/// 404 – survey inesistente **oppure** non posseduto dall'utente (nessun
/// oracolo di esistenza: il contratto risponde uguale nei due casi).
class NotFoundException extends ApiException {
  NotFoundException(String message, {Object? detail})
      : super(404, message, detail: detail);
}

/// 422 – validazione: `detail` contiene `loc`/`msg`/`type` per campo.
class ValidationException extends ApiException {
  ValidationException(String message, {Object? detail})
      : super(422, message, detail: detail);
}

/// Nessuna risposta entro [ApiClient.timeout].
class ApiTimeoutException extends ApiException {
  ApiTimeoutException(String message) : super(0, message);
}

class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  /// Backend di sviluppo locale.
  static const String defaultBaseUrl = 'http://localhost:7031';

  /// URL del backend per l'app reale:
  /// 1. `--dart-define=API_BASE_URL=https://...` se impostato in build;
  /// 2. sul web, la stessa origine della pagina (immagine Docker unica:
  ///    l'API serve anche l'app, quindi niente CORS);
  /// 3. altrimenti [defaultBaseUrl].
  static String resolveBaseUrl({required bool isWeb, Uri? pageUri}) {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) return _trimSlash(fromDefine);
    if (isWeb && pageUri != null && pageUri.hasAuthority) {
      return _trimSlash(pageUri.origin);
    }
    return defaultBaseUrl;
  }

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static const String _apiPrefix = '/api/v1';

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  String? _token;

  /// JWT corrente, in memoria soltanto.
  String? get token => _token;

  bool get isAuthenticated => _token != null;

  void logout() => _token = null;

  /// Ripristina un JWT salvato (sessione persistente).
  void setToken(String? token) => _token = token;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// `POST /api/v1/auth/register` → 201 (409 se l'email è già registrata).
  Future<AuthToken> register({
    required String email,
    required String password,
    String? name,
  }) {
    return _authRequest('$_apiPrefix/auth/register', <String, Object?>{
      'email': email,
      'password': password,
      if (name != null) 'name': name,
    });
  }

  /// `POST /api/v1/auth/login` → 200 (401 se credenziali errate).
  Future<AuthToken> login({
    required String email,
    required String password,
  }) {
    return _authRequest('$_apiPrefix/auth/login', <String, Object?>{
      'email': email,
      'password': password,
    });
  }

  Future<AuthToken> _authRequest(String path, Map<String, Object?> body) async {
    final json = await _request('POST', path, body: body, authenticated: false);
    final auth = AuthToken.fromJson(json);
    _token = auth.accessToken;
    return auth;
  }

  // ---------------------------------------------------------------------------
  // Surveys
  // ---------------------------------------------------------------------------

  /// `POST /api/v1/surveys` → 201.
  Future<SurveyRead> createSurvey(SurveyCreate body) async {
    final json =
        await _request('POST', '$_apiPrefix/surveys', body: body.toJson());
    return SurveyRead.fromJson(json);
  }

  /// `GET /api/v1/surveys` → 200, survey del chiamante (più recenti prima).
  Future<List<SurveySummary>> listSurveys() async {
    final json = await _requestAny('GET', '$_apiPrefix/surveys');
    if (json is! List) {
      throw ApiException(200, 'Risposta inattesa dal server (GET /surveys)');
    }
    return json
        .whereType<Map<String, dynamic>>()
        .map(SurveySummary.fromJson)
        .toList(growable: false);
  }

  /// `DELETE /api/v1/surveys/{id}` → 204 | 404.
  Future<void> deleteSurvey(String id) async {
    await _requestAny('DELETE', '$_apiPrefix/surveys/$id');
  }

  /// `GET /api/v1/surveys/{id}` → 200 | 404.
  Future<SurveyRead> getSurvey(String id) async {
    final json = await _request('GET', '$_apiPrefix/surveys/$id');
    return SurveyRead.fromJson(json);
  }

  /// `PUT /api/v1/surveys/{id}` → 200 | 404. Update **parziale**: i campi
  /// `null` del DTO non vengono inviati e quindi non vengono cancellati.
  Future<SurveyRead> updateSurvey(String id, SurveyCreate body) async {
    final json = await _request(
      'PUT',
      '$_apiPrefix/surveys/$id',
      body: body.toJson(),
    );
    return SurveyRead.fromJson(json);
  }

  // ---------------------------------------------------------------------------
  // Energy estimate + climate data
  // ---------------------------------------------------------------------------

  /// `POST /api/v1/estimate` → stima live (nulla viene salvato). [body] ha le
  /// chiavi del sottoinsieme energetico del sopralluogo (`building`,
  /// `square_meters`, `avg_height`, `address`, `latitude`, `longitude`).
  Future<EnergyResult> estimate(Map<String, Object?> body) async {
    final json = await _request('POST', '$_apiPrefix/estimate', body: body);
    return EnergyResult.fromJson(json);
  }

  /// `GET /api/v1/climate/comuni?q=` → autocompletamento comuni.
  Future<List<ComuneInfo>> searchComuni(String query) async {
    final q = Uri.encodeQueryComponent(query);
    final json = await _requestAny('GET', '$_apiPrefix/climate/comuni?q=$q');
    if (json is! List) return const [];
    return json
        .whereType<Map<String, dynamic>>()
        .map(ComuneInfo.fromJson)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Map<String, String> _headers({required bool authenticated}) => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final payload = await _requestAny(
      method,
      path,
      body: body,
      authenticated: authenticated,
    );
    if (payload is Map<String, dynamic>) return payload;
    throw ApiException(200, 'Risposta non JSON dal server ($method $path)');
  }

  /// Come [_request] ma restituisce il JSON grezzo (lista, mappa o `null`
  /// per le risposte vuote, es. 204).
  Future<Object?> _requestAny(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = _headers(authenticated: authenticated);
    final encoded = body == null ? null : jsonEncode(body);

    final Future<http.Response> pending;
    if (method == 'GET') {
      pending = _client.get(uri, headers: headers);
    } else if (method == 'POST') {
      pending = _client.post(uri, headers: headers, body: encoded);
    } else if (method == 'PUT') {
      pending = _client.put(uri, headers: headers, body: encoded);
    } else if (method == 'DELETE') {
      pending = _client.delete(uri, headers: headers);
    } else {
      throw ApiException(0, 'Metodo non supportato: $method');
    }

    final http.Response response;
    try {
      response = await pending.timeout(timeout);
    } on TimeoutException {
      throw ApiTimeoutException(
        'Nessuna risposta da $baseUrl$path entro ${_formatTimeout(timeout)}',
      );
    } on http.ClientException catch (e) {
      throw ApiException(0, 'Errore di rete: ${e.message}');
    }

    Object? payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body) as Object?;
      } on FormatException {
        throw ApiException(
          response.statusCode,
          'Risposta non JSON dal server ($method $path)',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }
    throw _exceptionFor(response.statusCode, payload);
  }

  String _formatTimeout(Duration d) =>
      d.inSeconds >= 1 ? '${d.inSeconds}s' : '${d.inMilliseconds}ms';

  /// Mappa gli status del contratto su eccezioni tipizzate.
  ApiException _exceptionFor(int status, Object? payload) {
    final Object? detail = payload is Map ? payload['detail'] : payload;
    final String message = _messageFor(status, detail);
    if (status == 401) return UnauthorizedException(message, detail: detail);
    if (status == 404) return NotFoundException(message, detail: detail);
    if (status == 422) return ValidationException(message, detail: detail);
    return ApiException(status, message, detail: detail);
  }

  String _messageFor(int status, Object? detail) {
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
}

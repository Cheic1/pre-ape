/// Sessione utente: login/registrazione contro l'API e JWT persistente.
///
/// Il token vive in [ApiClient] (memoria) ed è salvato con
/// `shared_preferences` (localStorage sul web) così il tecnico resta loggato
/// tra un sopralluogo e l'altro. Un 401 da qualunque chiamata deve passare da
/// [AuthNotifier.handleUnauthorized] che riporta alla schermata di login.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/survey.dart' show AuthToken;
import '../../services/api_client.dart';

/// Client API condiviso dall'intera app.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ApiClient.resolveBaseUrl(isWeb: kIsWeb, pageUri: Uri.base),
  );
});

final authProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier(ref.watch(apiClientProvider));
});

/// Utente autenticato (dati minimi mostrati in UI).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.isAdmin = false,
  });

  final String id;
  final String email;
  final String name;

  /// Accesso al pannello "Amministrazione" (il server verifica comunque).
  final bool isAdmin;
}

enum AuthStatus { restoring, signedOut, signedIn }

class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._api, {Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  static const _kToken = 'preape.token';
  static const _kUserId = 'preape.user_id';
  static const _kEmail = 'preape.email';
  static const _kName = 'preape.name';
  static const _kIsAdmin = 'preape.is_admin';

  final ApiClient _api;
  final Future<SharedPreferences> Function() _prefs;

  AuthStatus _status = AuthStatus.restoring;
  AuthUser? _user;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  /// True mentre login/registrazione sono in corso.
  bool get busy => _busy;

  /// Ultimo messaggio di errore leggibile (null se nessuno).
  String? get error => _error;

  /// Ripristina la sessione salvata all'avvio dell'app.
  Future<void> restore() async {
    try {
      final prefs = await _prefs();
      final token = prefs.getString(_kToken);
      final id = prefs.getString(_kUserId);
      if (token != null && id != null) {
        _api.setToken(token);
        _user = AuthUser(
          id: id,
          email: prefs.getString(_kEmail) ?? '',
          name: prefs.getString(_kName) ?? '',
          // sessioni salvate prima del pannello admin: non admin
          isAdmin: prefs.getBool(_kIsAdmin) ?? false,
        );
        _status = AuthStatus.signedIn;
      } else {
        _status = AuthStatus.signedOut;
      }
    } catch (_) {
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => _api.login(email: email.trim(), password: password));

  Future<bool> register(String email, String password, {String? name}) =>
      _authenticate(() => _api.register(
            email: email.trim(),
            password: password,
            name: (name == null || name.trim().isEmpty) ? null : name.trim(),
          ));

  Future<bool> _authenticate(Future<AuthToken> Function() call) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final auth = await call();
      _user = AuthUser(
        id: auth.userId,
        email: auth.email,
        name: auth.name,
        isAdmin: auth.isAdmin,
      );
      _status = AuthStatus.signedIn;
      await _persist(auth.accessToken);
      return true;
    } on ApiException catch (e) {
      _error = describeAuthError(e);
      return false;
    } catch (_) {
      _error = 'Errore imprevisto, riprova.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _api.logout();
    _user = null;
    _status = AuthStatus.signedOut;
    _error = null;
    notifyListeners();
    try {
      final prefs = await _prefs();
      await Future.wait([
        prefs.remove(_kToken),
        prefs.remove(_kUserId),
        prefs.remove(_kEmail),
        prefs.remove(_kName),
        prefs.remove(_kIsAdmin),
      ]);
    } catch (_) {
      // storage non disponibile: la sessione in memoria è comunque chiusa
    }
  }

  /// Token scaduto o revocato: torna al login con un messaggio chiaro.
  Future<void> handleUnauthorized() async {
    await logout();
    _error = 'Sessione scaduta, accedi di nuovo.';
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _persist(String token) async {
    try {
      final prefs = await _prefs();
      final user = _user!;
      await Future.wait([
        prefs.setString(_kToken, token),
        prefs.setString(_kUserId, user.id),
        prefs.setString(_kEmail, user.email),
        prefs.setString(_kName, user.name),
        prefs.setBool(_kIsAdmin, user.isAdmin),
      ]);
    } catch (_) {
      // es. navigazione privata: si resta loggati solo per questa sessione
    }
  }
}

/// Messaggi in italiano per gli errori di autenticazione.
String describeAuthError(ApiException e) {
  switch (e.statusCode) {
    case 0:
      return 'Server non raggiungibile. Controlla la connessione.';
    case 401:
      return 'Email o password non corretti.';
    case 409:
      return 'Esiste già un account con questa email.';
    case 422:
      return 'Dati non validi: controlla email e password (minimo 8 caratteri).';
    case 429:
      return 'Troppi tentativi. Attendi un minuto e riprova.';
    default:
      return 'Errore del server (${e.statusCode}). Riprova più tardi.';
  }
}

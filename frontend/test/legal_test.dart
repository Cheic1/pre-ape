/// Livello legale: consenso alla registrazione, pagina dei documenti,
/// dialogo di riaccettazione dopo il login.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/auth/login_page.dart';
import 'package:pre_ape/features/legal/legal_page.dart';
import 'package:pre_ape/main.dart';
import 'package:pre_ape/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://legal.test';

Map<String, Object?> _token({bool termsAccepted = true}) => <String, Object?>{
      'access_token': 'jwt-1',
      'token_type': 'bearer',
      'user_id': 'u-1',
      'email': 'geo@example.com',
      'name': 'Geometra',
      'terms_accepted': termsAccepted,
    };

Map<String, Object?> _doc({bool complete = false}) => <String, Object?>{
      'doc': 'privacy',
      'title': 'Informativa privacy',
      'version': '2026-10-19',
      'complete': complete,
      'markdown': '# Informativa sul trattamento\n\n'
          'Testo con **grassetto** e [da completare: TITOLARE_NOME].\n\n'
          '## 1. Diritti\n\n'
          '- accesso ai dati\n\n'
          '| Finalità | Base giuridica |\n|---|---|\n| Account | Contratto |\n',
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Widget _app(ApiClient api, Widget home) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(home: home),
    );

FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('login_submit')));

void main() {
  group('Registrazione – consenso obbligatorio', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('invio disabilitato finché la casella non è spuntata, poi '
        'accept_terms: true', (tester) async {
      final bodies = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json(_token(), 201);
        }),
      );
      await tester.pumpWidget(_app(api, const LoginPage()));

      // in modalità accesso il pulsante è attivo e la casella non c'è
      expect(_submitButton(tester).onPressed, isNotNull);
      expect(find.byKey(const ValueKey('register_accept_terms')), findsNothing);

      await tester.tap(find.text('Non hai un account? Registrati gratis'));
      await tester.pump();
      expect(find.text('Informativa privacy'), findsOneWidget);
      expect(find.text("Termini d'uso"), findsOneWidget);
      expect(find.text('Accordo sul trattamento dei dati'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('login_email')), 'geo@example.com');
      await tester.enterText(
          find.byKey(const ValueKey('login_password')), 'password-lunga');
      expect(_submitButton(tester).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('login_submit')));
      await tester.tap(find.byKey(const ValueKey('login_submit')));
      await tester.pump();
      expect(bodies, isEmpty);

      await tester.ensureVisible(find.byKey(const ValueKey('register_accept_terms')));
      await tester.tap(find.byKey(const ValueKey('register_accept_terms')));
      await tester.pump();
      expect(_submitButton(tester).onPressed, isNotNull);
      await tester.ensureVisible(find.byKey(const ValueKey('login_submit')));
      await tester.tap(find.byKey(const ValueKey('login_submit')));
      await tester.pumpAndSettle();

      expect(bodies, hasLength(1));
      expect(bodies.single['accept_terms'], isTrue);
      expect(bodies.single['email'], 'geo@example.com');
    });

    testWidgets('i link aprono il documento', (tester) async {
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          paths.add(req.url.path);
          return _json({..._doc(), 'doc': 'termini', 'title': "Termini d'uso"});
        }),
      );
      await tester.pumpWidget(_app(api, const LoginPage()));
      await tester.tap(find.text('Non hai un account? Registrati gratis'));
      await tester.pump();
      await tester.tap(find.text("Termini d'uso"));
      await tester.pumpAndSettle();
      expect(paths, ['/api/v1/legal/termini']);
      expect(find.byType(LegalPage), findsOneWidget);
    });
  });

  group('LegalPage', () {
    testWidgets('rende il markdown e il banner bozza se incompleto',
        (tester) async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          seen = req;
          return _json(_doc());
        }),
      )..setToken('jwt-1');
      await tester.pumpWidget(_app(api, const LegalPage(doc: 'privacy')));
      await tester.pumpAndSettle();

      expect(seen.url.path, '/api/v1/legal/privacy');
      expect(seen.headers['Authorization'], isNull,
          reason: 'documenti pubblici, nessun token');
      expect(find.byKey(const ValueKey('legal_draft_banner')), findsOneWidget);
      expect(find.text('Informativa privacy'), findsOneWidget); // app bar
      expect(find.text('Informativa sul trattamento'), findsOneWidget);
      expect(find.text('1. Diritti'), findsOneWidget);
      expect(find.textContaining('[da completare: TITOLARE_NOME]', findRichText: true),
          findsOneWidget);
      expect(find.text('accesso ai dati'), findsOneWidget);
      expect(find.text('Base giuridica'), findsOneWidget);
      expect(find.text('Contratto'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('nessun banner quando il documento è completo', (tester) async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json(_doc(complete: true))),
      );
      await tester.pumpWidget(_app(api, const LegalPage(doc: 'privacy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('legal_draft_banner')), findsNothing);
    });
  });

  group('Riaccettazione dopo il login', () {
    test('login: terms_accepted letto e salvato', () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json(_token(termsAccepted: false))),
      );
      final auth = AuthNotifier(api);
      expect(await auth.login('geo@example.com', 'password1'), isTrue);
      expect(auth.termsAccepted, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('preape.terms_accepted'), isFalse);
    });

    Future<List<http.Request>> pumpGate(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'preape.token': 'jwt-1',
        'preape.user_id': 'u-1',
        'preape.email': 'geo@example.com',
        'preape.name': 'Geometra',
        // sessione di un utente che non ha accettato la versione corrente
        'preape.terms_accepted': false,
      });
      final requests = <http.Request>[];
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          requests.add(req);
          if (req.url.path == '/api/v1/auth/accept-terms') {
            return _json({'terms_accepted': true, 'version': '2026-10-19'});
          }
          return _json(<Object>[]); // GET /surveys
        }),
      );
      await tester.pumpWidget(_app(api, const AuthGate()));
      await tester.pumpAndSettle();
      return requests;
    }

    testWidgets('dialogo bloccante → Accetto chiama accept-terms', (tester) async {
      final requests = await pumpGate(tester);
      expect(find.byKey(const ValueKey('terms_dialog')), findsOneWidget);

      // non si chiude toccando fuori
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terms_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('terms_accept')));
      await tester.pumpAndSettle();

      final accept =
          requests.where((r) => r.url.path == '/api/v1/auth/accept-terms');
      expect(accept, hasLength(1));
      expect(accept.single.method, 'POST');
      expect(accept.single.headers['Authorization'], 'Bearer jwt-1');
      expect(find.byKey(const ValueKey('terms_dialog')), findsNothing);
      expect(find.text('I miei sopralluoghi'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('preape.terms_accepted'), isTrue);
    });

    testWidgets('Esci → logout e ritorno al login', (tester) async {
      final requests = await pumpGate(tester);
      await tester.tap(find.byKey(const ValueKey('terms_exit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terms_dialog')), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(requests.where((r) => r.url.path == '/api/v1/auth/accept-terms'),
          isEmpty);
    });

    testWidgets('nessun dialogo se già accettati', (tester) async {
      SharedPreferences.setMockInitialValues({
        'preape.token': 'jwt-1',
        'preape.user_id': 'u-1',
        'preape.terms_accepted': true,
      });
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json(<Object>[])),
      );
      await tester.pumpWidget(_app(api, const AuthGate()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('terms_dialog')), findsNothing);
      expect(find.text('I miei sopralluoghi'), findsOneWidget);
    });
  });
}

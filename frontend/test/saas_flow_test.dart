/// SaaS MVP: sessione persistente, lista/cancellazione, salvataggio wizard.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/auth/login_page.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://saas.test';

const _token = <String, Object?>{
  'access_token': 'jwt-1',
  'token_type': 'bearer',
  'user_id': 'u-1',
  'email': 'geo@example.com',
  'name': 'Geometra',
};

Map<String, Object?> _survey(String id, {Map<String, Object?> extra = const {}}) =>
    <String, Object?>{
      'id': id,
      'status': 'draft',
      'created_at': '2026-10-01T10:00:00',
      'updated_at': '2026-10-01T10:00:00',
      ...extra,
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('ApiClient – lista e cancellazione', () {
    test('listSurveys: GET /surveys con Bearer, parse delle righe', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          seen = req;
          return _json([
            {
              ..._survey('s-1'),
              'title': 'APE 1/2026',
              'estimated_class': 'C',
              'photo_count': 3,
            },
          ]);
        }),
      )..setToken('jwt-1');

      final rows = await api.listSurveys();
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/surveys');
      expect(seen.headers['Authorization'], 'Bearer jwt-1');
      expect(rows.single.title, 'APE 1/2026');
      expect(rows.single.estimatedClass, 'C');
      expect(rows.single.photoCount, 3);
      expect(rows.single.isCompleted, isFalse);
    });

    test('deleteSurvey: 204 senza corpo non è un errore', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          seen = req;
          return http.Response('', 204);
        }),
      )..setToken('jwt-1');
      await api.deleteSurvey('s-9');
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/api/v1/surveys/s-9');
    });

    test('deleteSurvey: 404 → NotFoundException', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json({'detail': 'Survey not found'}, 404)),
      );
      expect(api.deleteSurvey('x'), throwsA(isA<NotFoundException>()));
    });

    test('resolveBaseUrl: sul web usa la stessa origine della pagina', () {
      expect(
        ApiClient.resolveBaseUrl(
            isWeb: true, pageUri: Uri.parse('https://app.example.it/#/x')),
        'https://app.example.it',
      );
      expect(ApiClient.resolveBaseUrl(isWeb: false), ApiClient.defaultBaseUrl);
    });
  });

  group('AuthNotifier – sessione persistente', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('login salva il token e restore lo ripristina', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json(_token)),
      );
      final auth = AuthNotifier(api);
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);

      expect(await auth.login('geo@example.com', 'password1'), isTrue);
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user!.email, 'geo@example.com');

      // nuova "sessione" del browser: client vergine, stesso storage
      final api2 = ApiClient(baseUrl: _base, client: MockClient((_) async => _json({})));
      final restored = AuthNotifier(api2);
      await restored.restore();
      expect(restored.status, AuthStatus.signedIn);
      expect(api2.token, 'jwt-1');
      expect(restored.user!.name, 'Geometra');
    });

    test('credenziali errate → messaggio in italiano, resta fuori', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient(
            (_) async => _json({'detail': 'Incorrect email or password'}, 401)),
      );
      final auth = AuthNotifier(api);
      await auth.restore();
      expect(await auth.login('geo@example.com', 'sbagliata'), isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.error, 'Email o password non corretti.');
    });

    test('email già registrata → 409 tradotto', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient(
            (_) async => _json({'detail': 'Email already registered'}, 409)),
      );
      final auth = AuthNotifier(api);
      expect(await auth.register('geo@example.com', 'password1'), isFalse);
      expect(auth.error, contains('Esiste già'));
    });

    test('logout e sessione scaduta puliscono storage e token', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json(_token)),
      );
      final auth = AuthNotifier(api);
      await auth.login('geo@example.com', 'password1');
      await auth.handleUnauthorized();
      expect(auth.status, AuthStatus.signedOut);
      expect(api.token, isNull);
      expect(auth.error, contains('Sessione scaduta'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('preape.token'), isNull);
    });
  });

  group('SurveyNotifier – salvataggio sul server', () {
    test('primo salvataggio = POST, poi PUT sullo stesso id', () async {
      final calls = <String>[];
      Map<String, dynamic>? lastBody;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          lastBody = jsonDecode(req.body) as Map<String, dynamic>;
          final status = lastBody!['status'] as String? ?? 'draft';
          return _json(_survey('s-42', extra: {'status': status}),
              req.method == 'POST' ? 201 : 200);
        }),
      );

      final n = SurveyNotifier()..startNew();
      n.updateTitle('APE 7/2026');
      n.updateClientName('Mario Rossi');
      n.setBuilding('telaio', 'PVC');
      n.setBuilding('vetro', 'Doppio');
      n.setBuilding('anno_costruzione', 1975);
      n.updateNotes('Caldaia in cantina');
      expect(n.dirty, isTrue);

      await n.save(api);
      expect(calls, ['POST /api/v1/surveys']);
      expect(n.data.surveyId, 's-42');
      expect(n.dirty, isFalse);
      expect(lastBody!['title'], 'APE 7/2026');
      expect(lastBody!['client_name'], 'Mario Rossi');
      expect(lastBody!['building'],
          {'telaio': 'PVC', 'vetro': 'Doppio', 'anno_costruzione': 1975});
      expect(lastBody!.containsKey('window_frame'), isFalse);
      expect(lastBody!['notes'], 'Caldaia in cantina');
      expect(lastBody!.containsKey('status'), isFalse);
      expect(lastBody!.containsKey('energy_score'), isFalse);

      await n.save(api, complete: true);
      expect(calls.last, 'PUT /api/v1/surveys/s-42');
      expect(lastBody!['status'], 'completed');
      expect(n.data.status, 'completed');
    });

    test('errore di rete: resta dirty e l\'eccezione arriva al chiamante', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final n = SurveyNotifier()..startNew();
      n.updateTitle('x');
      await expectLater(n.save(api), throwsA(isA<ApiException>()));
      expect(n.dirty, isTrue);
      expect(n.saving, isFalse);
      expect(n.data.surveyId, isNull);
    });

    test('loadFrom ricostruisce lo stato del wizard', () {
      final read = SurveyRead(
        id: 's-1',
        status: 'completed',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        title: 'APE 1',
        clientName: 'Bianchi',
        notes: 'n',
        squareMeters: 120,
        windowFrame: 'Legno',
        windowGlass: 'Triplo',
        heatingType: 'Pompa di Calore',
        photos: const {'Facciata': 'data:image/jpeg;base64,AAAA'},
        additionalPhotos: const ['data:image/jpeg;base64,BBBB'],
      );
      final n = SurveyNotifier()..loadFrom(read);
      expect(n.data.surveyId, 's-1');
      // colonne del primo MVP → input energetici
      expect(n.data.building, {
        'telaio': 'Legno',
        'vetro': 'Triplo',
        'generatore': 'pompa_calore_aria_acqua',
      });
      expect(n.data.squareMeters, 120);
      expect(n.data.photos.keys, ['Facciata']);
      expect(n.data.additionalPhotos, hasLength(1));
      expect(n.currentStep, 1);
      expect(n.dirty, isFalse);
      expect(n.data.result, isNull);
      // round-trip verso il server
      final wire = n.toWire();
      expect(wire.building!['vetro'], 'Triplo');
      expect(wire.windowFrame, isNull);
      expect(wire.photos, {'Facciata': 'data:image/jpeg;base64,AAAA'});
    });

    test('loadFrom: building salvato vince sulle colonne legacy', () {
      final read = SurveyRead(
        id: 's-2',
        status: 'draft',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        windowGlass: 'Singolo',
        building: const {'vetro': 'Triplo', 'comune': 'Roma'},
      );
      final n = SurveyNotifier()..loadFrom(read);
      expect(n.data.building['vetro'], 'Triplo');
      expect(n.data.building['comune'], 'Roma');
    });

    test('stima live: POST /estimate col sottoinsieme energetico', () async {
      Map<String, dynamic>? body;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          expect('${req.method} ${req.url.path}', 'POST /api/v1/estimate');
          expect(req.headers['Authorization'], 'Bearer jwt-1');
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'classe': 'D', 'punteggio': 34.0, 'ep': {'gl_nren': 90.0}});
        }),
      )..setToken('jwt-1');
      final n = SurveyNotifier(api: api, estimateDebounce: Duration.zero);
      n.updateSquareMeters(95);
      n.setBuilding('generatore', 'caldaia_condensazione');
      n.setBuilding('generatore', null); // cleared answers are not sent
      n.setBuilding('piano', 'ultimo');
      await n.refreshEstimate();
      expect(body!['square_meters'], 95);
      expect(body!['building'], {'piano': 'ultimo'});
      expect(n.data.result!.classe, 'D');
      expect(n.data.score, 34.0);
      expect(n.data.estimating, isFalse);
      n.dispose();
    });

    test('stima live: errore del server non cancella la stima precedente', () async {
      var fail = false;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async => fail
            ? _json({'detail': 'boom'}, 500)
            : _json({'classe': 'C', 'punteggio': 45.0})),
      )..setToken('jwt-1');
      final n = SurveyNotifier(api: api, estimateDebounce: Duration.zero);
      await n.refreshEstimate();
      fail = true;
      await n.refreshEstimate();
      expect(n.data.result!.classe, 'C');
      n.dispose();
    });

    test('senza login nessuna chiamata di stima', () async {
      var calls = 0;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async {
          calls++;
          return _json({});
        }),
      );
      final n = SurveyNotifier(api: api);
      await n.refreshEstimate();
      expect(calls, 0);
      n.dispose();
    });
  });

  group('LoginPage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('validazione locale e passaggio a registrazione', (tester) async {
      var requests = 0;
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async {
          requests++;
          return _json(_token);
        }),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: LoginPage()),
      ));

      await tester.tap(find.byKey(const ValueKey('login_submit')));
      await tester.pump();
      expect(find.text('Inserisci la tua email'), findsOneWidget);
      expect(requests, 0);

      await tester.tap(find.text('Non hai un account? Registrati gratis'));
      await tester.pump();
      expect(find.text('Crea il tuo account'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('login_email')), 'geo@example.com');
      await tester.enterText(find.byKey(const ValueKey('login_password')), 'corta');
      await tester.tap(find.byKey(const ValueKey('login_submit')));
      await tester.pump();
      expect(find.text('Almeno 8 caratteri'), findsOneWidget);
      expect(requests, 0);

      await tester.enterText(
          find.byKey(const ValueKey('login_password')), 'password-lunga');
      await tester.tap(find.byKey(const ValueKey('login_submit')));
      await tester.pumpAndSettle();
      expect(requests, 1);
    });
  });
}

/// Shape del contratto v1 (docs/openapi.snapshot.json) verificata con
/// `MockClient`: nessuna chiamata di rete nei test.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

const _baseUrl = 'http://contract.test';

const _tokenJson = <String, Object?>{
  'access_token': 'jwt-test-token',
  'token_type': 'bearer',
  'user_id': '9b0f0f4e-0000-4000-8000-000000000001',
  'email': 'anna@example.com',
  'name': 'Anna',
};

const _surveyJson = <String, Object?>{
  'id': '3f1d3f0e-6ba0-4b53-9b6f-1a2b3c4d5e6f',
  'address': 'Via Roma 1, Roma',
  'latitude': 41.90,
  'longitude': 12.50,
  'square_meters': 60.0,
  'avg_height': 2.7,
  'climate_zone': 'D',
  'wall_thickness': '30',
  'window_frame': 'PVC',
  'window_glass': 'doppio',
  'heating_type': 'autonomo',
  'generator_type': 'caldaia a condensazione',
  'generator_power_kw': 24.0,
  'generator_year': 2010,
  'estimated_class': 'D',
  'energy_score': 42.5,
  'status': 'draft',
  'created_at': '2026-09-23T01:00:00Z',
  'updated_at': '2026-09-23T02:00:00Z',
};

const _surveyId = '3f1d3f0e-6ba0-4b53-9b6f-1a2b3c4d5e6f';

String? headerOf(http.Request request, String name) {
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

http.Response _json(Object? body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

void main() {
  group('auth', () {
    test('register: POST /api/v1/auth/register, corpo JSON, nessun Bearer', () async {
      late http.Request captured;
      final client = ApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(_tokenJson, 201);
        }),
      );

      final auth = await client.register(
        email: 'anna@example.com',
        password: 'password123',
        name: 'Anna',
        acceptTerms: true,
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), '$_baseUrl/api/v1/auth/register');
      expect(headerOf(captured, 'content-type'), contains('application/json'));
      expect(headerOf(captured, 'authorization'), isNull,
          reason: 'l\'auth non è ancora autenticata');
      expect(jsonDecode(captured.body), <String, Object?>{
        'email': 'anna@example.com',
        'password': 'password123',
        'name': 'Anna',
        'accept_terms': true,
      });

      expect(auth.accessToken, 'jwt-test-token');
      expect(auth.tokenType, 'bearer');
      expect(auth.userId, '9b0f0f4e-0000-4000-8000-000000000001');
      expect(auth.email, 'anna@example.com');
      expect(client.token, 'jwt-test-token');
      expect(client.isAuthenticated, isTrue);
    });

    test('login: memorizza il JWT e lo invia su chiamate successive', () async {
      final seen = <http.Request>[];
      final client = ApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/auth/login')) {
            return _json(_tokenJson, 200);
          }
          return _json(_surveyJson, 200);
        }),
      );

      await client.login(email: 'anna@example.com', password: 'password123');
      await client.getSurvey(_surveyId);

      expect(seen, hasLength(2));
      expect(headerOf(seen[0], 'authorization'), isNull);
      expect(seen[1].method, 'GET');
      expect(seen[1].url.toString(), '$_baseUrl/api/v1/surveys/$_surveyId');
      expect(headerOf(seen[1], 'authorization'), 'Bearer jwt-test-token');
    });
  });

  group('surveys', () {
    test('createSurvey: POST snake_case, zero additional_photos finché riserva',
        () async {
      late http.Request captured;
      final client = ApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(_surveyJson, 201);
        }),
      );

      final created = await client.createSurvey(const SurveyCreate(
        address: 'Via Roma 1, Roma',
        squareMeters: 60,
        avgHeight: 2.7,
        wallThickness: '30',
        windowFrame: 'PVC',
        heatingType: 'autonomo',
        generatorType: 'caldaia a condensazione',
      ));

      expect(captured.method, 'POST');
      expect(captured.url.toString(), '$_baseUrl/api/v1/surveys');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.keys, containsAll(<String>[
        'address',
        'square_meters',
        'avg_height',
        'wall_thickness',
        'window_frame',
        'heating_type',
        'generator_type',
      ]));
      expect(body.containsKey('squareMeters'), isFalse,
          reason: 'il contratto parla solo snake_case');
      expect(body.containsKey('additional_photos'), isFalse,
          reason: 'riserva M8: finché non è nel contratto, zero invio');

      // Response → DTO
      expect(created.id, _surveyId);
      expect(created.status, 'draft');
      expect(created.createdAt, DateTime.parse('2026-09-23T01:00:00Z'));
      expect(created.updatedAt, DateTime.parse('2026-09-23T02:00:00Z'));
      expect(created.squareMeters, 60.0);
      expect(created.estimatedClass, 'D');
      expect(created.energyScore, 42.5);
      expect(created.additionalPhotos, isNull);
    });

    test('createSurvey: additional_photos inviato solo quando valorizzato', () async {
      late http.Request captured;
      final client = ApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(_surveyJson, 201);
        }),
      );

      await client.createSurvey(
        const SurveyCreate(additionalPhotos: ['a.jpg', 'b.jpg']),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['additional_photos'], <String>['a.jpg', 'b.jpg']);
    });

    test('updateSurvey: PUT parziale, i null non cancellano i campi', () async {
      late http.Request captured;
      final client = ApiClient(
        baseUrl: _baseUrl,
        client: MockClient((request) async {
          captured = request;
          return _json(_surveyJson, 200);
        }),
      );

      await client.updateSurvey(
        _surveyId,
        const SurveyCreate(address: 'Via Roma 2, Roma', squareMeters: 75),
      );

      expect(captured.method, 'PUT');
      expect(captured.url.toString(), '$_baseUrl/api/v1/surveys/$_surveyId');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.keys, <String>['address', 'square_meters'],
          reason: 'exclude_unset lato server: niente null sul wire');
    });

    test('SurveyRead.fromJson tollera i campi opzionali assenti', () {
      final read = SurveyRead.fromJson(<String, dynamic>{
        'id': _surveyId,
        'status': 'completed',
        'created_at': '2026-09-23T01:00:00Z',
        'updated_at': '2026-09-23T02:00:00Z',
      });
      expect(read.address, isNull);
      expect(read.userId, isNull,
          reason: 'user_id non è ancora nel contratto v1');
      expect(read.status, 'completed');
    });
  });

  group('error mapping', () {
    ApiClient clientReturning(int status, Object? body) => ApiClient(
          baseUrl: _baseUrl,
          client: MockClient((_) async => _json(body, status)),
        );

    test('401 → UnauthorizedException', () async {
      await expectLater(
        clientReturning(401, {'detail': 'Not authenticated'})
            .getSurvey(_surveyId),
        throwsA(isA<UnauthorizedException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Not authenticated')),
      );
    });

    test('404 → NotFoundException (non trovato o non di proprietà)', () async {
      await expectLater(
        clientReturning(404, {'detail': 'Survey not found'})
            .getSurvey(_surveyId),
        throwsA(isA<NotFoundException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.detail, 'detail', 'Survey not found')),
      );
    });

    test('422 → ValidationException con detail per campo', () async {
      await expectLater(
        clientReturning(422, {
          'detail': [
            {
              'loc': ['body', 'square_meters'],
              'msg': 'Input should be a valid number',
              'type': 'float_parsing',
            }
          ],
        }).createSurvey(const SurveyCreate()),
        throwsA(isA<ValidationException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.message, 'message',
                'Input should be a valid number')
            .having((e) => (e.detail as List).first['loc'], 'loc',
                ['body', 'square_meters'])),
      );
    });

    test('409 (email duplicata) → ApiException generica con lo status', () async {
      await expectLater(
        clientReturning(409, {'detail': 'Email already registered'})
            .register(
                email: 'a@b.it', password: 'password123', acceptTerms: true),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', 'Email already registered')),
      );
    });
  });

  group('timeout', () {
    test('risposta lenta → ApiTimeoutException con statusCode 0', () async {
      final client = ApiClient(
        baseUrl: _baseUrl,
        timeout: const Duration(milliseconds: 50),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return _json(_surveyJson, 200);
        }),
      );

      await expectLater(
        client.getSurvey(_surveyId),
        throwsA(isA<ApiTimeoutException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.message, 'message', contains('entro 50ms'))),
      );
    });
  });
}

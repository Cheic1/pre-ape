/// Pannello amministratore: AdminApi, is_admin in sessione, menu, elimina
/// utente, wizard in modalità admin.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/features/admin/admin_models.dart';
import 'package:pre_ape/features/admin/admin_pages.dart';
import 'package:pre_ape/features/admin/delete_user_dialog.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/surveys/survey_list_page.dart';
import 'package:pre_ape/models/survey.dart' show SurveyCreate;
import 'package:pre_ape/services/admin_api.dart';
import 'package:pre_ape/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'http://admin.test';

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object?> _survey(String id, {String? title}) => <String, Object?>{
      'id': id,
      'status': 'draft',
      'created_at': '2026-10-01T10:00:00',
      'updated_at': '2026-10-01T10:00:00',
      if (title != null) 'title': title,
    };

const _user = <String, Object?>{
  'id': 'u-2',
  'email': 'altro@example.test',
  'name': 'Altro Tecnico',
  'created_at': '2026-09-01T08:00:00',
  'last_login': '2026-10-17T18:30:00',
  'survey_count': 3,
  'document_count': 2,
  'is_admin': false,
};

const _doc = <String, Object?>{
  'id': 'd-1',
  'survey_id': 's-1',
  'kind': 'visura',
  'filename': 'visura.pdf',
  'mime_type': 'application/pdf',
  'size_bytes': 2048,
  'uploaded_by': {'id': 'u-2', 'email': 'altro@example.test', 'name': 'Altro'},
  'extracted': [],
  'created_at': '2026-10-02T09:15:00',
};

AdminApi _admin(MockClientHandler handler, {String? token = 'jwt-a'}) =>
    AdminApi(baseUrl: _base, token: () => token, client: MockClient(handler));

void main() {
  group('AdminApi', () {
    test('path, Bearer e parse di utenti/sopralluoghi/documenti/audit',
        () async {
      final seen = <String>[];
      final api = _admin((req) async {
        seen.add('${req.method} ${req.url.path}'
            '${req.url.hasQuery ? '?${req.url.query}' : ''}');
        expect(req.headers['Authorization'], 'Bearer jwt-a');
        final p = req.url.path;
        if (p == '/api/v1/admin/users') return _json([_user]);
        if (p.endsWith('/surveys') && p.contains('/users/')) {
          return _json([
            {..._survey('s-1', title: 'APE 1'), 'photo_count': 0}
          ]);
        }
        if (p.endsWith('/documents')) return _json([_doc]);
        if (p == '/api/v1/admin/audit') {
          return _json([
            {
              'id': '6f1c2a3e-0000-4000-8000-000000000007',
              'admin_email': 'boss@example.test',
              'action': 'delete_user',
              'target_type': 'user',
              'target_id': 'u-9',
              'detail': {'email': 'x@example.test', 'survey_count': 2},
              'created_at': '2026-10-18T10:00:00',
            }
          ]);
        }
        return http.Response('', 204);
      });

      final users = await api.listUsers();
      expect(users.single.email, 'altro@example.test');
      expect(users.single.surveyCount, 3);
      expect(users.single.documentCount, 2);
      expect(users.single.lastLogin, isNotNull);

      final surveys = await api.listUserSurveys('u-2');
      expect(surveys.single.title, 'APE 1');

      final docs = await api.listDocuments('s-1');
      expect(docs.single.uploadedBy!.email, 'altro@example.test');
      expect(docs.single.kindLabel, 'Visura');

      final audit = await api.listAudit(limit: 20, offset: 40);
      expect(audit.single.actionLabel, 'Eliminazione utente');
      expect(audit.single.id, '6f1c2a3e-0000-4000-8000-000000000007');
      expect(audit.single.detailText,
          'email: x@example.test · sopralluoghi: 2');

      await api.deleteSurvey('s-1');
      await api.deleteDocument('d-1');
      await api.deleteUser('u-2', confirmEmail: 'altro+x@example.test');

      expect(seen, [
        'GET /api/v1/admin/users',
        'GET /api/v1/admin/users/u-2/surveys',
        'GET /api/v1/admin/surveys/s-1/documents',
        'GET /api/v1/admin/audit?limit=20&offset=40',
        'DELETE /api/v1/admin/surveys/s-1',
        'DELETE /api/v1/admin/documents/d-1',
        'DELETE /api/v1/admin/users/u-2?confirm_email=altro%2Bx%40example.test',
      ]);
    });

    test('download: bytes, mime e nome dal Content-Disposition', () async {
      final api = _admin((req) async {
        expect(req.url.path, '/api/v1/admin/documents/d-1/content');
        return http.Response.bytes([0x25, 0x50, 0x44, 0x46], 200, headers: {
          'content-type': 'application/pdf',
          'content-disposition':
              "attachment; filename*=UTF-8''visura%20catastale.pdf",
        });
      });
      final file = await api.downloadDocument('d-1');
      expect(file.bytes, [0x25, 0x50, 0x44, 0x46]);
      expect(file.mimeType, 'application/pdf');
      expect(file.filename, 'visura catastale.pdf');
    });

    test('403 → ForbiddenException, 401 → UnauthorizedException', () async {
      final forbidden =
          _admin((_) async => _json({'detail': 'Admin only'}, 403));
      await expectLater(forbidden.listUsers(),
          throwsA(isA<ForbiddenException>().having((e) => e.statusCode, 'status', 403)));

      final expired =
          _admin((_) async => _json({'detail': 'Not authenticated'}, 401));
      await expectLater(
          expired.listAudit(), throwsA(isA<UnauthorizedException>()));
      await expectLater(expired.downloadDocument('d'),
          throwsA(isA<UnauthorizedException>()));
    });

    test('get/update sopralluogo su /admin/surveys/{id}', () async {
      final seen = <String>[];
      final api = _admin((req) async {
        seen.add('${req.method} ${req.url.path}');
        return _json(_survey('s-1', title: 'APE'));
      });
      final s = await api.getSurvey('s-1');
      await AdminSurveyClient(api)
          .updateSurvey(s.id, const SurveyCreate(title: 'APE 2'));
      expect(seen, ['GET /api/v1/admin/surveys/s-1', 'PUT /api/v1/admin/surveys/s-1']);
    });

    test('AdminApi.from condivide base URL e token con ApiClient', () async {
      final main = ApiClient(baseUrl: _base);
      String? auth;
      final admin = AdminApi.from(main, client: MockClient((req) async {
        auth = req.headers['Authorization'];
        return _json([]);
      }));
      main.setToken('jwt-nuovo');
      await admin.listUsers();
      expect(auth, 'Bearer jwt-nuovo');
    });
  });

  group('AuthNotifier – is_admin', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('login admin: is_admin persistito e ripristinato', () async {
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((_) async => _json({
              'access_token': 'jwt-a',
              'token_type': 'bearer',
              'user_id': 'u-1',
              'email': 'boss@example.test',
              'name': 'Boss',
              'is_admin': true,
            })),
      );
      final auth = AuthNotifier(api);
      expect(await auth.login('boss@example.test', 'password1'), isTrue);
      expect(auth.user!.isAdmin, isTrue);

      final restored = AuthNotifier(ApiClient(baseUrl: _base));
      await restored.restore();
      expect(restored.user!.isAdmin, isTrue);

      await restored.logout();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('preape.is_admin'), isNull);
    });

    test('sessione salvata prima del pannello: non admin', () async {
      SharedPreferences.setMockInitialValues({
        'preape.token': 'jwt-old',
        'preape.user_id': 'u-1',
        'preape.email': 'geo@example.test',
        'preape.name': 'Geo',
      });
      final auth = AuthNotifier(ApiClient(baseUrl: _base));
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user!.isAdmin, isFalse);
    });
  });

  group('SurveyListPage – menu Amministrazione', () {
    Future<void> pumpList(WidgetTester tester, {required bool admin}) async {
      SharedPreferences.setMockInitialValues({
        'preape.token': 'jwt-a',
        'preape.user_id': 'u-1',
        'preape.email': 'boss@example.test',
        'preape.name': 'Boss',
        'preape.is_admin': admin,
      });
      final api = ApiClient(
        baseUrl: _base,
        client: MockClient((req) async => _json([])),
      );
      final auth = AuthNotifier(api);
      await auth.restore();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authProvider.overrideWith((ref) => auth),
          adminApiProvider.overrideWithValue(_admin((req) async {
            expect(req.url.path, '/api/v1/admin/users');
            return _json([_user]);
          })),
        ],
        child: const MaterialApp(home: SurveyListPage()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
    }

    testWidgets('visibile per un amministratore e apre gli utenti',
        (tester) async {
      await pumpList(tester, admin: true);
      expect(find.text('Amministrazione'), findsOneWidget);
      await tester.tap(find.text('Amministrazione'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminUsersPage), findsOneWidget);
      expect(find.text('altro@example.test'), findsOneWidget);
      expect(find.textContaining('3 sopralluoghi · 2 documenti'), findsOneWidget);
    });

    testWidgets('nascosto per un utente normale', (tester) async {
      await pumpList(tester, admin: false);
      expect(find.text('Esci'), findsOneWidget);
      expect(find.text('Amministrazione'), findsNothing);
    });
  });

  group('Elimina utente', () {
    testWidgets('il pulsante si abilita solo con l\'email esatta',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showDeleteUserDialog(context, 'altro@example.test'),
            child: const Text('apri'),
          ),
        ),
      ));
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();

      FilledButton button() => tester.widget<FilledButton>(
          find.byKey(const ValueKey('delete_user_confirm')));
      expect(button().onPressed, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('delete_user_email')), 'altro@example');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('delete_user_email')),
          'ALTRO@example.test');
      await tester.pump();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('delete_user_email')),
          'altro@example.test');
      await tester.pump();
      expect(button().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('delete_user_confirm')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    Future<List<String>> pumpUserPage(WidgetTester tester,
        {required String meEmail, List<String>? calls}) async {
      SharedPreferences.setMockInitialValues({
        'preape.token': 'jwt-a',
        'preape.user_id': 'u-1',
        'preape.email': meEmail,
        'preape.name': 'Boss',
        'preape.is_admin': true,
      });
      final seen = calls ?? <String>[];
      final api = ApiClient(baseUrl: _base);
      final auth = AuthNotifier(api);
      await auth.restore();
      final admin = _admin((req) async {
        seen.add('${req.method} ${req.url.path}'
            '${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.method == 'GET' && req.url.path.endsWith('/surveys')) {
          return _json([
            {..._survey('s-1', title: 'APE Rossi'), 'photo_count': 0}
          ]);
        }
        if (req.method == 'GET' && req.url.path == '/api/v1/admin/surveys/s-1') {
          return _json(_survey('s-1', title: 'APE Rossi'));
        }
        if (req.method == 'PUT') {
          return _json(_survey('s-1', title: 'APE Rossi'));
        }
        return http.Response('', 204);
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authProvider.overrideWith((ref) => auth),
          adminApiProvider.overrideWithValue(admin),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    AdminUserSurveysPage(user: AdminUser.fromJson(_user)),
              )),
              child: const Text('apri'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('flusso completo: conferma con email → DELETE con confirm_email',
        (tester) async {
      final calls = await pumpUserPage(tester, meEmail: 'boss@example.test');
      await tester.tap(find.byKey(const ValueKey('admin_delete_user')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('delete_user_email')),
          'altro@example.test');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('delete_user_confirm')));
      await tester.pumpAndSettle();
      expect(calls.last,
          'DELETE /api/v1/admin/users/u-2?confirm_email=altro%40example.test');
      expect(find.byType(AdminUserSurveysPage), findsNothing);
    });

    testWidgets('nascosto sul proprio account', (tester) async {
      await pumpUserPage(tester, meEmail: 'altro@example.test');
      expect(find.byKey(const ValueKey('admin_delete_user')), findsNothing);
    });

    testWidgets('elimina sopralluogo solo dopo conferma', (tester) async {
      final calls = await pumpUserPage(tester, meEmail: 'boss@example.test');
      await tester.tap(find.byKey(const ValueKey('admin_delete_survey_s-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('DELETE')), isEmpty);

      await tester.tap(find.byKey(const ValueKey('admin_delete_survey_s-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm_delete')));
      await tester.pumpAndSettle();
      expect(calls, contains('DELETE /api/v1/admin/surveys/s-1'));
    });

    testWidgets('wizard in modalità admin: GET e PUT su /admin/surveys/{id}',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final calls = await pumpUserPage(tester, meEmail: 'boss@example.test');
      await tester.tap(find.text('APE Rossi'));
      await tester.pumpAndSettle();
      expect(calls, contains('GET /api/v1/admin/surveys/s-1'));
      expect(find.byKey(const ValueKey('wizard_save')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('wizard_save')));
      await tester.pumpAndSettle();
      expect(calls, contains('PUT /api/v1/admin/surveys/s-1'));
      expect(calls.where((c) => c.startsWith('PUT /api/v1/surveys')), isEmpty);
    });
  });

  group('Documenti e registro', () {
    testWidgets('documenti: caricato da + data; registro paginato',
        (tester) async {
      final seen = <String>[];
      final admin = _admin((req) async {
        seen.add('${req.url.path}?${req.url.query}');
        if (req.url.path.endsWith('/documents')) return _json([_doc]);
        final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
        return _json([
          for (var i = 0; i < (offset == 0 ? 2 : 1); i++)
            {
              'id': 'a-${offset + i}',
              'admin_email': 'boss@example.test',
              'action': 'view_survey',
              'target_type': 'survey',
              'target_id': 's-$i',
              'detail': {'owner_email': 'altro@example.test'},
              'created_at': '2026-10-18T10:00:00',
            }
        ]);
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [adminApiProvider.overrideWithValue(admin)],
        child: const MaterialApp(
          home: AdminDocumentsPage(surveyId: 's-1', surveyTitle: 'APE'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('visura.pdf'), findsOneWidget);
      expect(find.textContaining('Caricato da altro@example.test il 02/10/2026'),
          findsOneWidget);

      await tester.pumpWidget(ProviderScope(
        overrides: [adminApiProvider.overrideWithValue(admin)],
        child: const MaterialApp(home: AdminAuditPage(pageSize: 2)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Apertura sopralluogo'), findsNWidgets(2));
      expect(find.textContaining('proprietario: altro@example.test'),
          findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('audit_more')));
      await tester.pumpAndSettle();
      expect(find.text('Apertura sopralluogo'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('audit_more')), findsNothing);
      expect(seen, contains('/api/v1/admin/audit?limit=2&offset=2'));
    });
  });
}

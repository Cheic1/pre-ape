/// Widget: sezione "Dati catastali" (step 1) e card "Scheda CENED" (step 6),
/// contro un backend finto (`MockClient`).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/catasto_section.dart';
import 'package:pre_ape/features/onboarding/cened_sheet_card.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

http.Response _json(Object? body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _surveyJson(String id) => {
      'id': id,
      'status': 'draft',
      'created_at': '2026-10-18T10:00:00Z',
      'updated_at': '2026-10-18T10:00:00Z',
    };

Map<String, Object?> _doc(String id, String kind,
        {List<Map<String, Object?>>? extracted}) =>
    {
      'id': id,
      'survey_id': 's-1',
      'kind': kind,
      'filename': '$kind.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 2048,
      'uploaded_by': {'id': 'u-1', 'email': 'anna@example.com', 'name': 'Anna'},
      'extracted': extracted,
      'created_at': '2026-10-18T10:00:00Z',
    };

/// Backend finto: registra le richieste, risponde da [routes] ("METHOD path").
class _FakeBackend {
  _FakeBackend(this.routes);

  final Map<String, http.Response Function(http.Request)> routes;
  final List<http.Request> requests = [];

  ApiClient client() => ApiClient(
        baseUrl: 'http://t',
        client: MockClient((r) async {
          requests.add(r);
          final h = routes['${r.method} ${r.url.path}'];
          return h == null ? _json({'detail': 'Not Found'}, 404) : h(r);
        }),
      );

  List<String> get calls =>
      requests.map((r) => '${r.method} ${r.url.path}').toList();
}

Future<SurveyNotifier> _pump(WidgetTester tester, Widget child, ApiClient api,
    {SurveyNotifier? notifier}) async {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      if (notifier != null) surveyProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)))
      .read(surveyProvider);
}

const _visuraUnits = [
  {'comune': 'Milano', 'foglio': '12', 'particella': '345', 'subalterno': '6', 'categoria': 'A/2', 'rendita_euro': 1032.91},
  {'comune': 'Milano', 'foglio': '12', 'particella': '345', 'subalterno': '7', 'categoria': 'C/6'},
];

Future<PickedDocument?> _pickPdf() async =>
    (dataUrl: 'data:application/pdf;base64,JVBERi0xLjQ=', name: 'visura.pdf');

void main() {
  group('CatastoSection', () {
    testWidgets('aggiungi, compila e rimuovi unità', (tester) async {
      final backend = _FakeBackend({});
      final n = await _pump(tester, const CatastoSection(), backend.client());

      expect(find.text('Nessuna unità inserita.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cadastral_add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cadastral_add')));
      await tester.pump();
      expect(n.data.cadastral, hasLength(2));
      expect(find.text('Unità 2'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('cadastral_0_foglio')), '12');
      await tester.enterText(
          find.byKey(const ValueKey('cadastral_1_foglio')), '99');
      await tester.enterText(
          find.byKey(const ValueKey('cadastral_0_rendita_euro')), '1.032,91');
      await tester.pump();
      expect(n.data.cadastral[0].foglio, '12');
      expect(n.data.cadastral[0].renditaEuro, 1032.91);
      expect(n.dirty, isTrue);

      await tester.tap(find.byKey(const ValueKey('cadastral_remove_0')));
      await tester.pumpAndSettle();
      expect(n.data.cadastral, hasLength(1));
      expect(n.data.cadastral.single.foglio, '99');
      // Il campo dell'indice 0 mostra ora la seconda unità.
      final field = tester.widget<TextField>(
          find.byKey(const ValueKey('cadastral_0_foglio')));
      expect(field.controller!.text, '99');
      expect(backend.requests, isEmpty);
    });

    testWidgets('carica visura su sopralluogo nuovo: salva prima, poi applica la proposta',
        (tester) async {
      final backend = _FakeBackend({
        'POST /api/v1/surveys': (_) => _json(_surveyJson('s-1'), 201),
        'POST /api/v1/surveys/s-1/documents': (_) =>
            _json(_doc('d-1', 'visura', extracted: _visuraUnits), 201),
        'GET /api/v1/surveys/s-1/documents': (_) => _json([], 200),
      });
      final n = await _pump(
          tester, const CatastoSection(pickFile: _pickPdf), backend.client());
      n.addCadastralUnit(); // vuota: verrà sostituita

      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_upload')));
      await tester.pumpAndSettle();
      expect(find.text('Estratto di mappa'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('document_kind_visura')));
      await tester.pumpAndSettle();

      expect(backend.calls.take(2), [
        'POST /api/v1/surveys',
        'POST /api/v1/surveys/s-1/documents',
      ]);
      final upload = backend.requests
          .firstWhere((r) => r.url.path.endsWith('/documents') && r.method == 'POST');
      expect(jsonDecode(upload.body), {
        'kind': 'visura',
        'filename': 'visura.pdf',
        'content_base64': 'JVBERi0xLjQ=',
      });
      expect(n.data.surveyId, 's-1');
      expect(find.byKey(const ValueKey('document_d-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('visura_proposal')), findsOneWidget);
      expect(find.textContaining('2 unità trovate'), findsOneWidget);
      // L'anteprima non tocca ancora i dati.
      expect(n.data.cadastral.single.isEmpty, isTrue);

      await tester.tap(find.byKey(const ValueKey('visura_apply')));
      await tester.pumpAndSettle();
      expect(n.data.cadastral, hasLength(2));
      expect(n.data.cadastral[0].categoria, 'A/2');
      expect(n.data.cadastral[1].subalterno, '7');
      expect(find.byKey(const ValueKey('visura_proposal')), findsNothing);
      final f = tester.widget<TextField>(
          find.byKey(const ValueKey('cadastral_0_foglio')));
      expect(f.controller!.text, '12');
    });

    testWidgets('elenca, scarica ed elimina i documenti del sopralluogo',
        (tester) async {
      final backend = _FakeBackend({
        'GET /api/v1/surveys/s-1/documents': (_) =>
            _json([_doc('d-1', 'planimetria')], 200),
        'GET /api/v1/documents/d-1/content': (_) =>
            http.Response.bytes([0x25, 0x50], 200),
        'DELETE /api/v1/documents/d-1': (_) => http.Response('', 204),
      });
      final n = await _pump(tester, const CatastoSection(), backend.client());
      n.loadFrom(SurveyRead.fromJson(_surveyJson('s-1')));
      await tester.pumpAndSettle();

      expect(find.text('planimetria.pdf'), findsOneWidget);
      expect(find.textContaining('Planimetria · 2 KB'), findsOneWidget);
      expect(find.textContaining('Anna'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('document_download_d-1')));
      await tester.pumpAndSettle();
      expect(backend.calls, contains('GET /api/v1/documents/d-1/content'));

      await tester.tap(find.byKey(const ValueKey('document_delete_d-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_delete_confirm')));
      await tester.pumpAndSettle();
      expect(backend.calls, contains('DELETE /api/v1/documents/d-1'));
      expect(find.text('planimetria.pdf'), findsNothing);
    });

    testWidgets('errore 415 in upload → messaggio leggibile', (tester) async {
      final backend = _FakeBackend({
        'GET /api/v1/surveys/s-1/documents': (_) => _json([], 200),
        'POST /api/v1/surveys/s-1/documents': (_) =>
            _json({'detail': 'Formato non supportato'}, 415),
      });
      final n = await _pump(
          tester, const CatastoSection(pickFile: _pickPdf), backend.client());
      n.loadFrom(SurveyRead.fromJson(_surveyJson('s-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('document_kind_altro')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Formato non supportato: carica un PDF'),
          findsOneWidget);
    });
  });

  group('CenedSheetCard', () {
    final sheetJson = {
      'survey_id': 's-1',
      'generated_at': '2026-10-18T10:00:00Z',
      'disclaimer': 'Stima preliminare: non sostituisce l\'APE.',
      'sections': [
        {
          'key': 'edificio',
          'title': 'Edificio e localizzazione',
          'rows': [
            {'label': 'Comune', 'value': 'Milano', 'cened_field': 'servizioDatiClimatici@codiceIstat', 'status': 'ok'},
            {'label': 'Anno di costruzione', 'value': 1970, 'cened_field': null, 'status': 'stimato'},
            {'label': 'Numero di piani', 'value': null, 'cened_field': null, 'status': 'da_rilevare'},
          ],
        },
      ],
    };

    testWidgets('sopralluogo salvato: carica la scheda, evidenzia i dati da rilevare',
        (tester) async {
      final backend = _FakeBackend({
        'GET /api/v1/surveys/s-1/cened-sheet': (_) => _json(sheetJson, 200),
      });
      final n = SurveyNotifier()
        ..loadFrom(SurveyRead.fromJson(_surveyJson('s-1')));
      await _pump(tester, const CenedSheetCard(), backend.client(), notifier: n);

      expect(find.text('Scheda CENED'), findsOneWidget);
      expect(find.textContaining('Stima preliminare'), findsOneWidget);
      expect(find.text('Milano'), findsOneWidget);
      expect(find.text('servizioDatiClimatici@codiceIstat'), findsOneWidget);
      expect(find.text('stimato'), findsOneWidget);
      expect(find.text('da rilevare'), findsOneWidget);
      expect(find.text('1 dato da rilevare (evidenziati).'), findsOneWidget);

      BoxDecoration deco(String key) => tester
          .widget<Container>(find
              .descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(Container))
              .first)
          .decoration! as BoxDecoration;
      expect(deco('cened_row_edificio_2').color,
          AppColors.warning.withValues(alpha: 0.12));
      expect(deco('cened_row_edificio_0').color, isNull);
    });

    testWidgets('sopralluogo nuovo: "Genera" salva prima e poi carica',
        (tester) async {
      final backend = _FakeBackend({
        'POST /api/v1/surveys': (_) => _json(_surveyJson('s-1'), 201),
        'GET /api/v1/surveys/s-1/cened-sheet': (_) => _json(sheetJson, 200),
      });
      await _pump(tester, const CenedSheetCard(), backend.client());
      expect(backend.requests, isEmpty);
      expect(find.text('Genera'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cened_load')));
      await tester.pumpAndSettle();
      expect(backend.calls, [
        'POST /api/v1/surveys',
        'GET /api/v1/surveys/s-1/cened-sheet',
      ]);
      expect(find.text('Aggiorna'), findsOneWidget);
      expect(find.text('Numero di piani'), findsOneWidget);
    });
  });
}

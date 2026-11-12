/// Planimetria → disegno CAD: DTO `FloorPlan`, API client e pagina
/// `FloorPlanPage` (anteprima 2D/3D, ricalcolo, download) su backend finto.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/planimetria/floor_plan_page.dart';
import 'package:pre_ape/features/planimetria/floor_plan_view.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

http.Response _json(Object? body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

List<List<double>> _rect(double x0, double y0, double x1, double y1) =>
    [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];

Map<String, Object?> _planJson({int scale = 200, double height = 2.7}) => {
      'version': 1,
      'source': 'cv',
      'page': 0,
      'scale_denominator': scale,
      'meters_per_px': 0.0169,
      'wall_height_m': height,
      'image_width_px': 2480,
      'image_height_px': 3508,
      'origin_px': [400.0, 2600.0],
      'walls': [
        {
          'outer': _rect(0, 0, 10, 8),
          'holes': [_rect(0.3, 0.3, 9.7, 7.7)],
        },
      ],
      'footprint': [
        {'outer': _rect(0, 0, 10, 8), 'holes': <Object>[]},
      ],
      'rooms': [
        {
          'polygon': _rect(0.3, 0.3, 9.7, 7.7),
          'area_m2': 69.56,
          'label_point': [5.0, 4.0],
        },
      ],
      'openings': [
        {'kind': 'finestra', 'polygon': _rect(2, 0, 3.2, 0.3), 'width_m': 1.2, 'exterior': true},
        {'kind': 'porta', 'polygon': _rect(6, 7.7, 6.9, 8), 'width_m': 0.9, 'exterior': true},
      ],
      'stats': {
        'gross_area_m2': 80.0,
        'net_area_m2': 69.56,
        'perimeter_m': 36.0,
        'rooms': 1,
        'doors': 1,
        'windows': 1,
        'windows_width_m': 1.2,
      },
      'warnings': ['Scala non trovata nel documento: assunta 1:200, da verificare.'],
    };

DocumentMeta _doc({Map<String, Object?>? cadStats}) => DocumentMeta.fromJson({
      'id': 'd-1',
      'survey_id': 's-1',
      'kind': 'planimetria',
      'filename': 'pianta.pdf',
      'mime_type': 'application/pdf',
      'size_bytes': 2048,
      'cad_stats': cadStats,
      'created_at': '2026-11-12T10:00:00Z',
    });

class _Backend {
  _Backend(this.routes);

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

Future<void> _pump(WidgetTester tester, Widget page, ApiClient api) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(home: page),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('FloorPlan DTO', () {
    test('parse completo', () {
      final plan = FloorPlan.fromJson(_planJson());
      expect(plan.scaleDenominator, 200);
      expect(plan.walls.single.holes.single, hasLength(4));
      expect(plan.rooms.single.labelPoint, const Offset(5, 4));
      expect(plan.openings.where((o) => o.isWindow), hasLength(1));
      expect(plan.stats.grossAreaM2, 80);
      expect(plan.warnings, hasLength(1));
      expect(planBounds(plan), const Rect.fromLTRB(0, 0, 10, 8));
    });

    test('DocumentMeta: cad_stats e supportsCad', () {
      final doc = _doc(cadStats: (_planJson()['stats'] as Map<String, Object?>));
      expect(doc.supportsCad, isTrue);
      expect(doc.cadStats!.rooms, 1);
      expect(_doc().cadStats, isNull);
    });
  });

  group('ApiClient', () {
    test('extractCad invia solo i parametri impostati', () async {
      final backend = _Backend({
        'POST /api/v1/documents/d-1/cad': (r) => _json(_planJson(scale: 100), 200),
      });
      final plan = await backend
          .client()
          .extractCad('d-1', scaleDenominator: 100, wallHeightM: 3.0);
      expect(plan.scaleDenominator, 100);
      expect(jsonDecode(backend.requests.single.body),
          {'scale_denominator': 100, 'wall_height_m': 3.0});
    });

    test('downloadCad usa il nome da Content-Disposition', () async {
      final backend = _Backend({
        'GET /api/v1/documents/d-1/cad.dxf': (r) => http.Response('0\nSECTION', 200,
            headers: {'content-disposition': "attachment; filename*=UTF-8''pianta_cad.dxf"}),
      });
      final file = await backend.client().downloadCad('d-1', 'dxf');
      expect(file.filename, 'pianta_cad.dxf');
      expect(utf8.decode(file.bytes), startsWith('0'));
    });
  });

  group('FloorPlanPage', () {
    testWidgets('estrae, mostra 2D/3D, ricalcola e scarica', (tester) async {
      final backend = _Backend({
        'POST /api/v1/documents/d-1/cad': (r) {
          final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map;
          return _json(
              _planJson(
                  scale: (body['scale_denominator'] as int?) ?? 200,
                  height: (body['wall_height_m'] as num?)?.toDouble() ?? 2.7),
              200);
        },
        'GET /api/v1/documents/d-1/cad.dxf': (r) => http.Response('dxf', 200,
            headers: {'content-disposition': "attachment; filename*=UTF-8''pianta_cad.dxf"}),
      });
      final saved = <String>[];
      await _pump(
        tester,
        FloorPlanPage(
          document: _doc(),
          saveFile: (name, Uint8List bytes, mime) => saved.add('$name $mime'),
        ),
        backend.client(),
      );

      expect(backend.calls, ['POST /api/v1/documents/d-1/cad']);
      expect(find.text('80,00 m²'), findsOneWidget);
      expect(find.textContaining('Scala non trovata'), findsOneWidget);
      expect(find.byType(FloorPlan3DView), findsNothing);

      await tester.tap(find.text('Modello 3D'));
      await tester.pumpAndSettle();
      expect(find.byType(FloorPlan3DView), findsOneWidget);
      await tester.drag(find.byType(FloorPlan3DView), const Offset(60, 20));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('cad_scale')), '100');
      await tester.enterText(find.byKey(const ValueKey('cad_height')), '3,1');
      await tester.tap(find.byKey(const ValueKey('cad_recompute')));
      await tester.pumpAndSettle();
      expect(jsonDecode(backend.requests.last.body),
          {'scale_denominator': 100, 'wall_height_m': 3.1});

      await tester.tap(find.byKey(const ValueKey('cad_download_dxf')));
      await tester.pumpAndSettle();
      expect(saved, ['pianta_cad.dxf image/vnd.dxf']);
    });

    testWidgets('già estratto: legge il disegno salvato', (tester) async {
      final backend = _Backend({
        'GET /api/v1/documents/d-1/cad': (r) => _json(_planJson(), 200),
      });
      await _pump(
        tester,
        FloorPlanPage(
            document: _doc(cadStats: _planJson()['stats'] as Map<String, Object?>)),
        backend.client(),
      );
      expect(backend.calls, ['GET /api/v1/documents/d-1/cad']);
      expect(find.text('Pianta 2D'), findsOneWidget);
    });

    testWidgets('nessun muro: messaggio del server', (tester) async {
      final backend = _Backend({
        'POST /api/v1/documents/d-1/cad': (r) =>
            _json({'detail': 'Nessun muro riconosciuto nella planimetria'}, 422),
      });
      await _pump(tester, FloorPlanPage(document: _doc()), backend.client());
      expect(find.byKey(const ValueKey('cad_error')), findsOneWidget);
      expect(find.text('Nessun muro riconosciuto nella planimetria'), findsOneWidget);
    });
  });
}

/// Endpoint documenti catastali + scheda CENED con `MockClient`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/services/api_client.dart';

const _base = 'http://contract.test';

const _docJson = <String, Object?>{
  'id': 'd-1',
  'survey_id': 's-1',
  'kind': 'visura',
  'filename': 'visura.pdf',
  'mime_type': 'application/pdf',
  'size_bytes': 5,
  'uploaded_by': {'id': 'u-1', 'email': 'anna@example.com', 'name': 'Anna'},
  'extracted': [
    {'foglio': '12', 'particella': '345', 'subalterno': '6'},
  ],
  'created_at': '2026-10-18T10:00:00Z',
};

http.Response _json(Object? body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json'},
    );

String? _header(http.Request r, String name) => r.headers.entries
    .where((e) => e.key.toLowerCase() == name)
    .map((e) => e.value)
    .firstOrNull;

ApiClient _client(Future<http.Response> Function(http.Request) handler,
    {List<http.Request>? seen}) {
  final api = ApiClient(
    baseUrl: _base,
    client: MockClient((r) {
      seen?.add(r);
      return handler(r);
    }),
  );
  api.setToken('jwt');
  return api;
}

void main() {
  test('uploadDocument: POST JSON {kind, filename, content_base64} con Bearer',
      () async {
    final seen = <http.Request>[];
    final api = _client((_) async => _json(_docJson, 201), seen: seen);
    final meta = await api.uploadDocument('s-1',
        kind: 'visura', filename: 'visura.pdf', contentBase64: 'JVBERi0=');

    final r = seen.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), '$_base/api/v1/surveys/s-1/documents');
    expect(_header(r, 'authorization'), 'Bearer jwt');
    expect(_header(r, 'content-type'), contains('application/json'));
    expect(jsonDecode(r.body), {
      'kind': 'visura',
      'filename': 'visura.pdf',
      'content_base64': 'JVBERi0=',
    });
    expect(meta.id, 'd-1');
    expect(meta.extracted!.single.subalterno, '6');
  });

  test('listDocuments: GET lista di DocumentMeta', () async {
    final seen = <http.Request>[];
    final api = _client((_) async => _json([_docJson], 200), seen: seen);
    final docs = await api.listDocuments('s-1');
    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), '$_base/api/v1/surveys/s-1/documents');
    expect(docs.single.filename, 'visura.pdf');
  });

  test('downloadDocument: byte grezzi, Bearer', () async {
    final seen = <http.Request>[];
    final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0xFF, 0x00]);
    final api = _client(
        (_) async => http.Response.bytes(bytes, 200,
            headers: const {'content-type': 'application/pdf'}),
        seen: seen);
    final got = await api.downloadDocument('d-1');
    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), '$_base/api/v1/documents/d-1/content');
    expect(_header(seen.single, 'authorization'), 'Bearer jwt');
    expect(got, bytes);
  });

  test('deleteDocument: DELETE → 204', () async {
    final seen = <http.Request>[];
    final api = _client((_) async => http.Response('', 204), seen: seen);
    await api.deleteDocument('d-1');
    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.toString(), '$_base/api/v1/documents/d-1');
  });

  test('getCenedSheet: GET /surveys/{id}/cened-sheet', () async {
    final seen = <http.Request>[];
    final api = _client(
        (_) async => _json({
              'survey_id': 's-1',
              'generated_at': '2026-10-18T10:00:00Z',
              'disclaimer': 'Stima preliminare',
              'sections': [
                {
                  'key': 'edificio',
                  'title': 'Edificio',
                  'rows': [
                    {'label': 'Comune', 'value': null, 'cened_field': null, 'status': 'da_rilevare'},
                  ],
                },
              ],
            }, 200),
        seen: seen);
    final sheet = await api.getCenedSheet('s-1');
    expect(seen.single.url.toString(), '$_base/api/v1/surveys/s-1/cened-sheet');
    expect(sheet.sections.single.rows.single.missing, isTrue);
  });

  group('errori', () {
    test('401 → UnauthorizedException (upload, download, cened)', () async {
      final api =
          _client((_) async => _json({'detail': 'Token non valido'}, 401));
      await expectLater(
          api.uploadDocument('s-1',
              kind: 'altro', filename: 'a.png', contentBase64: 'AA=='),
          throwsA(isA<UnauthorizedException>()));
      await expectLater(api.downloadDocument('d-1'),
          throwsA(isA<UnauthorizedException>()));
      await expectLater(
          api.getCenedSheet('s-1'), throwsA(isA<UnauthorizedException>()));
      await expectLater(
          api.listDocuments('s-1'), throwsA(isA<UnauthorizedException>()));
    });

    test('404 su download/delete → NotFoundException', () async {
      final api = _client((_) async => _json({'detail': 'Not found'}, 404));
      await expectLater(
          api.downloadDocument('x'), throwsA(isA<NotFoundException>()));
      await expectLater(
          api.deleteDocument('x'), throwsA(isA<NotFoundException>()));
    });

    test('413/415/409 → ApiException con status e detail', () async {
      for (final status in [413, 415, 409]) {
        final api = _client((_) async => _json({'detail': 'no $status'}, status));
        await expectLater(
          api.uploadDocument('s-1',
              kind: 'altro', filename: 'a.bin', contentBase64: 'AA=='),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having((e) => e.message, 'message', 'no $status')),
        );
      }
    });

    test('download: errore non JSON → ApiException con lo status', () async {
      final api = _client((_) async => http.Response('boom', 500));
      await expectLater(
          api.downloadDocument('d-1'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)));
    });

    test('download: errore di rete → ApiException(0)', () async {
      final api = _client((_) async => throw http.ClientException('offline'));
      await expectLater(
          api.downloadDocument('d-1'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 0)));
    });
  });
}

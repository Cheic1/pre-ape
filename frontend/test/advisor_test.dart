/// Agente consulente: client API (MockClient) e parsing della risposta.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pre_ape/services/api_client.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('advisorEnabled: true solo se il server lo dice, false sugli errori', () async {
    final on = ApiClient(
        baseUrl: 'http://t',
        client: MockClient((r) async => _json({'enabled': true, 'modello': 'm'})));
    expect(await on.advisorEnabled(), isTrue);
    final off = ApiClient(
        baseUrl: 'http://t', client: MockClient((r) async => _json({'detail': 'x'}, 500)));
    expect(await off.advisorEnabled(), isFalse);
  });

  test('advisor: POST con il body della stima e raccomandazioni con i numeri', () async {
    late http.Request sent;
    final api = ApiClient(
      baseUrl: 'http://t',
      client: MockClient((r) async {
        sent = r;
        return _json({
          'sintesi': 'Partire dal tetto.',
          'raccomandazioni': [
            {'rif': 'copertura', 'titolo': 'Isolare il sottotetto', 'motivazione': 'Rientro rapido',
             'classe': 'F', 'investimento_eur': 8800, 'incentivo_eur': 4400,
             'investimento_netto_eur': 4400, 'risparmio_annuo_eur': 987,
             'tempo_ritorno_anni': 8.9, 'tempo_ritorno_netto_anni': 6.2},
          ],
          'avvertenze': ['Verificare i massimali'],
          'nota': 'Valori indicativi',
        });
      }),
    );
    final r = await api.advisor({'square_meters': 80});
    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/v1/advisor');
    expect(jsonDecode(sent.body), {'square_meters': 80});
    expect(r.sintesi, 'Partire dal tetto.');
    expect(r.raccomandazioni.single.incentivoEur, 4400);
    expect(r.raccomandazioni.single.tempoRitornoNettoAnni, 6.2);
    expect(r.avvertenze, ['Verificare i massimali']);
  });

  test('advisor: 503 diventa ApiException con il messaggio del server', () async {
    final api = ApiClient(
        baseUrl: 'http://t',
        client: MockClient((r) async => _json({'detail': 'Agente consulente non configurato'}, 503)));
    expect(() => api.advisor({}), throwsA(isA<ApiException>()));
  });
}

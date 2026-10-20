import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/survey.dart';

final _sheet = CenedSheet.fromJson({
  'survey_id': 's-1',
  'generated_at': '2026-10-18T10:00:00Z',
  'disclaimer': 'Stima preliminare <indicativa>',
  'sections': [
    {
      'key': 'edificio',
      'title': 'Edificio & localizzazione',
      'rows': [
        {'label': 'Comune', 'value': 'Milano', 'cened_field': 'servizioDatiClimatici@codiceIstat', 'status': 'ok'},
        {'label': 'Anno', 'value': 1970, 'cened_field': null, 'status': 'stimato'},
        {'label': 'Piani <b>', 'value': null, 'cened_field': null, 'status': 'da_rilevare'},
      ],
    },
  ],
});

void main() {
  test('report: tabella dati catastali con escape HTML', () {
    final s = SurveyData()
      ..cadastral = [
        const CadastralUnit(
          comune: 'Milano',
          codiceComune: 'F205',
          provincia: 'MI',
          foglio: '12',
          particella: '<script>',
          subalterno: '6',
          categoria: 'A/2',
          superficieMq: 95,
          renditaEuro: 1032.91,
          indirizzo: 'Via "Roma" 1',
          piano: '2',
        ),
        const CadastralUnit(), // vuota: non compare
      ];
    final html = buildReportHtml(s);
    expect(html, contains('<h2>Dati catastali</h2>'));
    expect(html, contains('&lt;script&gt;'));
    expect(html, isNot(contains('<script>')));
    expect(html, contains('Milano (F205) MI'));
    expect(html, contains('€ 1032,91'));
    expect(html, contains('95 m²'));
    expect(html, contains('Via &quot;Roma&quot; 1, piano 2'));
    expect('<td>A/2</td>'.allMatches(html), hasLength(1));
    // Senza scheda: nessuna sezione CENED.
    expect(html, isNot(contains('Scheda CENED')));
  });

  test('report: nessun dato catastale → messaggio', () {
    final html = buildReportHtml(SurveyData());
    expect(html, contains('Nessun dato catastale inserito.'));
  });

  test('report: scheda CENED con righe da rilevare evidenziate e stimate marcate', () {
    final html = buildReportHtml(SurveyData(), cened: _sheet);
    expect(html, contains('<h2>Scheda CENED</h2>'));
    expect(html, contains('Stima preliminare &lt;indicativa&gt;'));
    expect(html, contains('Edificio &amp; localizzazione'));
    expect(html, contains('servizioDatiClimatici@codiceIstat'));
    expect(html, contains('<tr class="missing"><td>Piani &lt;b&gt;</td><td>da rilevare</td></tr>'));
    expect(html, contains('1970 <span class="est">stimato</span>'));
    expect(html, contains('stima preliminare'));
  });
}

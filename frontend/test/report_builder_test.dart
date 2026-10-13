import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/energy.dart';

SurveyData _survey({
  String? wall,
  Map<String, String>? photos,
  List<String>? additional,
  EnergyResult? result,
}) {
  final data = SurveyData()
    ..address = 'Via Roma 1, Milano'
    ..building = {
      'telaio': 'Legno',
      'vetro': 'Doppio',
      'generatore': 'caldaia_condensazione',
      if (wall != null) 'spessore_muri': wall,
    }
    ..result = result;
  if (photos != null) data.photos = photos;
  if (additional != null) data.additionalPhotos = additional;
  return data;
}

final _result = EnergyResult.fromJson({
  'classe': 'E',
  'punteggio': 33.0,
  'rapporto_ep': 2.3,
  'metodo': 'Stima preliminare DM 26/06/2015',
  'clima': {
    'zona': 'E',
    'gradi_giorno': 2404,
    'comune': {'comune': 'Milano', 'provincia': 'MI', 'zona': 'E', 'gradi_giorno': 2404},
  },
  'ep': {'gl_nren': 120.5, 'gl_ren': 8.1, 'h_nd': 70.0, 'h_nren': 100.0, 'w_nren': 20.5},
  'riferimento': {'gl_nren_rif_standard': 52.4},
  'trasmittanze': {'pareti': 1.15, 'finestre': 2.83},
  'trasmittanze_limite': {'pareti': 0.26, 'finestre': 1.4},
  'geometria': {'pareti_opache': 50.0, 'superfici_finestrate': 10.0},
  'consumi': [
    {'vettore': 'metano', 'kwh': 9600, 'quantita': 1000, 'unita': 'Smc', 'costo_eur': 1152},
  ],
  'costo_annuo_eur': 1152,
  'co2_kg_anno': 1900,
  'interventi': [
    {'codice': 'cappotto', 'intervento': 'Cappotto <12 cm>', 'classe': 'C',
     'riduzione_ep_pct': 40.0, 'risparmio_annuo_eur': 450, 'investimento_eur': 6500,
     'tempo_ritorno_anni': 14.4, 'classi_guadagnate': 2},
  ],
  'assunzioni': [
    {'campo': 'anno_costruzione', 'descrizione': 'Anno di costruzione', 'valore': 1970},
  ],
});

int _imgCount(String html) => html.split('<img').length - 1;

void main() {
  group('M4/M3/M5 – report', () {
    test('0 foto aggiuntive: sezione presente, nessun <img>', () {
      final html = buildReportHtml(_survey());

      expect(html, contains('<h2>Foto aggiuntive</h2>'));
      expect(html, contains('Nessuna foto aggiuntiva.'));
      expect(_imgCount(html), 0);
    });

    test('1 foto aggiuntiva: un solo <img> con data:image escapato', () {
      const photo = 'data:image/jpeg;base64,QUFBQQ==';
      final html = buildReportHtml(_survey(additional: [photo]));

      expect(_imgCount(html), 1);
      expect(html, contains('src="$photo"'));
      expect(html, contains('alt="Foto aggiuntiva 1"'));
      expect(html, contains('Foto aggiuntiva 1</figcaption>'));
    });

    test('N foto aggiuntive: un <img> ciascuna, numerate', () {
      final photos = [
        'data:image/jpeg;base64,QUFB',
        'data:image/png;base64,QkJCQg==',
        'data:image/webp;base64,REVGSUg=',
      ];
      final html = buildReportHtml(_survey(additional: photos));

      expect(_imgCount(html), 3);
      expect(html, contains('alt="Foto aggiuntiva 3"'));
      expect(html, isNot(contains('alt="Foto aggiuntiva 4"')));
    });

    test('M5: rifiuta prefissi non-immagine come src', () {
      final html = buildReportHtml(_survey(
        photos: {'Facciata': 'data:text/html;base64,PHNjcmlwdD4='},
        additional: [
          'javascript:alert(1)',
          'https://evil.example/x.png',
          'data:text/html;base64,PHNjcmlwdD4=',
        ],
      ));

      expect(_imgCount(html), 0);
      expect(html, isNot(contains('data:text/html')));
      expect(html, isNot(contains('javascript:')));
      expect(html, isNot(contains('https://evil.example')));
      expect(html, contains('Nessuna foto inserita.'));
      expect(html, contains('Nessuna foto aggiuntiva.'));
    });

    test('spessore muri con label umana ed escaping', () {
      expect(buildReportHtml(_survey(wall: '30-40cm')), contains('<td>Spessore muri</td><td>Medio</td>'));
      expect(buildReportHtml(_survey()), contains('<td>Spessore muri</td><td>—</td>'));
    });

    test('risultato: classe, indici, consumi, interventi escapati, assunzioni', () {
      final html = buildReportHtml(_survey(result: _result));
      expect(html, contains('>E</div>'));
      expect(html, contains('120,5 kWh/m²anno'));
      expect(html, contains('52,4 kWh/m²anno'));
      expect(html, contains('Milano (MI)'));
      expect(html, contains('€ 1.152'));
      expect(html, contains('Cappotto &lt;12 cm&gt;'));
      expect(html, contains('Dati non rilevati'));
      expect(html, contains('Anno di costruzione'));
    });

    test('riferimenti normativi corretti, DPR 59/2009 assente', () {
      final html = buildReportHtml(_survey(result: _result));
      expect(html, contains('D.Lgs. 192/2005'));
      expect(html, contains('DM 26/06/2015'));
      expect(html, contains('UNI/TS 11300'));
      expect(html, contains('Non sostituisce l\'attestato'));
      expect(html, isNot(contains('59/2009')));
    });

    test('senza stima: report comunque generato', () {
      expect(buildReportHtml(_survey()), contains('Stima non disponibile.'));
    });

    test('M4: zero invio API – solo HTML autocontenuto, nessun endpoint', () {
      final html = buildReportHtml(
        _survey(additional: ['data:image/jpeg;base64,QUFB']),
      );

      expect(html, isNot(contains('/api/v1')));
      expect(html, isNot(contains('fetch(')));
      expect(html, isNot(contains('<script')));
    });

    test('escaping: indirizzo con HTML non esce crudo', () {
      final data = _survey()..address = '<script>alert(1)</script>';
      final html = buildReportHtml(data);

      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

SurveyData _survey({
  String? wall,
  Map<String, String>? photos,
  List<String>? additional,
}) {
  final data = SurveyData()
    ..address = 'Via Roma 1, Milano'
    ..windowType = 'Legno Doppio'
    ..heatingType = 'Condensazione';
  if (wall != null) data.wallThickness = wall;
  if (photos != null) data.photos = photos;
  if (additional != null) data.additionalPhotos = additional;
  return data;
}

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

    test('M3: «Spessore muri» con label umana, mai il valore grezzo', () {
      final html = buildReportHtml(_survey(wall: '30-40cm'));

      expect(html, contains('<td>Medio — 30–40 cm</td>'));
      expect(html, isNot(contains('30-40cm')));
    });

    test('M3: tutte le label umane (+ escaping della pennetta <)', () {
      expect(
        buildReportHtml(_survey(wall: '<30cm')),
        contains('<td>Sottile — &lt;30 cm</td>'),
      );
      expect(
        buildReportHtml(_survey(wall: '>40cm')),
        contains('<td>Spesso — &gt;40 cm</td>'),
      );
      // Nessuna selezione → trattino, non il valore grezzo.
      expect(
        buildReportHtml(_survey()),
        contains('<td>Spessore muri</td><td>—</td>'),
      );
    });

    test('M3: stringhe normative presenti, DPR 59/2009 assente', () {
      final html = buildReportHtml(_survey(wall: '30-40cm'));

      expect(html, contains('D.Lgs. 192/2005'));
      expect(html, contains('D.M. 26/06/2015 (UNI TS 11300)'));
      expect(html, contains('lo spessore è un proxy della trasmittanza U'));
      expect(html, contains('non definisce la classe APE'));

      expect(html, isNot(contains('DPR 59/2009')));
      expect(html, isNot(contains('59/2009')));
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

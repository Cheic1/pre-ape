/// Dati catastali, documenti e scheda CENED: DTO di rete e stato wizard.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/survey.dart';

const _unitJson = <String, Object?>{
  'comune': 'Milano',
  'codice_comune': 'F205',
  'provincia': 'MI',
  'sezione_urbana': 'A',
  'foglio': '12',
  'particella': '345',
  'subalterno': '6',
  'categoria': 'A/2',
  'classe': '3',
  'consistenza': '5,5 vani',
  'superficie_mq': 95.0,
  'rendita_euro': 1032.91,
  'indirizzo': 'Via Roma 1',
  'piano': '2',
};

SurveyRead _read({List<Map<String, Object?>>? cadastral}) => SurveyRead.fromJson({
      'id': 's-1',
      'status': 'draft',
      'created_at': '2026-10-18T10:00:00Z',
      'updated_at': '2026-10-18T10:00:00Z',
      if (cadastral != null) 'cadastral': cadastral,
    });

void main() {
  group('CadastralUnit', () {
    test('round-trip completo: stesse chiavi e valori del contratto', () {
      final unit = CadastralUnit.fromJson(Map<String, dynamic>.of(_unitJson));
      expect(unit.toJson(), _unitJson);
      expect(CadastralUnit.keys.toSet(), _unitJson.keys.toSet());
    });

    test('toJson omette i null e non emette mai chiavi sconosciute', () {
      final unit = CadastralUnit.fromJson({
        'foglio': '1',
        'particella': '',
        'intestatario': 'Mario Rossi', // fuori contratto: ignorato
        'superficie_mq': 80,
      });
      final json = unit.toJson();
      expect(json, {'foglio': '1', 'superficie_mq': 80.0});
      expect(CadastralUnit.keys.toSet().containsAll(json.keys), isTrue);
      expect(const CadastralUnit().toJson(), isEmpty);
      expect(const CadastralUnit().isEmpty, isTrue);
    });

    test('withField imposta, cancella e ignora chiavi fuori contratto', () {
      var u = const CadastralUnit().withField('foglio', '7');
      expect(u.foglio, '7');
      u = u.withField('rendita_euro', 12.5);
      expect(u.renditaEuro, 12.5);
      u = u.withField('foglio', '');
      expect(u.foglio, isNull);
      expect(u.withField('nome', 'x').toJson(), {'rendita_euro': 12.5});
    });

    test('label leggibile', () {
      expect(const CadastralUnit(foglio: '1', particella: '2', subalterno: '3').label,
          'Fg. 1 Part. 2 Sub. 3');
    });
  });

  group('SurveyCreate / SurveyRead', () {
    test('cadastral serializzata come lista di oggetti del contratto', () {
      final body = SurveyCreate(cadastral: [
        CadastralUnit.fromJson(Map<String, dynamic>.of(_unitJson)),
        const CadastralUnit(foglio: '3'),
      ]).toJson();
      expect(body['cadastral'], [
        _unitJson,
        {'foglio': '3'},
      ]);
      expect(const SurveyCreate().toJson().containsKey('cadastral'), isFalse);
    });

    test('SurveyRead legge cadastral (assente → null)', () {
      expect(_read().cadastral, isNull);
      final r = _read(cadastral: [_unitJson]);
      expect(r.cadastral!.single.categoria, 'A/2');
    });
  });

  group('SurveyNotifier – dati catastali', () {
    test('loadFrom + toWire: round-trip, unità vuote escluse', () {
      final n = SurveyNotifier();
      n.loadFrom(_read(cadastral: [_unitJson]));
      expect(n.data.cadastral.single.foglio, '12');
      expect(n.dirty, isFalse);

      expect(n.addCadastralUnit(), isTrue);
      expect(n.dirty, isTrue);
      expect(n.data.cadastral, hasLength(2));
      final wire = n.toWire().toJson();
      expect(wire['cadastral'], [_unitJson]);
      n.dispose();
    });

    test('nessuna unità → cadastral: [] (svuota sul server)', () {
      final n = SurveyNotifier();
      expect(n.toWire().toJson()['cadastral'], isEmpty);
      n.dispose();
    });

    test('add/set/remove con limite di 20 unità', () {
      final n = SurveyNotifier();
      for (var i = 0; i < kMaxCadastralUnits; i++) {
        expect(n.addCadastralUnit(), isTrue);
      }
      expect(n.addCadastralUnit(), isFalse);
      n.setCadastralField(0, 'foglio', '9');
      expect(n.data.cadastral.first.foglio, '9');
      expect(n.removeCadastralUnit(0), isTrue);
      expect(n.removeCadastralUnit(99), isFalse);
      expect(n.data.cadastral, hasLength(kMaxCadastralUnits - 1));
      expect(n.data.cadastral.first.foglio, isNull);
      n.dispose();
    });

    test('applica visura: sostituisce le vuote, completa la stessa particella, aggiunge le nuove',
        () {
      final n = SurveyNotifier();
      n.addCadastralUnit(); // vuota → rimossa
      n.addCadastralUnit(const CadastralUnit(
          foglio: '12', particella: '345', subalterno: '6', piano: 'T'));
      n.applyCadastralProposal(const [
        CadastralUnit(
            foglio: '12', particella: '345', subalterno: '6', categoria: 'A/2'),
        CadastralUnit(
            foglio: '12', particella: '345', subalterno: '7', categoria: 'C/6'),
      ]);
      final units = n.data.cadastral;
      expect(units, hasLength(2));
      expect(units[0].categoria, 'A/2');
      expect(units[0].piano, 'T'); // dato del tecnico conservato
      expect(units[1].subalterno, '7');
      expect(n.dirty, isTrue);
      n.dispose();
    });
  });

  group('DocumentMeta / CenedSheet', () {
    test('DocumentMeta.fromJson con uploader ed extracted', () {
      final d = DocumentMeta.fromJson({
        'id': 'd-1',
        'survey_id': 's-1',
        'kind': 'visura',
        'filename': 'visura.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 2048,
        'uploaded_by': {'id': 'u-1', 'email': 'anna@example.com', 'name': 'Anna'},
        'extracted': [_unitJson],
        'created_at': '2026-10-18T10:00:00Z',
      });
      expect(d.kindLabel, 'Visura catastale');
      expect(d.uploadedBy!.display, 'Anna');
      expect(d.extracted!.single.renditaEuro, 1032.91);
      final other = DocumentMeta.fromJson({
        'id': 'd-2',
        'survey_id': 's-1',
        'kind': 'mappa',
        'filename': 'mappa.png',
        'mime_type': 'image/png',
        'size_bytes': 10,
        'uploaded_by': null,
        'extracted': null,
        'created_at': '2026-10-18T10:00:00Z',
      });
      expect(other.extracted, isNull);
      expect(other.uploadedBy, isNull);
    });

    test('CenedSheet.fromJson: sezioni, stati, conteggio da rilevare', () {
      final sheet = CenedSheet.fromJson({
        'survey_id': 's-1',
        'generated_at': '2026-10-18T10:00:00Z',
        'disclaimer': 'Stima preliminare',
        'sections': [
          {
            'key': 'edificio',
            'title': 'Edificio e localizzazione',
            'rows': [
              {'label': 'Comune', 'value': 'Milano', 'cened_field': 'x@y', 'status': 'ok'},
              {'label': 'Anno', 'value': 1970, 'cened_field': null, 'status': 'stimato'},
              {'label': 'Piani', 'value': null, 'cened_field': null, 'status': 'da_rilevare'},
              {'label': 'Altezza', 'value': 2.7, 'cened_field': null, 'status': 'ok'},
            ],
          },
        ],
      });
      final rows = sheet.sections.single.rows;
      expect(sheet.missingCount, 1);
      expect(rows[1].estimated, isTrue);
      expect(rows[1].displayValue, '1970');
      expect(rows[2].missing, isTrue);
      expect(rows[3].displayValue, '2,7');
    });
  });
}

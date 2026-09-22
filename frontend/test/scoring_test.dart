import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/core/scoring.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/widgets/energy_gauge.dart';

/// Defaults d'app: 60 m², 2.7 m, niente selezioni → 30 (base) + 0.6 (area)
/// + 2 (branch default del riscaldamento) = 32.6.
const double baseline = 32.6;

/// SurveyData con i default di `SurveyData()` e override opzionali.
SurveyData data({
  double? sqMeters,
  String? wall,
  String? window,
  String? heating,
}) {
  final d = SurveyData();
  if (sqMeters != null) d.squareMeters = sqMeters;
  if (wall != null) d.wallThickness = wall;
  if (window != null) d.windowType = window;
  if (heating != null) d.heatingType = heating;
  return d;
}

void main() {
  group('AC-1: casi di confronto espliciti pre/post refactor', () {
    test('default (60 m², 2.7 m, niente selezioni) resta 32.6', () {
      // Stesso risultato del vecchio `_recalculateScore`:
      // 30 + 0.6 (60/100) + 2 (default riscaldamento) = 32.6
      expect(computeScore(SurveyData()), closeTo(32.6, 1e-9));
    });

    test('combo 30-40cm + Doppio + Condensazione a 60 m² resta 63.6', () {
      // Stesso risultato pre-refactor:
      // 30 + 0.6 + 15 (muri) + 10 (finestre) + 8 (Condensazione) = 63.6
      expect(
        computeScore(data(wall: '30-40cm', window: 'Doppio vetro',
            heating: 'Condensazione')),
        closeTo(63.6, 1e-9),
      );
    });

    test('massimo teorico resta esattamente 100.0', () {
      // Stesso risultato pre-refactor: 30 + 20 (clamp area) + 25 + 15 + 10
      // = 100.0 esatto (clamp finale non morde).
      expect(
        computeScore(data(
          sqMeters: 2500,
          wall: '>40cm',
          window: 'Triplo vetro',
          heating: 'Pompa di Calore',
        )),
        100.0,
      );
    });

    test('SurveyNotifier applica computeScore: >40cm + Triplo + Pompa = 80.6',
        () {
      final notifier = SurveyNotifier();
      notifier.updateWallThickness('>40cm');
      notifier.updateWindowType('Triplo vetro');
      notifier.updateHeatingType('Pompa di Calore');
      // 30 + 0.6 (60 m²) + 25 + 15 + 10 = 80.6 – stessa via del pre-refactor.
      expect(notifier.data.currentScore, closeTo(80.6, 1e-9));
    });
  });

  group('computeScore – spessore muri', () {
    test('>40cm dà +25 rispetto al default', () {
      expect(computeScore(data(wall: '>40cm')), closeTo(baseline + 25, 1e-9));
    });

    test('30-40cm dà +15 rispetto al default', () {
      expect(computeScore(data(wall: '30-40cm')), closeTo(baseline + 15, 1e-9));
    });

    test('<30cm dà +5 rispetto al default', () {
      expect(computeScore(data(wall: '<30cm')), closeTo(baseline + 5, 1e-9));
    });

    test('muro sconosciuto o assente non aggiunge nulla', () {
      expect(computeScore(data(wall: 'spessore ignoto')),
          closeTo(baseline, 1e-9));
      expect(computeScore(SurveyData()), closeTo(baseline, 1e-9));
    });
  });

  group('computeScore – tipologie di finestra', () {
    test('Triplo dà +15 (contains "Triplo")', () {
      expect(computeScore(data(window: 'Triplo vetro')),
          closeTo(baseline + 15, 1e-9));
    });

    test('Doppio dà +10 (contains "Doppio")', () {
      expect(computeScore(data(window: 'Doppio vetro')),
          closeTo(baseline + 10, 1e-9));
    });

    test('qualsiasi altra finestra dà +5', () {
      expect(computeScore(data(window: 'Singolo vetro')),
          closeTo(baseline + 5, 1e-9));
    });

    test('nessuna selezione finestra non aggiunge nulla', () {
      expect(computeScore(SurveyData()), closeTo(baseline, 1e-9));
    });
  });

  group('computeScore – riscaldamento', () {
    // Il riscaldamento si somma a 30 + 0.6 (60 m²) = 30.6: il branch
    // default (+2) viene sostituito dal bonus della tipologia scelta.
    const withoutHeating = 30.6;

    test('Pompa di Calore dà +10', () {
      expect(computeScore(data(heating: 'Pompa di Calore')),
          closeTo(withoutHeating + 10, 1e-9));
    });

    test('Condensazione dà +8', () {
      expect(computeScore(data(heating: 'Condensazione')),
          closeTo(withoutHeating + 8, 1e-9));
    });

    test('Pellet dà +6', () {
      expect(computeScore(data(heating: 'Pellet')),
          closeTo(withoutHeating + 6, 1e-9));
    });

    test('Gas dà +2 (branch default)', () {
      expect(computeScore(data(heating: 'Gas')),
          closeTo(withoutHeating + 2, 1e-9));
    });

    test('riscaldamento assente dà +2 (branch default, = baseline)', () {
      expect(computeScore(SurveyData()), closeTo(baseline, 1e-9));
    });
  });

  group('computeScore – clamp', () {
    test('area enormi vengono clamped: il risultato resta 100.0', () {
      // 1e9 m² → clamp area a 20 → 30 + 20 + 25 + 15 + 10 = 100.0.
      final score = computeScore(data(
        sqMeters: 1000000000,
        wall: '>40cm',
        window: 'Triplo vetro',
        heating: 'Pompa di Calore',
      ));
      expect(score, 100.0);
      expect(score, lessThanOrEqualTo(100.0));
    });

    test('area negative/assente: nessun bonus, risultato sempre ≥ 0', () {
      // Il guard `squareMeters > 0` salta: 30 + 2 = 32 ≥ 0.
      final score = computeScore(data(sqMeters: -500));
      expect(score, 32.0);
      expect(score, greaterThanOrEqualTo(0.0));
    });

    test('range garantito [0, 100] per qualsiasi input estremo', () {
      final extremes = [
        data(sqMeters: -1e9),
        data(sqMeters: 1e9),
        data(sqMeters: 0, wall: '>40cm', window: 'Triplo',
            heating: 'Pompa di Calore'),
      ];
      for (final d in extremes) {
        final s = computeScore(d);
        expect(s, greaterThanOrEqualTo(0.0));
        expect(s, lessThanOrEqualTo(100.0));
      }
    });
  });

  group('energyClassForScore – mapping agli estremi e casi noti', () {
    test('score 0 → G, score 100 → A4', () {
      expect(energyClassForScore(0), 'G');
      expect(energyClassForScore(100), 'A4');
    });

    test('clamp della classe: -50 → G, 250 → A4', () {
      expect(energyClassForScore(-50), 'G');
      expect(energyClassForScore(250), 'A4');
    });

    test('casi intermedi noti', () {
      // index = round(score/100*9); classe = kEnergyClassLetters[9 - index].
      expect(energyClassForScore(10), 'F'); // index 1 → classes[8]
      expect(energyClassForScore(30), 'D'); // index 3 → classes[6]
      expect(energyClassForScore(50), 'B'); // index 5 → classes[4]
      expect(energyClassForScore(90), 'A3'); // index 8 → classes[1]
    });

    test('punteggio di default del survey → classe D', () {
      expect(energyClassForScore(baseline), 'D');
    });

    test('energyClassIndexForScore: 0 → 0, 50 → 5, 100 → 9', () {
      expect(energyClassIndexForScore(0), 0);
      expect(energyClassIndexForScore(50), 5);
      expect(energyClassIndexForScore(100), 9);
    });
  });

  group('AC-4: nessun duplicato – core/scoring.dart è fonte unica', () {
    test('kEnergyClassLetters è allineato a EnergyClass.classes del gauge',
        () {
      expect(kEnergyClassLetters.length, EnergyClass.classes.length);
      for (var i = 0; i < kEnergyClassLetters.length; i++) {
        expect(kEnergyClassLetters[i], EnergyClass.classes[i].letter,
            reason: 'lettera disallineata all\'indice $i');
      }
    });

    test('la classe di core coincide con la risoluzione della tabella gauge',
        () {
      for (final s in [0.0, 10.0, 32.6, 50.0, 77.0, 90.0, 100.0]) {
        final fromCore = energyClassForScore(s);
        final fromGauge =
            EnergyClass.classes[9 - energyClassIndexForScore(s)].letter;
        expect(fromCore, fromGauge, reason: 'score $s');
      }
    });
  });
}

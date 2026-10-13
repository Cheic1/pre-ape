import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/core/scoring.dart';
import 'package:pre_ape/features/widgets/energy_gauge.dart';

void main() {
  group('energyClassForScore – punteggio del server → classe', () {
    test('estremi e clamp', () {
      expect(energyClassForScore(0), 'G');
      expect(energyClassForScore(100), 'A4');
      expect(energyClassForScore(-50), 'G');
      expect(energyClassForScore(250), 'A4');
    });

    test('centri di classe (il server mette il punteggio dentro la fascia)', () {
      for (var k = 0; k <= 9; k++) {
        expect(energyClassForScore(k / 9 * 100), kEnergyClassLetters[9 - k]);
      }
    });

    test('bordi delle fasce generati dal backend (score_for_ratio)', () {
      // round(score/100*9) con score = (k - 0.5 + 0.001 + 0.998*frac)/9*100
      for (var k = 1; k <= 9; k++) {
        final low = (k - 0.5 + 0.001) / 9 * 100;
        final high = (k - 0.5 + 0.999) / 9 * 100;
        expect(energyClassForScore(low), kEnergyClassLetters[9 - k]);
        expect(energyClassForScore(high), kEnergyClassLetters[9 - k]);
      }
    });
  });

  group('allineamento con il gauge', () {
    test('kEnergyClassLetters segue EnergyClass.classes', () {
      expect(kEnergyClassLetters.length, EnergyClass.classes.length);
      for (var i = 0; i < kEnergyClassLetters.length; i++) {
        expect(kEnergyClassLetters[i], EnergyClass.classes[i].letter);
      }
    });

    test('EnergyClass.of: lettera nota e fallback su G', () {
      expect(EnergyClass.of('B').letter, 'B');
      expect(EnergyClass.of('?').letter, 'G');
    });
  });
}

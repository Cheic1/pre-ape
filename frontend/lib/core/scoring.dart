/// Pure scoring logic for the Pre-APE onboarding survey.
///
/// Extracted (TEAM_REVIEW.md P2-B4 – "logica pura estraibile") from
/// `SurveyNotifier._recalculateScore` (`features/onboarding/survey_provider.dart`)
/// and from `energyClassForScore` (`features/onboarding/report_builder.dart`)
/// so the score formula and the score → energy-class mapping live in exactly
/// one place. The `EnergyGauge` widget delegates here as well.
///
/// Behaviour is intentionally unchanged: values, branches and clamping are
/// identical to the pre-refactor code (guarded by `test/scoring_test.dart`).
library;

import 'package:pre_ape/features/onboarding/survey_provider.dart'
    show SurveyData;

/// Energy-class letters from best (A4) to worst (G).
///
/// Must stay aligned with `EnergyClass.classes` in
/// `features/widgets/energy_gauge.dart`; the alignment is guarded by a test
/// in `test/scoring_test.dart`.
const List<String> kEnergyClassLetters = <String>[
  'A4',
  'A3',
  'A2',
  'A1',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
];

/// Preliminary score (0–100) for the given survey answers.
///
/// Body moved verbatim from `SurveyNotifier._recalculateScore`: base 30,
/// area bonus `(m² / 100).clamp(0, 20)`, wall/window/heating bonuses and the
/// final `clamp(0, 100)`. No value or branch was changed.
double computeScore(SurveyData data) {
  double score = 30.0;

  if (data.squareMeters > 0) {
    score += (data.squareMeters / 100).clamp(0, 20);
  }

  switch (data.wallThickness) {
    case '>40cm':
      score += 25;
      break;
    case '30-40cm':
      score += 15;
      break;
    case '<30cm':
      score += 5;
      break;
  }

  if (data.windowType != null) {
    if (data.windowType!.contains('Triplo')) {
      score += 15;
    } else if (data.windowType!.contains('Doppio')) {
      score += 10;
    } else {
      score += 5;
    }
  }

  switch (data.heatingType) {
    case 'Pompa di Calore':
      score += 10;
      break;
    case 'Condensazione':
      score += 8;
      break;
    case 'Pellet':
      score += 6;
      break;
    default:
      score += 2;
  }

  return score.clamp(0, 100);
}

/// Index (0–9) of the energy class for [score]: 0 = worst (G),
/// 9 = best (A4).
///
/// Same formula the `EnergyGauge.currentClass` getter used before the
/// extraction (score clamped to 0–100, then `(score / 100 * 9).round()`).
int energyClassIndexForScore(double score) {
  final normalized = score.clamp(0, 100);
  return ((normalized / 100) * 9).round().clamp(0, 9);
}

/// Letter of the energy class for [score] (0 → G, 100 → A4).
///
/// Single source of the mapping – previously duplicated between
/// `report_builder.dart` and `energy_gauge.dart`.
String energyClassForScore(double score) =>
    kEnergyClassLetters[9 - energyClassIndexForScore(score)];

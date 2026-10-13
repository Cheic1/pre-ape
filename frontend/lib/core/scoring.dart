/// Energy-class helpers for the score computed by the server.
///
/// The estimate itself lives in the backend (`app/core/energy`): its
/// `punteggio` (0–100) is built so that `round(score / 100 * 9)` is the class
/// index counted from G — the mapping below — and the gauge only renders it.
library;

/// Energy-class letters from best (A4) to worst (G).
const List<String> kEnergyClassLetters = <String>[
  'A4', 'A3', 'A2', 'A1', 'B', 'C', 'D', 'E', 'F', 'G',
];

/// Index (0–9) of the energy class for [score]: 0 = worst (G), 9 = best (A4).
int energyClassIndexForScore(double score) {
  final normalized = score.clamp(0, 100);
  return ((normalized / 100) * 9).round().clamp(0, 9);
}

/// Letter of the energy class for [score] (0 → G, 100 → A4).
String energyClassForScore(double score) =>
    kEnergyClassLetters[9 - energyClassIndexForScore(score)];

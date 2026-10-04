/// Spessore muri (M3): sublabel UI in centimetri, label umana per il report e
/// caption normativa.  Il valore grezzo (`30-40cm`) resta solo interno allo
/// stato/allo scoring, non viene mai mostrato come tale.
///
/// NOTA: la normativa di riferimento è D.Lgs. 192/2005 + D.M. 26/06/2015
/// (UNI TS 11300).  **Mai** DPR 59/2009.
library;

/// Caption sotto il selettore di spessore (step 2) e nota nel report.
const String kWallThicknessCaption =
    'Riferimento: D.Lgs. 192/2005, D.M. 26/06/2015 (UNI TS 11300) — '
    'lo spessore è un proxy della trasmittanza U, non definisce la classe APE';

/// Sublabel in centimetri mostrata sotto la label della card, derivata dal
/// valore di stato (`<30cm` / `30-40cm` / `>40cm`).  Nulla per valori ignoti.
String? wallThicknessSublabel(String? value) => switch (value) {
      '<30cm' => '< 30 cm',
      '30-40cm' => '30 – 40 cm',
      '>40cm' => '> 40 cm',
      _ => null,
    };

/// Label umana per il report (`Medio — 30–40 cm`) al posto del valore grezzo.
String? wallThicknessReportLabel(String? value) => switch (value) {
      '<30cm' => 'Sottile — <30 cm',
      '30-40cm' => 'Medio — 30–40 cm',
      '>40cm' => 'Spesso — >40 cm',
      _ => value,
    };

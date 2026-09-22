/// Builds a printable HTML report from the collected [SurveyData].
///
/// The HTML is self-contained (inline CSS, embedded photos) so the user can
/// open it offline, print it, or save it as PDF from the browser.
library;

import 'package:pre_ape/core/scoring.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

String _esc(String? value) {
  if (value == null || value.isEmpty) return '—';
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String buildReportHtml(SurveyData s) {
  final now = DateTime.now();
  final date =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  final cls = energyClassForScore(s.currentScore);

  final photoSections = s.photos.entries.map((e) => '''
      <figure>
        <img src="${e.value}" alt="${_esc(e.key)}">
        <figcaption>${_esc(e.key)}</figcaption>
      </figure>''').join('\n');

  return '''<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Pre-APE – Rilievo ${_esc(s.address)}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: 'Inter', system-ui, sans-serif; color: #1a1a1a;
         margin: 0; padding: 32px; background: #f6f7f9; }
  .card { background: #fff; max-width: 800px; margin: 0 auto;
          border: 1px solid #e2e5ea; border-radius: 12px; padding: 32px; }
  h1 { margin: 0 0 4px; font-size: 24px; }
  .sub { color: #667085; font-size: 14px; margin-bottom: 24px; }
  h2 { font-size: 16px; margin: 28px 0 12px; color: #344054;
       border-bottom: 1px solid #e2e5ea; padding-bottom: 6px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  td { padding: 8px 4px; border-bottom: 1px solid #f0f2f5; }
  td:first-child { color: #667085; width: 45%; }
  td:last-child { font-weight: 600; text-align: right; }
  .badge { display: inline-block; background: #10B981; color: #fff;
           font-weight: 700; border-radius: 8px; padding: 4px 12px; }
  .photos { display: flex; flex-wrap: wrap; gap: 12px; }
  figure { margin: 0; width: 160px; }
  figure img { width: 160px; height: 120px; object-fit: cover;
               border-radius: 8px; border: 1px solid #e2e5ea; }
  figcaption { font-size: 12px; color: #667085; text-align: center; }
  .footer { margin-top: 28px; font-size: 12px; color: #98a2b3;
            border-top: 1px solid #e2e5ea; padding-top: 12px; }
  @media print { body { background: #fff; padding: 0; }
                 .card { border: none; } }
</style>
</head>
<body>
<div class="card">
  <h1>Pre-APE – Rilievo dati</h1>
  <div class="sub">Certificazione energetica · $date</div>

  <h2>Edificio</h2>
  <table>
    <tr><td>Indirizzo</td><td>${_esc(s.address)}</td></tr>
    <tr><td>Coordinate</td><td>${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}</td></tr>
    <tr><td>Superficie</td><td>${s.squareMeters.toStringAsFixed(0)} m²</td></tr>
    <tr><td>Altezza media</td><td>${s.avgHeight.toStringAsFixed(1)} m</td></tr>
    <tr><td>Volume utile</td><td>${(s.squareMeters * s.avgHeight).toStringAsFixed(1)} m³</td></tr>
  </table>

  <h2>Involucro</h2>
  <table>
    <tr><td>Spessore muri</td><td>${_esc(s.wallThickness)}</td></tr>
    <tr><td>Infissi</td><td>${_esc(s.windowType)}</td></tr>
  </table>

  <h2>Impianti</h2>
  <table>
    <tr><td>Riscaldamento</td><td>${_esc(s.heatingType)}</td></tr>
    <tr><td>Generatore</td><td>${_esc(s.generatorType)}</td></tr>
  </table>

  <h2>Valutazione preliminare</h2>
  <table>
    <tr><td>Punteggio</td><td>${s.currentScore.toStringAsFixed(0)} / 100</td></tr>
    <tr><td>Classe stimata</td><td><span class="badge">${_esc(cls)}</span></td></tr>
  </table>

  <h2>Rilievo fotografico</h2>
  ${photoSections.isEmpty ? '<p>Nessuna foto inserita.</p>' : '<div class="photos">\n$photoSections\n</div>'}

  <div class="footer">
    Documento generato da Pre-APE – stima preliminare ai fini del sopralluogo.
    Non sostituisce l'attestato di prestazione energetica (APE) ai sensi del
    D.Lgs. 192/2005, che richiede sopralluogo e calcolo da parte di un
    tecnico abilitato.
  </div>
</div>
</body>
</html>''';
}

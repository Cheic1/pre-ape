/// Builds a printable HTML report from the collected [SurveyData].
///
/// The HTML is self-contained (inline CSS, embedded photos) so the user can
/// open it offline, print it, or save it as PDF from the browser.
library;

import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/web_media.dart';
import 'package:pre_ape/models/energy.dart';

String _esc(Object? value) {
  final s = value?.toString();
  if (s == null || s.isEmpty) return '—';
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _n(Object? v, [int decimals = 0]) {
  final d = (v as num?)?.toDouble();
  if (d == null) return '—';
  return d.toStringAsFixed(decimals).replaceAll('.', ',');
}

String _eur(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '€ $b';
}

const _classColors = {
  'A4': '#00853F', 'A3': '#2E9E3E', 'A2': '#5DB33D', 'A1': '#8CC63F',
  'B': '#C9D92B', 'C': '#FFD21B', 'D': '#FBB01F', 'E': '#F47B20',
  'F': '#EE3B24', 'G': '#C81E1E',
};

String _row(String label, Object? value, {bool assumed = false}) =>
    '<tr><td>${_esc(label)}</td><td>${_esc(value)}${assumed ? ' <span class="est">stimato</span>' : ''}</td></tr>';

String buildReportHtml(SurveyData s) {
  final now = DateTime.now();
  final date =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  final r = s.result;
  final b = s.building;
  final assumed = {for (final a in r?.assunzioni ?? const <Assumption>[]) a.campo};

  String opt(String key, String label) =>
      _row(label, optionLabel(key, b[key]), assumed: assumed.contains(key));
  String numRow(String key, String label, String unit) => _row(
      label, b[key] == null ? null : '${_n(b[key], b[key] is int ? 0 : 1)} $unit',
      assumed: assumed.contains(key));

  // Solo data-URL immagine validati diventano `src` (mai prefissi esterni o
  // `data:text/html`): le foto non valide vengono semplicemente ignorate.
  final photoSections = s.photos.entries
      .where((e) => isImageDataUrl(e.value))
      .map((e) => '''
      <figure>
        <img src="${_esc(e.value)}" alt="${_esc(e.key)}">
        <figcaption>${_esc(e.key)}</figcaption>
      </figure>''')
      .join('\n');

  final additionalValid =
      s.additionalPhotos.where(isImageDataUrl).toList(growable: false);
  final additionalSections = [
    for (var i = 0; i < additionalValid.length; i++)
      '''
      <figure>
        <img src="${_esc(additionalValid[i])}" alt="Foto aggiuntiva ${i + 1}">
        <figcaption>Foto aggiuntiva ${i + 1}</figcaption>
      </figure>''',
  ].join('\n');

  final isFlat = b['tipologia'] == null || b['tipologia'] == 'appartamento';

  return '''<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Pre-APE – ${_esc(s.title ?? s.address)}</title>
<style>
  * { box-sizing: border-box; }
  body { font-family: 'Inter', system-ui, sans-serif; color: #1a1a1a;
         margin: 0; padding: 32px; background: #f6f7f9; }
  .card { background: #fff; max-width: 860px; margin: 0 auto;
          border: 1px solid #e2e5ea; border-radius: 12px; padding: 32px; }
  h1 { margin: 0 0 4px; font-size: 24px; }
  .sub { color: #667085; font-size: 14px; margin-bottom: 24px; }
  h2 { font-size: 16px; margin: 28px 0 12px; color: #344054;
       border-bottom: 1px solid #e2e5ea; padding-bottom: 6px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  td, th { padding: 7px 4px; border-bottom: 1px solid #f0f2f5; }
  th { text-align: left; color: #667085; font-weight: 500; font-size: 12px; }
  td:first-child { color: #667085; }
  .kv td:first-child { width: 45%; }
  .kv td:last-child { font-weight: 600; text-align: right; }
  .num { text-align: right; }
  .grid { display: flex; gap: 24px; flex-wrap: wrap; }
  .grid > div { flex: 1 1 320px; }
  .scale div { color: #fff; font-weight: 700; font-size: 12px; margin: 2px 0;
               padding: 3px 8px; border-radius: 0 10px 10px 0; opacity: .45; }
  .scale div.on { opacity: 1; font-size: 15px; padding: 6px 8px; }
  .big { font-size: 56px; font-weight: 800; line-height: 1; }
  .est { font-size: 10px; font-weight: 600; color: #b54708; background: #fef0c7;
         border-radius: 8px; padding: 1px 6px; }
  .badge { display: inline-block; color: #fff; font-weight: 700;
           border-radius: 6px; padding: 2px 8px; }
  .kpis { display: flex; gap: 12px; flex-wrap: wrap; margin: 16px 0 0; }
  .kpi { flex: 1 1 150px; border: 1px solid #e2e5ea; border-radius: 10px; padding: 10px 12px; }
  .kpi b { display: block; font-size: 18px; }
  .kpi span { color: #667085; font-size: 12px; }
  .photos { display: flex; flex-wrap: wrap; gap: 12px; }
  .note { font-size: 12px; color: #667085; margin: 8px 0 0; }
  .notes { white-space: pre-wrap; font-size: 14px; }
  figure { margin: 0; width: 160px; }
  figure img { width: 160px; height: 120px; object-fit: cover;
               border-radius: 8px; border: 1px solid #e2e5ea; }
  figcaption { font-size: 12px; color: #667085; text-align: center; }
  .footer { margin-top: 28px; font-size: 12px; color: #98a2b3;
            border-top: 1px solid #e2e5ea; padding-top: 12px; }
  @media print { body { background: #fff; padding: 0; }
                 .card { border: none; } h2 { break-after: avoid; } }
</style>
</head>
<body>
<div class="card">
  <h1>Pre-APE – Valutazione energetica preliminare</h1>
  <div class="sub">Sopralluogo del $date${s.title != null && s.title!.isNotEmpty ? ' · ${_esc(s.title)}' : ''}</div>

  ${r == null ? '<p>Stima non disponibile.</p>' : _summary(r)}

  <h2>Pratica</h2>
  <table class="kv">
    ${_row('Riferimento', s.title)}
    ${_row('Cliente', s.clientName)}
    ${_row('Indirizzo', s.address)}
    ${_row('Coordinate', '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}')}
    ${_row('Comune', r?.comune?.label, assumed: assumed.contains('comune'))}
    ${_row('Zona climatica / gradi giorno', r == null ? null : '${r.zona} / ${r.gradiGiorno} GG')}
  </table>

  <h2>Edificio</h2>
  <table class="kv">
    ${opt('tipologia', 'Tipologia')}
    ${numRow('anno_costruzione', 'Anno di costruzione', '')}
    ${isFlat ? opt('piano', 'Posizione') : opt('numero_piani', 'Piani riscaldati')}
    ${_row('Superficie utile', '${_n(s.squareMeters)} m²')}
    ${_row('Altezza netta', '${_n(s.avgHeight, 2)} m')}
    ${_row('Volume netto', '${_n(s.squareMeters * s.avgHeight)} m³')}
    ${opt('lati_esposti', 'Lati esposti')}
    ${opt('orientamento', 'Orientamento finestre')}
  </table>

  <h2>Involucro</h2>
  <table class="kv">
    ${opt('muratura', 'Muratura')}
    ${opt('spessore_muri', 'Spessore muri')}
    ${opt('isolamento_pareti_cm', 'Isolamento pareti')}
    ${b['copertura'] != null ? opt('copertura', 'Copertura') : ''}
    ${b['isolamento_copertura_cm'] != null ? opt('isolamento_copertura_cm', 'Isolamento copertura') : ''}
    ${b['pavimento'] != null ? opt('pavimento', 'Pavimento verso') : ''}
    ${b['isolamento_pavimento_cm'] != null ? opt('isolamento_pavimento_cm', 'Isolamento pavimento') : ''}
    ${opt('telaio', 'Telaio')}
    ${opt('vetro', 'Vetro')}
    ${numRow('superficie_finestrata', 'Superficie finestrata', 'm²')}
  </table>
  ${r == null ? '' : _envelope(r)}

  <h2>Impianti</h2>
  <table class="kv">
    ${opt('generatore', 'Generatore')}
    ${usesFuel(b['generatore']) ? opt('combustibile', 'Combustibile') : ''}
    ${numRow('anno_generatore', 'Anno generatore', '')}
    ${numRow('potenza_kw', 'Potenza', 'kW')}
    ${opt('impianto', 'Impianto')}
    ${opt('terminali', 'Terminali')}
    ${opt('regolazione', 'Regolazione')}
    ${opt('acs', 'Acqua calda sanitaria')}
    ${_row('Solare termico', b['solare_termico'] == true ? 'Sì' : 'No')}
    ${opt('raffrescamento', 'Raffrescamento')}
    ${opt('vmc', 'Ventilazione')}
    ${_row('Fotovoltaico', b['fotovoltaico_kwp'] == null ? 'No' : '${_n(b['fotovoltaico_kwp'], 1)} kWp')}
    ${r == null ? '' : _row('Rendimento globale riscaldamento', _n(r.impianto['eta_h_globale'], 2))}
  </table>

  ${r == null ? '' : _consumption(r)}
  ${r == null ? '' : _improvements(r)}
  ${r == null || r.assunzioni.isEmpty ? '' : _assumptions(r)}

  <h2>Rilievo fotografico</h2>
  ${photoSections.isEmpty ? '<p>Nessuna foto inserita.</p>' : '<div class="photos">\n$photoSections\n</div>'}

  <h2>Foto aggiuntive</h2>
  ${additionalValid.isEmpty ? '<p>Nessuna foto aggiuntiva.</p>' : '<div class="photos">\n$additionalSections\n</div>'}

  <h2>Note del tecnico</h2>
  <p class="notes">${_esc(s.notes)}</p>

  <div class="footer">
    ${_esc(r?.metodo ?? '')}<br>
    Documento generato da Pre-APE – stima preliminare ai fini del sopralluogo.
    Non sostituisce l'attestato di prestazione energetica (APE) ai sensi del
    D.Lgs. 192/2005 e del DM 26/06/2015, che va redatto da un soggetto
    certificatore abilitato con software conforme alle UNI/TS 11300.
  </div>
</div>
</body>
</html>''';
}

String _summary(EnergyResult r) {
  final color = _classColors[r.classe] ?? '#667085';
  final scale = [
    for (final c in _classColors.entries)
      '<div class="${c.key == r.classe ? 'on' : ''}" style="background:${c.value};'
          'width:${35 + 6.5 * _classColors.keys.toList().indexOf(c.key)}%">${c.key}</div>',
  ].join();
  return '''
  <div class="grid">
    <div>
      <div style="color:#667085;font-size:13px">Classe energetica stimata</div>
      <div class="big" style="color:$color">${_esc(r.classe)}</div>
      <table class="kv" style="margin-top:12px">
        ${_row('EPgl,nren', '${_n(r.epGlNren, 1)} kWh/m²anno')}
        ${_row('EPgl,ren', '${_n(r.epGlRen, 1)} kWh/m²anno')}
        ${_row('EPgl,nren,rif,standard (2019/21)', '${_n(r.epRifStandard, 1)} kWh/m²anno')}
        ${_row('Rapporto (scala DM 26/06/2015)', _n(r.rapportoEp, 2))}
        ${_row('Qualità involucro invernale', r.qualitaInvernale)}
      </table>
    </div>
    <div class="scale">$scale</div>
  </div>
  <div class="kpis">
    <div class="kpi"><b>${_eur(r.costoAnnuoEur)}</b><span>spesa energetica annua</span></div>
    <div class="kpi"><b>${_n(r.co2KgAnno / 1000, 1)} t</b><span>CO₂ all'anno (${_n(r.co2KgM2, 1)} kg/m²)</span></div>
    <div class="kpi"><b>${_n(r.epValue('h_nd'), 1)}</b><span>EPH,nd kWh/m²anno</span></div>
  </div>
  <h2>Energia primaria non rinnovabile per servizio</h2>
  <table>
    <tr><th>Servizio</th><th class="num">kWh/m²anno</th></tr>
    <tr><td>Riscaldamento</td><td class="num">${_n(r.epValue('h_nren'), 1)}</td></tr>
    <tr><td>Acqua calda sanitaria</td><td class="num">${_n(r.epValue('w_nren'), 1)}</td></tr>
    <tr><td>Raffrescamento</td><td class="num">${_n(r.epValue('c_nren'), 1)}</td></tr>
    <tr><td>Ventilazione meccanica</td><td class="num">${_n(r.epValue('v_nren'), 1)}</td></tr>
    <tr><td>Fotovoltaico (autoconsumo)</td><td class="num">${_n(r.epValue('fv_nren'), 1)}</td></tr>
    <tr><td><b>Totale EPgl,nren</b></td><td class="num"><b>${_n(r.epGlNren, 1)}</b></td></tr>
  </table>''';
}

String _envelope(EnergyResult r) {
  final geo = r.geometria;
  final u = r.trasmittanze;
  final lim = r.trasmittanzeLimite;
  final rows = [
    ('Pareti opache', 'pareti', 'pareti_opache'),
    ('Copertura', 'copertura', 'copertura'),
    ('Pavimento', 'pavimento', 'pavimento'),
    ('Serramenti', 'finestre', 'superfici_finestrate'),
  ].where((e) => ((geo[e.$3] as num?) ?? 0) > 0);
  return '''
  <table style="margin-top:12px">
    <tr><th>Elemento</th><th class="num">Superficie m²</th><th class="num">U stimata W/m²K</th><th class="num">U riferimento</th></tr>
    ${rows.map((e) => '<tr><td>${e.$1}</td><td class="num">${_n(geo[e.$3])}</td><td class="num">${_n(u[e.$2], 2)}</td><td class="num">${_n(lim[e.$2], 2)}</td></tr>').join('\n    ')}
  </table>
  <p class="note">Trasmittanze da abaco per epoca e tipologia (UNI/TS 11300-1), riferimento DM 26/06/2015 App. A (2019/21).</p>''';
}

String _consumption(EnergyResult r) => '''
  <h2>Consumi e costi annui stimati</h2>
  <table>
    <tr><th>Vettore</th><th class="num">Quantità</th><th class="num">kWh</th><th class="num">Costo</th></tr>
    ${r.consumi.map((c) => '<tr><td>${_esc(c.label)}</td><td class="num">${_n(c.quantita)} ${_esc(c.unita)}</td><td class="num">${_n(c.kwh)}</td><td class="num">${_eur(c.costoEur)}</td></tr>').join('\n    ')}
    <tr><td><b>Totale</b></td><td></td><td></td><td class="num"><b>${_eur(r.costoAnnuoEur)}</b></td></tr>
  </table>
  <p class="note">Uso convenzionale (20 °C, periodo di riscaldamento di legge) e prezzi medi indicativi: i consumi reali dipendono dalle abitudini.</p>''';

String _improvements(EnergyResult r) {
  if (r.interventi.isEmpty) return '';
  return '''
  <h2>Interventi migliorativi raccomandati</h2>
  <table>
    <tr><th>Intervento</th><th class="num">Classe</th><th class="num">−EP</th><th class="num">Risparmio/anno</th><th class="num">Costo indicativo</th><th class="num">Rientro</th></tr>
    ${r.interventi.map((i) => '<tr${i.isGlobal ? ' style="font-weight:700"' : ''}><td>${_esc(i.intervento)}</td><td class="num"><span class="badge" style="background:${_classColors[i.classe] ?? '#667085'}">${_esc(i.classe)}</span></td><td class="num">${_n(i.riduzioneEpPct)}%</td><td class="num">${_eur(i.risparmioAnnuoEur)}</td><td class="num">${_eur(i.investimentoEur)}</td><td class="num">${i.tempoRitornoAnni == null ? '—' : '${_n(i.tempoRitornoAnni)} anni'}</td></tr>').join('\n    ')}
  </table>
  <p class="note">Costi parametrici indicativi (IVA inclusa) al lordo di eventuali detrazioni fiscali; da verificare con preventivi.</p>''';
}

String _assumptions(EnergyResult r) => '''
  <h2>Dati non rilevati (valori tipici usati)</h2>
  <table class="kv">
    ${r.assunzioni.map((a) => _row(a.descrizione, a.valore)).join('\n    ')}
  </table>''';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/cened_sheet_card.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/survey_save.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';
import 'package:pre_ape/features/web/web_download_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_download.dart';
import 'package:pre_ape/features/widgets/energy_gauge.dart';
import 'package:pre_ape/models/energy.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

/// Wizard step that holds each input key (for "completa il dato" links).
int stepForField(String key) {
  const step1 = {'comune', 'gradi_giorno', 'zona_climatica'};
  const step2 = {
    'square_meters', 'avg_height', 'tipologia', 'anno_costruzione', 'piano',
    'numero_piani', 'lati_esposti', 'orientamento',
  };
  const step3 = {
    'muratura', 'spessore_muri', 'isolamento_pareti_cm', 'copertura',
    'isolamento_copertura_cm', 'pavimento', 'isolamento_pavimento_cm',
    'telaio', 'vetro', 'superficie_finestrata',
  };
  if (step1.contains(key)) return 1;
  if (step2.contains(key)) return 2;
  if (step3.contains(key)) return 3;
  return 4;
}

String _eur(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}€ $b';
}

String _num(num v, [int decimals = 0]) => v.toStringAsFixed(decimals).replaceAll('.', ',');

/// Step 6 – risultato della stima, dati da completare e interventi.
class Step6Results extends ConsumerWidget {
  const Step6Results({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(surveyProvider);
    final result = notifier.data.result;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const StepHeader('Risultati', 'Stima della prestazione energetica e interventi consigliati'),
        if (result == null)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else ...[
          _ClassCard(result: result, estimating: notifier.data.estimating),
          _KpiRow(result: result),
          if (result.assunzioni.isNotEmpty) _AssumptionsCard(result: result),
          _BreakdownCard(result: result),
          _EnvelopeCard(result: result),
          _ConsumptionCard(result: result),
          _ImprovementsCard(result: result),
          const _AdvisorCard(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(result.metodo, style: AppTextStyles.bodySmall),
          ),
        ],
        const CenedSheetCard(),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const ValueKey('export_report'),
          onPressed: result == null ? null : () => _exportReport(context, ref),
          icon: const Icon(Icons.description_outlined),
          label: const Text('Scarica report (HTML / PDF)'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
        ),
        WizardNav(
          nextLabel: 'Completa e salva',
          onNext: notifier.saving ? () {} : () => _complete(context, ref),
        ),
      ],
    );
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    // Scheda CENED dei dati salvati (best effort: il report esce comunque).
    CenedSheet? cened;
    if (ref.read(surveyProvider).data.surveyId != null) {
      try {
        cened = await loadCenedSheet(context, ref);
      } on ApiException {
        cened = null;
      }
    }
    if (!context.mounted) return;
    final survey = ref.read(surveyProvider).data;
    final html = buildReportHtml(survey, cened: cened);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final filename = 'PreAPE_${survey.result?.classe ?? 'rilievo'}_$stamp.html';
    try {
      downloadTextFile(filename, html, 'text/html;charset=utf-8');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Report scaricato: $filename (stampabile in PDF dal browser)'),
          backgroundColor: AppColors.primary,
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Errore durante l\'esportazione del report'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final ok = await saveSurvey(context, ref, complete: true);
    if (ok && navigator.canPop()) navigator.pop();
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.icon, this.trailing});

  final String title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class ClassScale extends StatelessWidget {
  const ClassScale({super.key, required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < EnergyClass.classes.length; i++)
          Builder(builder: (context) {
            final c = EnergyClass.classes[i];
            final selected = c.letter == current;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.35 + 0.065 * i,
                      child: Container(
                        height: selected ? 26 : 18,
                        padding: const EdgeInsets.only(left: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: c.color.withValues(alpha: selected ? 1 : 0.55),
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        ),
                        child: Text(c.letter,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: selected ? 15 : 11,
                            )),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 22,
                    child: selected
                        ? Icon(Icons.arrow_left, color: c.color, size: 26)
                        : null,
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.result, required this.estimating});

  final EnergyResult result;
  final bool estimating;

  @override
  Widget build(BuildContext context) {
    final cls = EnergyClass.of(result.classe);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cls.color.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [BoxShadow(color: cls.color.withValues(alpha: 0.12), blurRadius: 24)],
      ),
      child: LayoutBuilder(builder: (context, c) {
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Classe stimata', style: AppTextStyles.labelLarge),
              if (estimating) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
              ],
            ]),
            const SizedBox(height: 4),
            Text(result.classe,
                key: const ValueKey('result_class'),
                style: TextStyle(
                  fontSize: 64, fontWeight: FontWeight.w800, color: cls.color, height: 1.05)),
            Text(cls.description, style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppSpacing.md),
            _metric('EPgl,nren', '${_num(result.epGlNren, 1)} kWh/m²anno'),
            _metric('Riferimento (DM 26/06/2015)', '${_num(result.epRifStandard, 1)} kWh/m²anno'),
            _metric('Rapporto', _num(result.rapportoEp, 2)),
            if (result.comune != null)
              _metric('Comune', '${result.comune!.label} · zona ${result.zona}'),
          ],
        );
        if (c.maxWidth < 520) {
          return Column(children: [summary, const SizedBox(height: AppSpacing.md), ClassScale(current: result.classe)]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: ClassScale(current: result.classe)),
          ],
        );
      }),
    );
  }

  Widget _metric(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: AppTextStyles.bodySmall)),
          Text(value, style: AppTextStyles.labelLarge),
        ]),
      );
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context) {
    final quality = result.qualitaInvernale;
    final qColor = switch (quality) {
      'alta' => AppColors.success,
      'media' => AppColors.warning,
      _ => AppColors.error,
    };
    final tiles = [
      _Kpi('Spesa energetica', '${_eur(result.costoAnnuoEur)}/anno', Icons.euro, AppColors.primary),
      _Kpi('Emissioni CO₂', '${_num(result.co2KgAnno / 1000, 1)} t/anno', Icons.co2, AppColors.accent),
      _Kpi('Rinnovabile', '${_num(result.epGlRen, 1)} kWh/m²', Icons.eco, AppColors.success),
      _Kpi('Involucro inverno', quality.isEmpty ? '—' : 'Qualità $quality', Icons.shield_outlined, qColor),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth > 640 ? 4 : 2;
        final w = (c.maxWidth - (perRow - 1) * AppSpacing.sm) / perRow;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      }),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(value, style: AppTextStyles.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _AssumptionsCard extends ConsumerWidget {
  const _AssumptionsCard({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = result.assunzioni;
    return _Card(
      title: 'Dati da rilevare (${items.length})',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Per questi dati è stato usato un valore tipico: completali per una stima più precisa.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final a in items)
            InkWell(
              onTap: () => ref.read(surveyProvider.notifier).goToStep(stepForField(a.campo)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: AppColors.warning),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(a.descrizione, style: AppTextStyles.bodyMedium)),
                    Text(a.valore, style: AppTextStyles.bodySmall),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double, Color)>[
      ('Riscaldamento', result.epValue('h_nren'), const Color(0xFFF47B20)),
      ('Acqua calda sanitaria', result.epValue('w_nren'), const Color(0xFF2DD4BF)),
      ('Raffrescamento', result.epValue('c_nren'), const Color(0xFF60A5FA)),
      ('Ventilazione', result.epValue('v_nren'), const Color(0xFFA78BFA)),
      ('Fotovoltaico', result.epValue('fv_nren'), AppColors.success),
    ].where((r) => r.$2.abs() >= 0.05).toList();
    final maxV = rows.fold<double>(1, (m, r) => r.$2.abs() > m ? r.$2.abs() : m);
    return _Card(
      title: 'Energia primaria non rinnovabile per servizio',
      icon: Icons.bar_chart,
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(width: 150, child: Text(r.$1, style: AppTextStyles.bodyMedium)),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (r.$2.abs() / maxV).clamp(0.02, 1.0),
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: r.$3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(_num(r.$2, 1),
                        textAlign: TextAlign.right, style: AppTextStyles.labelLarge),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(children: [
            const Expanded(child: Text('Fabbisogno ideale riscaldamento (EPH,nd)', style: AppTextStyles.bodySmall)),
            Text('${_num(result.epValue('h_nd'), 1)} kWh/m²anno', style: AppTextStyles.bodySmall),
          ]),
          Row(children: [
            const Expanded(child: Text('Rendimento globale impianto', style: AppTextStyles.bodySmall)),
            Text(_num((result.impianto['eta_h_globale'] as num?) ?? 0, 2), style: AppTextStyles.bodySmall),
          ]),
        ],
      ),
    );
  }
}

class _EnvelopeCard extends StatelessWidget {
  const _EnvelopeCard({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context) {
    final geo = result.geometria;
    final u = result.trasmittanze;
    final lim = result.trasmittanzeLimite;
    final rows = <(String, String, String)>[
      ('Pareti', 'pareti', 'pareti_opache'),
      ('Copertura', 'copertura', 'copertura'),
      ('Pavimento', 'pavimento', 'pavimento'),
      ('Finestre', 'finestre', 'superfici_finestrate'),
    ];
    return _Card(
      title: 'Involucro: trasmittanze stimate',
      icon: Icons.grid_view,
      child: Column(
        children: [
          const Row(children: [
            Expanded(child: Text('Elemento', style: AppTextStyles.bodySmall)),
            SizedBox(width: 70, child: Text('m²', textAlign: TextAlign.right, style: AppTextStyles.bodySmall)),
            SizedBox(width: 80, child: Text('U W/m²K', textAlign: TextAlign.right, style: AppTextStyles.bodySmall)),
            SizedBox(width: 80, child: Text('Limite', textAlign: TextAlign.right, style: AppTextStyles.bodySmall)),
          ]),
          const Divider(color: AppColors.border),
          for (final r in rows)
            if (((geo[r.$3] as num?) ?? 0) > 0)
              Builder(builder: (context) {
                final uv = (u[r.$2] as num?)?.toDouble() ?? 0;
                final lv = (lim[r.$2] as num?)?.toDouble() ?? 0;
                final ok = uv <= lv * 1.05;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text(r.$1, style: AppTextStyles.bodyMedium)),
                    SizedBox(
                        width: 70,
                        child: Text(_num((geo[r.$3] as num?) ?? 0),
                            textAlign: TextAlign.right, style: AppTextStyles.bodyMedium)),
                    SizedBox(
                        width: 80,
                        child: Text(_num(uv, 2),
                            textAlign: TextAlign.right,
                            style: AppTextStyles.labelLarge
                                .copyWith(color: ok ? AppColors.success : AppColors.warning))),
                    SizedBox(
                        width: 80,
                        child: Text(_num(lv, 2),
                            textAlign: TextAlign.right, style: AppTextStyles.bodySmall)),
                  ]),
                );
              }),
          const SizedBox(height: AppSpacing.xs),
          const Text('Limite: edificio di riferimento DM 26/06/2015 (2019/21) per la zona climatica.',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _ConsumptionCard extends StatelessWidget {
  const _ConsumptionCard({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context) {
    final pv = result.fotovoltaico;
    return _Card(
      title: 'Consumi annui stimati',
      icon: Icons.receipt_long_outlined,
      trailing: Text(_eur(result.costoAnnuoEur), style: AppTextStyles.titleMedium),
      child: Column(
        children: [
          for (final c in result.consumi)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(c.label, style: AppTextStyles.bodyMedium)),
                Text('${_num(c.quantita)} ${c.unita}', style: AppTextStyles.bodyMedium),
                SizedBox(
                    width: 90,
                    child: Text(_eur(c.costoEur),
                        textAlign: TextAlign.right, style: AppTextStyles.labelLarge)),
              ]),
            ),
          if (((pv['produzione_kwh'] as num?) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Expanded(child: Text('Fotovoltaico: prodotto / autoconsumato', style: AppTextStyles.bodySmall)),
                Text('${pv['produzione_kwh']} / ${pv['autoconsumo_kwh']} kWh', style: AppTextStyles.bodySmall),
              ]),
            ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Uso convenzionale (20 °C, stagione di legge), prezzi medi indicativi.',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _ImprovementsCard extends StatelessWidget {
  const _ImprovementsCard({required this.result});

  final EnergyResult result;

  @override
  Widget build(BuildContext context) {
    final items = result.interventi;
    return _Card(
      title: 'Interventi migliorativi',
      icon: Icons.trending_up,
      child: items.isEmpty
          ? const Text('Nessun intervento con benefici significativi.', style: AppTextStyles.bodyMedium)
          : Column(children: [for (final i in items) _ImprovementTile(item: i, from: result.classe)]),
    );
  }
}

/// L'agente consulente è configurato sul server? (false su qualsiasi errore)
final advisorEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(apiClientProvider).advisorEnabled(),
);

/// «Analisi consulente»: l'agente LLM sceglie e spiega gli interventi più
/// convenienti; costi, incentivi e rientro arrivano dal motore di stima.
/// Nascosta se il server non ha l'LLM configurato.
class _AdvisorCard extends ConsumerStatefulWidget {
  const _AdvisorCard();

  @override
  ConsumerState<_AdvisorCard> createState() => _AdvisorCardState();
}

class _AdvisorCardState extends ConsumerState<_AdvisorCard> {
  bool _loading = false;
  String? _error;
  AdvisorResult? _result;

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = ref.read(surveyProvider).estimateBody();
      final r = await ref.read(apiClientProvider).advisor(body);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(advisorEnabledProvider).valueOrNull ?? false;
    if (!enabled) return const SizedBox.shrink();
    final r = _result;
    return _Card(
      title: 'Analisi consulente',
      icon: Icons.auto_awesome,
      trailing: TextButton(
        key: const ValueKey('advisor_run'),
        onPressed: _loading ? null : _run,
        child: Text(r == null ? 'Analizza' : 'Rifai analisi'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_error != null)
            Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))
          else if (r == null)
            const Text(
                'Un assistente AI valuta quali interventi convengono di più per questo '
                'edificio e in quanti anni si rientra della spesa.',
                style: AppTextStyles.bodySmall)
          else ...[
            if (r.sintesi.isNotEmpty) Text(r.sintesi, style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, rec) in r.raccomandazioni.indexed) _AdvisorTile(index: i + 1, rec: rec),
            for (final w in r.avvertenze)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $w', style: AppTextStyles.bodySmall),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(r.nota, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _AdvisorTile extends StatelessWidget {
  const _AdvisorTile({required this.index, required this.rec});

  final int index;
  final AdvisorRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final payback = rec.tempoRitornoNettoAnni;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$index. ${rec.titolo}${rec.classe.isEmpty ? '' : ' → classe ${rec.classe}'}',
              style: AppTextStyles.labelLarge),
          if (rec.motivazione.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(rec.motivazione, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: 4),
          Wrap(spacing: AppSpacing.md, runSpacing: 2, children: [
            Text('costo ~${_eur(rec.investimentoEur)}', style: AppTextStyles.bodySmall),
            if (rec.incentivoEur > 0)
              Text('incentivo ~${_eur(rec.incentivoEur)}', style: AppTextStyles.bodySmall),
            Text('${_eur(rec.risparmioAnnuoEur)}/anno', style: AppTextStyles.bodySmall),
            Text(
                payback == null
                    ? 'rientro oltre 15 anni'
                    : 'rientro ~${_num(payback, 1)} anni',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ]),
        ],
      ),
    );
  }
}

class _ImprovementTile extends StatelessWidget {
  const _ImprovementTile({required this.item, required this.from});

  final Improvement item;
  final String from;

  @override
  Widget build(BuildContext context) {
    final to = EnergyClass.of(item.classe);
    final payback = item.tempoRitornoAnni;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: item.isGlobal ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: item.isGlobal ? AppColors.primary : AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.intervento, style: AppTextStyles.labelLarge),
                const SizedBox(height: 4),
                Wrap(spacing: AppSpacing.md, runSpacing: 2, children: [
                  Text('−${_num(item.riduzioneEpPct)}% energia', style: AppTextStyles.bodySmall),
                  Text('${_eur(item.risparmioAnnuoEur)}/anno', style: AppTextStyles.bodySmall),
                  Text('costo ~${_eur(item.investimentoEur)}', style: AppTextStyles.bodySmall),
                  if (payback != null)
                    Text('rientro ~${_num(payback)} anni', style: AppTextStyles.bodySmall),
                ]),
                if (item.hasIncentive) ...[
                  const SizedBox(height: 2),
                  Wrap(spacing: AppSpacing.md, runSpacing: 2, children: [
                    Text('incentivo ~${_eur(item.incentivoEur)}',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                    if (item.investimentoNettoEur != null)
                      Text('netto ~${_eur(item.investimentoNettoEur!)}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                    Text(
                        item.tempoRitornoNettoAnni == null
                            ? 'rientro con incentivo oltre 15 anni'
                            : 'rientro con incentivo ~${_num(item.tempoRitornoNettoAnni!)} anni',
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(children: [
            Text('$from →', style: AppTextStyles.bodySmall),
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: to.color, borderRadius: BorderRadius.circular(8)),
              child: Text(item.classe,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Step 6 – "Scheda CENED": i dati salvati del sopralluogo ordinati come le
/// schermate di CENED+2.0, da ricopiare nel software (nessun XML: vedi spec).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/survey_save.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

/// Scheda CENED dei dati **salvati**: se il sopralluogo è nuovo o ha
/// modifiche non salvate lo salva prima (bozza). Null se non disponibile.
Future<CenedSheet?> loadCenedSheet(BuildContext context, WidgetRef ref,
    {bool quiet = true}) async {
  final notifier = ref.read(surveyProvider);
  if (notifier.data.surveyId == null || notifier.dirty) {
    final ok = await saveSurvey(context, ref, quiet: quiet);
    if (!ok) return null;
  }
  final id = ref.read(surveyProvider).data.surveyId;
  if (id == null) return null;
  return ref.read(apiClientProvider).getCenedSheet(id);
}

class CenedSheetCard extends ConsumerStatefulWidget {
  const CenedSheetCard({super.key});

  @override
  ConsumerState<CenedSheetCard> createState() => _CenedSheetCardState();
}

class _CenedSheetCardState extends ConsumerState<CenedSheetCard> {
  CenedSheet? _sheet;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = ref.read(surveyProvider);
    // Sopralluogo già salvato e senza modifiche: la scheda è subito attuale.
    if (n.data.surveyId != null && !n.dirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = await loadCenedSheet(context, ref, quiet: true);
      if (mounted) setState(() => _sheet = sheet ?? _sheet);
    } on UnauthorizedException {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      await ref.read(authProvider).handleUnauthorized();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.statusCode == 0
            ? 'Server non raggiungibile.'
            : 'Scheda non disponibile (${e.statusCode}): ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return Container(
      key: const ValueKey('cened_card'),
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
            const Icon(Icons.fact_check_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
                child: Text('Scheda CENED', style: AppTextStyles.titleMedium)),
            TextButton.icon(
              key: const ValueKey('cened_load'),
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(sheet == null ? Icons.play_arrow : Icons.refresh,
                      size: 18),
              label: Text(sheet == null ? 'Genera' : 'Aggiorna'),
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Dati del sopralluogo nell\'ordine delle schermate di CENED+2.0 '
            '(Regione Lombardia), da ricopiare nel software. Generata dai dati '
            'salvati.',
            style: AppTextStyles.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          ],
          if (sheet != null) ..._sheetBody(sheet),
        ],
      ),
    );
  }

  List<Widget> _sheetBody(CenedSheet sheet) {
    final missing = sheet.missingCount;
    return [
      const SizedBox(height: AppSpacing.md),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(sheet.disclaimer,
            key: const ValueKey('cened_disclaimer'),
            style: AppTextStyles.bodySmall),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        missing == 0
            ? 'Tutti i dati sono presenti.'
            : '$missing ${missing == 1 ? 'dato da rilevare' : 'dati da rilevare'} '
                '(evidenziati).',
        key: const ValueKey('cened_missing_count'),
        style: AppTextStyles.bodyMedium.copyWith(
            color: missing == 0 ? AppColors.success : AppColors.warning),
      ),
      for (final section in sheet.sections) ...[
        const SizedBox(height: AppSpacing.md),
        Text(section.title, style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        if (section.rows.isEmpty)
          Text('Nessun dato.', style: AppTextStyles.bodySmall)
        else
          for (var i = 0; i < section.rows.length; i++)
            _CenedRowTile(
              key: ValueKey('cened_row_${section.key}_$i'),
              row: section.rows[i],
            ),
      ],
    ];
  }
}

class _CenedRowTile extends StatelessWidget {
  const _CenedRowTile({super.key, required this.row});

  final CenedRow row;

  @override
  Widget build(BuildContext context) {
    final missing = row.missing;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: missing ? AppColors.warning.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: missing
            ? Border.all(color: AppColors.warning.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: AppTextStyles.bodyMedium),
                if (row.cenedField != null)
                  Text(row.cenedField!,
                      style: AppTextStyles.bodySmall
                          .copyWith(fontFamily: 'monospace', fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 4,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  missing ? 'da rilevare' : row.displayValue,
                  textAlign: TextAlign.right,
                  style: missing
                      ? AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.warning,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600)
                      : AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w600),
                ),
                if (row.estimated && !missing) const _EstimatedPill(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EstimatedPill extends StatelessWidget {
  const _EstimatedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: const Text('stimato',
          style: TextStyle(
              color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

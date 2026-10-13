import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/widgets/energy_gauge.dart';
import 'package:pre_ape/features/onboarding/step1_general_data.dart';
import 'package:pre_ape/features/onboarding/step2_building.dart';
import 'package:pre_ape/features/onboarding/step3_envelope.dart';
import 'package:pre_ape/features/onboarding/step4_systems.dart';
import 'package:pre_ape/features/onboarding/step5_photos.dart';
import 'package:pre_ape/features/onboarding/step6_results.dart';
import 'package:pre_ape/features/onboarding/survey_save.dart';

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(surveyProvider);
    final survey = notifier.data;
    final currentStep = notifier.currentStep;

    return PopScope(
      canPop: !notifier.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit(context, ref);
      },
      child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, ref, survey, currentStep),
            _buildStepIndicator(ref, currentStep),
            Expanded(
              child: _buildStepContent(context, ref, currentStep),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Leave the wizard: unsaved changes are saved as a draft first; if the
  /// save fails the user decides whether to discard them.
  Future<void> _exit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(surveyProvider);
    final navigator = Navigator.of(context);
    if (!notifier.dirty) {
      navigator.pop();
      return;
    }
    final saved = await saveSurvey(context, ref);
    if (saved) {
      navigator.pop();
      return;
    }
    if (!context.mounted || !navigator.canPop()) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Uscire senza salvare?'),
        content: const Text(
            'Il salvataggio non è riuscito: le modifiche andranno perse.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Resta'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Esci', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (discard == true) {
      ref.read(surveyProvider).startNew(); // drop the unsaved state
      navigator.pop();
    }
  }

  Widget _buildHeader(
      BuildContext context, WidgetRef ref, SurveyData survey, int currentStep) {
    final saving = ref.watch(surveyProvider.select((n) => n.saving));
    final title = (survey.title?.trim().isNotEmpty ?? false)
        ? survey.title!.trim()
        : (survey.surveyId == null ? 'Nuovo sopralluogo' : 'Sopralluogo');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => ref.read(surveyProvider.notifier).goToStep(SurveyNotifier.totalSteps),
            child: EnergyGauge(score: survey.score, size: 72),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    survey.status == 'completed' ? 'Completato' : 'Bozza',
                    if (survey.result != null)
                      'EP ${survey.result!.epGlNren.toStringAsFixed(0)} kWh/m²a',
                    if (survey.estimating) 'calcolo…',
                  ].join(' · '),
                  style: AppTextStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('wizard_save'),
            tooltip: 'Salva bozza',
            onPressed: saving ? null : () => saveSurvey(context, ref),
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  )
                : const Icon(Icons.save_outlined, color: AppColors.textMuted),
          ),
          IconButton(
            key: const ValueKey('wizard_close'),
            tooltip: 'Salva ed esci',
            onPressed: saving ? null : () => _exit(context, ref),
            icon: const Icon(Icons.close, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  static const _stepLabels = ['Dati', 'Edificio', 'Involucro', 'Impianti', 'Foto', 'Risultati'];

  Widget _buildStepIndicator(WidgetRef ref, int currentStep) {
    final notifier = ref.read(surveyProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: LayoutBuilder(builder: (context, constraints) {
        // On phones only the current step keeps its label.
        final wide = constraints.maxWidth >= 520;
        return Row(
          children: [
            for (var i = 1; i <= _stepLabels.length; i++) ...[
              if (i > 1) Expanded(child: _StepLine(isActive: currentStep >= i)),
              InkWell(
                key: ValueKey('step_dot_$i'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => notifier.goToStep(i),
                child: _StepDot(
                  step: i,
                  label: wide || currentStep == i ? _stepLabels[i - 1] : '',
                  isActive: currentStep == i,
                  isCompleted: currentStep > i,
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildStepContent(BuildContext context, WidgetRef ref, int currentStep) {
    return switch (currentStep) {
      2 => const Step2Building(),
      3 => const Step3Envelope(),
      4 => const Step4Systems(),
      5 => const Step5Photos(),
      6 => const Step6Results(),
      _ => const Step1GeneralData(),
    };
  }
}

class _StepDot extends StatelessWidget {
  final int step;
  final String label;
  final bool isActive;
  final bool isCompleted;

  const _StepDot({
    required this.step,
    required this.label,
    required this.isActive,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.primary : AppColors.surfaceElevated,
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
          ),
          child: isCompleted
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : Center(
                  child: Text(
                    step.toString(),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: (isActive
                  ? AppTextStyles.labelMedium.copyWith(color: AppColors.primary)
                  : AppTextStyles.labelMedium)
              .copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool isActive;

  const _StepLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(left: 2, right: 2, bottom: 14),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.border,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
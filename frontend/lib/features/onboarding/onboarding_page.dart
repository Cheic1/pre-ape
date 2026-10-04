import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/widgets/energy_gauge.dart';
import 'package:pre_ape/features/onboarding/step1_general_data.dart';
import 'package:pre_ape/features/onboarding/step2_enclosure.dart';
import 'package:pre_ape/features/onboarding/step3_systems.dart';
import 'package:pre_ape/features/onboarding/step4_photos.dart';
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
            _buildStepIndicator(currentStep),
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
          EnergyGauge(score: survey.currentScore, size: 80),
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
                  survey.status == 'completed'
                      ? 'Completato · stima indicativa'
                      : 'Bozza · stima indicativa',
                  style: AppTextStyles.bodyMedium,
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

  Widget _buildStepIndicator(int currentStep) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepDot(step: 1, label: 'Dati', isActive: currentStep == 1, isCompleted: currentStep > 1),
          _StepLine(isActive: currentStep >= 2),
          _StepDot(step: 2, label: 'Involucro', isActive: currentStep == 2, isCompleted: currentStep > 2),
          _StepLine(isActive: currentStep >= 3),
          _StepDot(step: 3, label: 'Impianti', isActive: currentStep == 3, isCompleted: currentStep > 3),
          _StepLine(isActive: currentStep >= 4),
          _StepDot(step: 4, label: 'Foto', isActive: currentStep == 4, isCompleted: false),
        ],
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, WidgetRef ref, int currentStep) {
    switch (currentStep) {
      case 1:
        return const Step1GeneralData();
      case 2:
        return const Step2Enclosure();
      case 3:
        return const Step3Systems();
      case 4:
        return const Step4Photos();
      default:
        return const Step1GeneralData();
    }
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
          width: 32,
          height: 32,
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
          style: isActive
              ? AppTextStyles.labelMedium.copyWith(color: AppColors.primary)
              : AppTextStyles.labelMedium,
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
      width: 40,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary : AppColors.border,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
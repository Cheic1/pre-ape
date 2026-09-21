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

final currentStepProvider = StateProvider<int>((ref) => 1);

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final survey = ref.watch(surveyProvider).data;
    final currentStep = ref.watch(currentStepProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, survey, currentStep),
            _buildStepIndicator(currentStep),
            Expanded(
              child: _buildStepContent(context, ref, currentStep),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SurveyData survey, int currentStep) {
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
                const Text(
                  'Pre-APE',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Certificazione Energetica',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              // TODO: Save & exit
            },
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
          _StepDot(step: 1, label: 'Dati', isActive: currentStep == 1),
          _StepLine(isActive: currentStep >= 2),
          _StepDot(step: 2, label: 'Involucro', isActive: currentStep == 2),
          _StepLine(isActive: currentStep >= 3),
          _StepDot(step: 3, label: 'Impianti', isActive: currentStep == 3),
          _StepLine(isActive: currentStep >= 4),
          _StepDot(step: 4, label: 'Foto', isActive: currentStep == 4),
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

  const _StepDot({
    required this.step,
    required this.label,
    required this.isActive,
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
          child: isActive
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
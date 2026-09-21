import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverprovider.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

class Step1GeneralData extends ConsumerWidget {
  const Step1GeneralData({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final survey = ref.watch(surveyProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Dati Generali', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Inserisci le informazioni di base dell\'edificio', style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        
        _buildAddressField(ref, survey),
        const SizedBox(height: AppSpacing.lg),
        
        _buildMqSlider(ref, survey),
        const SizedBox(height: AppSpacing.lg),
        
        _buildHeightSlider(ref, survey),
        
        const SizedBox(height: AppSpacing.xxl),
        
        _buildNextButton(context, ref),
      ],
    );
  }

  Widget _buildAddressField(WidgetRef ref, SurveyData survey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Indirizzo', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  survey.address ?? 'Seleziona indirizzo sulla mappa',
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMqSlider(WidgetRef ref, SurveyData survey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('M² Totali', style: AppTextStyles.labelLarge),
            const Spacer(),
            Text(
              '${survey.squareMeters?.toInt() ?? 0} m²',
              style: AppTextStyles.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Slider(
          value: survey.squareMeters ?? 0,
          min: 0,
          max: 500,
          divisions: 50,
          label: '${survey.squareMeters?.toInt() ?? 0} m²',
          onChanged: (value) {
            ref.read(surveyProvider.notifier).updateSquareMeters(value);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        const Row(
          children: [
            Text('0 m²', style: AppTextStyles.bodySmall),
            Spacer(),
            Text('500 m²', style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _buildHeightSlider(WidgetRef ref, SurveyData survey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Altezza Media', style: AppTextStyles.labelLarge),
            const Spacer(),
            Text(
              '${survey.avgHeight?.toStringAsFixed(1) ?? 0} m',
              style: AppTextStyles.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Slider(
          value: survey.avgHeight ?? 0,
          min: 2,
          max: 6,
          divisions: 40,
          label: '${survey.avgHeight?.toStringAsFixed(1) ?? 0} m',
          onChanged: (value) {
            ref.read(surveyProvider.notifier).updateAvgHeight(value);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        const Row(
          children: [
            Text('2 m', style: AppTextStyles.bodySmall),
            Spacer(),
            Text('6 m', style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  Widget _buildNextButton(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.glow,
      ),
      child: MaterialButton(
        onPressed: () {
          ref.read(surveyProvider.notifier).nextStep();
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Avanti',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
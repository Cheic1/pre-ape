import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

class Step3Systems extends ConsumerWidget {
  const Step3Systems({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final survey = ref.watch(surveyProvider).data;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Impianti', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Tipo di riscaldamento e generatore', style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        
        Text('Tipo Riscaldamento', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.md),
        _buildHeatingSelector(ref, survey),
        
        const SizedBox(height: AppSpacing.xxl),
        
        Text('Generatore', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.md),
        _buildGeneratorSelector(ref, survey),
        
        const SizedBox(height: AppSpacing.xxl),
        
        _buildNavButtons(context, ref),
      ],
    );
  }

  Widget _buildHeatingSelector(WidgetRef ref, SurveyData survey) {
    final options = [
      _HeatOption('Pompa di Calore', Icons.electric_bolt, 'Efficiente'),
      _HeatOption('Condensazione', Icons.whatshot, 'Alta efficienza'),
      _HeatOption('Pellet', Icons.local_fire_department, 'Economica'),
      _HeatOption('Gas', Icons.gas_meter, 'Tradizionale'),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((opt) {
        final isSelected = survey.heatingType == opt.value;
        return GestureDetector(
          onTap: () {
            ref.read(surveyProvider.notifier).updateHeatingType(opt.value);
          },
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? AppShadows.glow : null,
            ),
            child: Column(
              children: [
                Icon(opt.icon, color: isSelected ? AppColors.primary : AppColors.textMuted, size: 28),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  opt.value,
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  opt.description,
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGeneratorSelector(WidgetRef ref, SurveyData survey) {
    final options = [
      _GenOption('Caldaia a Condensazione', Icons.electrical_services),
      _GenOption('Caldaia Tradizionale', Icons.electrical_services_outlined),
      _GenOption('Stufa a Pellet', Icons.local_fire_department),
      _GenOption('Pompa Calore Aria-Aria', Icons.electric_bolt),
      _GenOption('Pannelli Solari', Icons.solar_power),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: options.map((opt) {
        final isSelected = survey.generatorType == opt.value;
        return GestureDetector(
          onTap: () {
            ref.read(surveyProvider.notifier).updateGeneratorType(opt.value);
          },
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? AppShadows.glow : null,
            ),
            child: Column(
              children: [
                Icon(opt.icon, color: isSelected ? AppColors.primary : AppColors.textMuted, size: 28),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  opt.value,
                  style: AppTextStyles.titleMedium,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNavButtons(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => ref.read(surveyProvider.notifier).previousStep(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: const Text('Indietro'),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.glow,
            ),
            child: IconButton(
              onPressed: () => ref.read(surveyProvider.notifier).nextStep(),
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Avanti',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeatOption {
  final String value;
  final IconData icon;
  final String description;

  _HeatOption(this.value, this.icon, this.description);
}

class _GenOption {
  final String value;
  final IconData icon;

  _GenOption(this.value, this.icon);
}
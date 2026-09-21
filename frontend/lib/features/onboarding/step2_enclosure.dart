import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

class Step2Enclosure extends ConsumerWidget {
  const Step2Enclosure({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final survey = ref.watch(surveyProvider).data;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Involucro', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Spessore muri e tipo di infissi', style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        
        // Spessore Muri
        Text('Spessore Muri', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.md),
        _buildWallThicknessSelector(ref, survey),
        const SizedBox(height: AppSpacing.lg),
        
        // AR Measurement Button
        _buildARMeasurementButton(context, ref, survey),
        
        const SizedBox(height: AppSpacing.xxl),
        
        // Tipo Infissi
        Text('Tipo Infissi', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.md),
        _buildWindowTypeSelector(ref, survey),
        
        const SizedBox(height: AppSpacing.xxl),
        
        // Bottone navigazione
        _buildNavButtons(context, ref),
      ],
    );
  }

  Widget _buildWallThicknessSelector(WidgetRef ref, SurveyData survey) {
    final options = [
      _WallOption('<30cm', 'Sottile', Icons.check_box_outline_blank),
      _WallOption('30-40cm', 'Medio', Icons.indeterminate_check_box),
      _WallOption('>40cm', 'Spesso', Icons.check_box),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = survey.wallThickness == opt.value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: _SelectorCard(
              isSelected: isSelected,
              icon: opt.icon,
              label: opt.label,
              onTap: () {
                ref.read(surveyProvider.notifier).updateWallThickness(opt.value);
              },
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildARMeasurementButton(BuildContext context, WidgetRef ref, SurveyData survey) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: MaterialButton(
        onPressed: () {
          // HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Avviamento AR per misurazione spessore muri...'),
              backgroundColor: AppColors.surfaceElevated,
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten, color: AppColors.primary, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Misurazione AR Spessore Muri',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowTypeSelector(WidgetRef ref, SurveyData survey) {
    final frameTypes = [
      _FrameOption('Legno', Icons.radio_button_checked),
      _FrameOption('PVC', Icons.check_box),
      _FrameOption('Alluminio', Icons.tab),
    ];

    final glassTypes = [
      _GlassOption('Singolo', 1),
      _GlassOption('Doppio', 2),
      _GlassOption('Triplo', 3),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Telaio
        Text('Materiale Telaio', style: AppTextStyles.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: frameTypes.map((opt) {
            final isSelected = survey.windowType?.contains(opt.value) ?? false;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: _SelectorCard(
                  isSelected: isSelected,
                  icon: opt.icon,
                  label: opt.value,
                  onTap: () {
                    final glass = survey.windowType?.split(' ').last ?? 'Singolo';
                    ref.read(surveyProvider.notifier)
                        .updateWindowType('${opt.value} $glass');
                  },
                ),
              ),
            );
          }).toList(),
        ),
        
        const SizedBox(height: AppSpacing.lg),
        
        // Vetro
        Text('Tipo Vetro', style: AppTextStyles.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: glassTypes.map((opt) {
            final frame = survey.windowType?.split(' ').first ?? 'Legno';
            final isSelected = survey.windowType?.contains(opt.label) ?? false;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: _SelectorCard(
                  isSelected: isSelected,
                  icon: Icons.layers,
                  label: opt.label,
                  onTap: () {
                    ref.read(surveyProvider.notifier)
                        .updateWindowType('$frame ${opt.label}');
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ],
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

class _WallOption {
  final String value;
  final String label;
  final IconData icon;

  _WallOption(this.value, this.label, this.icon);
}

class _FrameOption {
  final String value;
  final IconData icon;

  _FrameOption(this.value, this.icon);
}

class _GlassOption {
  final String label;
  final int panes;

  _GlassOption(this.label, this.panes);
}

class _SelectorCard extends StatelessWidget {
  final bool isSelected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SelectorCard({
    required this.isSelected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : AppColors.textMuted, size: 32),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppTextStyles.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
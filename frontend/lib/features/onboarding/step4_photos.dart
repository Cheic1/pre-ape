import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

class Step4Photos extends ConsumerWidget {
  const Step4Photos({super.key});

  static const List<_PhotoSlot> _slots = [
    _PhotoSlot('Facciata', 'Foto edificio frontale', Icons.photo_camera),
    _PhotoSlot('Caldaia', 'Etichetta caldaia', Icons.photo_camera),
    _PhotoSlot('Finestra', 'Dettaglio infisso', Icons.photo_camera),
    _PhotoSlot('Muro', 'Spessore muratura', Icons.photo_camera),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final survey = ref.watch(surveyProvider).data;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Rilievo Fotografico', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Scatta le foto guidate del sopralluogo', style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),
        
        // Grid foto
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: _slots.map((slot) {
            final hasPhoto = survey.photoPaths != null &&
                             survey.photoPaths!.any((p) => p.contains(slot.label));
            return _PhotoSlotCard(
              slot: slot,
              hasPhoto: hasPhoto,
              onTap: () => _capturePhoto(context, ref, slot),
            );
          }).toList(),
        ),
        
        const SizedBox(height: AppSpacing.xxl),
        
        // Bottone
        _buildNavButtons(context, ref, survey),
      ],
    );
  }

  void _capturePhoto(BuildContext context, WidgetRef ref, _PhotoSlot slot) {
    // TODO: Apri camera con overlay di guida
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Apertura camera per: ${slot.label}'),
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  Widget _buildNavButtons(BuildContext context, WidgetRef ref, SurveyData survey) {
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
              onPressed: () {
                // TODO: Generate report
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Generazione report in corso...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Esporta Report',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoSlot {
  final String label;
  final String description;
  final IconData icon;

  const _PhotoSlot(this.label, this.description, this.icon);
}

class _PhotoSlotCard extends StatelessWidget {
  final _PhotoSlot slot;
  final bool hasPhoto;
  final VoidCallback onTap;

  const _PhotoSlotCard({
    required this.slot,
    required this.hasPhoto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 160,
        decoration: BoxDecoration(
          color: hasPhoto ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hasPhoto ? AppColors.primary : AppColors.border,
            width: hasPhoto ? 2 : 1,
          ),
          boxShadow: hasPhoto ? AppShadows.glow : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.md),
            Icon(
              hasPhoto ? Icons.check_circle : slot.icon,
              color: hasPhoto ? AppColors.primary : AppColors.textMuted,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              slot.label,
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              slot.description,
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
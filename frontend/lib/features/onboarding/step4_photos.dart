import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/web/web_download_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_download.dart';
import 'package:pre_ape/features/web/web_file_picker_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_file_picker.dart';

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
            return _PhotoSlotCard(
              slot: slot,
              photoDataUrl: survey.photos[slot.label],
              onTap: () => _capturePhoto(context, ref, slot),
            );
          }).toList(),
        ),

        const SizedBox(height: AppSpacing.xxl),

        // Bottone
        _buildNavButtons(context, ref),
      ],
    );
  }

  // ── Photo capture ────────────────────────────────────────────────────

  void _capturePhoto(BuildContext context, WidgetRef ref, _PhotoSlot slot) {
    final survey = ref.read(surveyProvider).data;
    final hasPhoto = survey.photos.containsKey(slot.label);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  const Icon(Icons.photo_camera, color: AppColors.primary),
              title: const Text('Scatta foto'),
              subtitle: const Text('Apri la fotocamera'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ref, slot, camera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: AppColors.primary),
              title: const Text('Scegli dalla galleria'),
              subtitle: const Text('Seleziona un file dal dispositivo'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ref, slot, camera: false);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: const Text('Rimuovi foto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref.read(surveyProvider.notifier).removePhoto(slot.label);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(
    WidgetRef ref,
    _PhotoSlot slot, {
    required bool camera,
  }) async {
    final picked = await pickImageFile(camera: camera);
    if (picked == null) return; // User cancelled.
    ref.read(surveyProvider.notifier).updatePhoto(slot.label, picked.dataUrl);
  }

  // ── Report export ────────────────────────────────────────────────────

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final survey = ref.read(surveyProvider).data;
    final html = buildReportHtml(survey);
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final filename = 'PreAPE_rilievo_$stamp.html';

    try {
      downloadTextFile(filename, html, 'text/html;charset=utf-8');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Report scaricato: $filename (apribile anche come PDF dal browser)'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore durante l\'esportazione del report'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Navigation ───────────────────────────────────────────────────────

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
              onPressed: () => _exportReport(context, ref),
              icon: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Esporta Report',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
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
  final String? photoDataUrl;
  final VoidCallback onTap;

  const _PhotoSlotCard({
    required this.slot,
    required this.photoDataUrl,
    required this.onTap,
  });

  bool get hasPhoto => photoDataUrl != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 160,
        decoration: BoxDecoration(
          color: hasPhoto
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surfaceElevated,
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
            const SizedBox(height: AppSpacing.sm),
            if (hasPhoto)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Image.memory(
                  base64Decode(photoDataUrl!.split(',').last),
                  width: 124,
                  height: 70,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: AppColors.textMuted,
                    size: 40,
                  ),
                ),
              )
            else
              Icon(
                slot.icon,
                color: AppColors.textMuted,
                size: 40,
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              slot.label,
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              hasPhoto ? 'Tocca per modificare' : slot.description,
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/report_builder.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/web_media.dart';
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
    final additional = survey.additionalPhotos;

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

        // Altre foto (aggiuntive, cap [kMaxAdditionalPhotos])
        const Text('Altre foto', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Foto aggiuntive del sopralluogo (max $kMaxAdditionalPhotos)',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            if (additional.length < kMaxAdditionalPhotos)
              _AddPhotoTile(onTap: () => _openAdditionalSheet(context, ref)),
            for (var i = 0; i < additional.length; i++)
              _AdditionalPhotoThumb(
                key: ValueKey('additional_photo_$i'),
                dataUrl: additional[i],
                index: i,
                onRemove: () => _removeAdditionalPhoto(context, ref, i),
              ),
          ],
        ),
        if (additional.length >= kMaxAdditionalPhotos)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Hai raggiunto il massimo di $kMaxAdditionalPhotos foto aggiuntive.',
              style: AppTextStyles.bodySmall,
            ),
          ),

        const SizedBox(height: AppSpacing.xxl),

        // Bottone
        _buildNavButtons(context, ref),
      ],
    );
  }

  // ── Photo capture (stessa bottom sheet per slot e foto aggiuntive) ────

  void _openPhotoSheet(
    BuildContext context, {
    required void Function(bool camera) onPick,
    bool showRemove = false,
    VoidCallback? onRemove,
  }) {
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
                onPick(true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library,
                  color: AppColors.primary),
              title: const Text('Scegli dalla galleria'),
              subtitle: const Text('Seleziona un file dal dispositivo'),
              onTap: () {
                Navigator.of(ctx).pop();
                onPick(false);
              },
            ),
            if (showRemove && onRemove != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: const Text('Rimuovi foto'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onRemove();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _capturePhoto(BuildContext context, WidgetRef ref, _PhotoSlot slot) {
    final survey = ref.read(surveyProvider).data;
    final hasPhoto = survey.photos.containsKey(slot.label);
    _openPhotoSheet(
      context,
      onPick: (camera) => _pickSlotPhoto(context, ref, slot, camera: camera),
      showRemove: hasPhoto,
      onRemove: () => ref.read(surveyProvider.notifier).removePhoto(slot.label),
    );
  }

  void _openAdditionalSheet(BuildContext context, WidgetRef ref) {
    _openPhotoSheet(
      context,
      onPick: (camera) => _pickAdditionalPhotos(context, ref, camera: camera),
    );
  }

  /// Pick for one of the 4 guided slots (single photo), normalised through
  /// `normalizeImageForState` (EXIF strip + downscale + cap on web).
  Future<void> _pickSlotPhoto(
    BuildContext context,
    WidgetRef ref,
    _PhotoSlot slot, {
    required bool camera,
  }) async {
    final notifier = ref.read(surveyProvider.notifier);
    final picked = await pickImageFiles(camera: camera);
    if (picked == null || picked.isEmpty) return; // User cancelled.
    final normalized = await normalizeImageForState(picked.first.dataUrl);
    if (!context.mounted) return;
    if (normalized == null) {
      _showMessage(
        context,
        'Foto non valida: formato o dimensione non supportati',
        AppColors.error,
      );
      return;
    }
    if (!notifier.updatePhoto(slot.label, normalized)) {
      _showMessage(
        context,
        'Foto non salvata: supera il limite di dimensione',
        AppColors.error,
      );
    }
  }

  /// Pick one or more additional photos (`input.multiple` on web for the
  /// gallery); each one is normalised and appended until the cap.
  Future<void> _pickAdditionalPhotos(
    BuildContext context,
    WidgetRef ref, {
    required bool camera,
  }) async {
    final notifier = ref.read(surveyProvider.notifier);
    final picked = await pickImageFiles(camera: camera, multiple: !camera);
    if (picked == null || picked.isEmpty) return; // User cancelled.
    var added = 0;
    for (final file in picked) {
      final normalized = await normalizeImageForState(file.dataUrl);
      if (normalized != null && notifier.addAdditionalPhoto(normalized)) {
        added++;
      }
    }
    if (!context.mounted) return;
    if (added == 0) {
      _showMessage(
        context,
        'Nessuna foto aggiunta: formato o dimensione non supportati',
        AppColors.error,
      );
    } else if (added < picked.length) {
      _showMessage(
        context,
        '$added foto aggiunte, le altre scartate (limite raggiunto)',
        AppColors.primary,
      );
    } else {
      _showMessage(
        context,
        added == 1 ? 'Foto aggiunta' : '$added foto aggiunte',
        AppColors.primary,
      );
    }
  }

  void _removeAdditionalPhoto(BuildContext context, WidgetRef ref, int index) {
    final notifier = ref.read(surveyProvider.notifier);
    if (notifier.removeAdditionalPhoto(index)) {
      _showMessage(context, 'Foto aggiuntiva rimossa', AppColors.primary);
    }
  }

  void _showMessage(BuildContext context, String message, Color color) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
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

/// Decode tollerante: restituisce null invece di lanciare se il payload
/// base64 è corrotto (evita errori di build nella griglia).
Uint8List? _tryDecodeDataUrl(String dataUrl) {
  try {
    return base64Decode(dataUrl.split(',').last);
  } catch (_) {
    return null;
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
    final bytes = photoDataUrl == null ? null : _tryDecodeDataUrl(photoDataUrl!);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
            if (hasPhoto && bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Image.memory(
                  bytes,
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

/// Tile "Aggiungi foto": riapre la stessa bottom sheet degli slot.
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 140,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_a_photo,
                  color: AppColors.primary, size: 40),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Aggiungi foto',
                style: AppTextStyles.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thumbnail di una foto aggiuntiva con pulsante ✕ (rimozione per indice).
class _AdditionalPhotoThumb extends StatelessWidget {
  const _AdditionalPhotoThumb({
    super.key,
    required this.dataUrl,
    required this.index,
    required this.onRemove,
  });

  final String dataUrl;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final bytes = _tryDecodeDataUrl(dataUrl);
    return SizedBox(
      width: 140,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? const Center(
                      child: Icon(Icons.broken_image,
                          color: AppColors.textMuted, size: 40),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: AppColors.textMuted,
                        size: 40,
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: Colors.white,
                tooltip: 'Rimuovi foto aggiuntiva ${index + 1}',
                onPressed: onRemove,
              ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

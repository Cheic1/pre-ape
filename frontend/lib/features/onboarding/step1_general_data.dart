import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

class Step1GeneralData extends ConsumerStatefulWidget {
  const Step1GeneralData({super.key});

  @override
  ConsumerState<Step1GeneralData> createState() => _Step1GeneralDataState();
}

class _Step1GeneralDataState extends ConsumerState<Step1GeneralData> {
  bool _locationInitiated = false;

  @override
  Widget build(BuildContext context) {
    // Trigger browser geolocation once on first build.
    if (!_locationInitiated) {
      _locationInitiated = true;
      // Schedule after the current frame to avoid setState-during-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(surveyProvider.notifier).fetchLocation();
      });
    }

    final survey = ref.watch(surveyProvider).data;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Dati Generali', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Inserisci le informazioni di base dell\'edificio',
            style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),

        _buildAddressField(context, ref, survey),
        const SizedBox(height: AppSpacing.lg),

        _buildMqSlider(ref, survey),
        const SizedBox(height: AppSpacing.lg),

        _buildHeightSlider(ref, survey),

        const SizedBox(height: AppSpacing.xxl),

        _buildNextButton(context, ref),
      ],
    );
  }

  // ── Address field ───────────────────────────────────────────────────

  Widget _buildAddressField(
      BuildContext context, WidgetRef ref, SurveyData survey) {
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
              Icon(
                survey.locating ? Icons.hourglass_empty : Icons.location_on_outlined,
                color: survey.locating ? AppColors.primary : AppColors.textMuted,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: survey.locating
                    ? Text(
                        'Rilevamento posizione…',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : Text(
                        survey.address ?? 'Seleziona indirizzo sulla mappa',
                        style: AppTextStyles.bodyMedium,
                      ),
              ),
              IconButton(
                onPressed: () => _openAddressEditor(context, ref, survey),
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.primary, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Address editor dialog ──────────────────────────────────────────

  void _openAddressEditor(
      BuildContext context, WidgetRef ref, SurveyData survey) {
    final controller = TextEditingController(text: survey.address ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Indirizzo edificio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Manual text entry
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Via Roma 1, Milano',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Geolocation button (web only)
              if (kIsWeb)
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await ref
                        .read(surveyProvider.notifier)
                        .fetchLocation();
                    // If no address was resolved, show coordinates as fallback.
                    if (context.mounted) {
                      final s = ref.read(surveyProvider).data;
                      if (s.address == null && !s.locating) {
                        ref.read(surveyProvider.notifier).updateAddress(
                              '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}',
                            );
                      }
                    }
                  },
                  icon: const Icon(Icons.my_location, size: 18),
                  label: const Text('Usa la mia posizione'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),

              if (kIsWeb) const SizedBox(height: AppSpacing.sm),

              // Open OSM map (web only)
              if (kIsWeb)
                OutlinedButton.icon(
                  onPressed: () async {
                    final lat = survey.latitude;
                    final lng = survey.longitude;
                    await _openOsmMap(lat, lng);
                  },
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Apri mappa e importa punto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(surveyProvider.notifier)
                  .updateAddress(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  /// Open OpenStreetMap at the current coordinates to let the user pick a point.
  /// After the user clicks a location on OSM, they copy the coordinates from
  /// the URL hash (e.g. #map=17/41.90280/12.49640) and paste them back via a
  /// small import dialog that appears after the map opens.
  Future<void> _openOsmMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Small delay to let the external browser open, then prompt.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _promptImportOsmCoordinates(context, ref, lat, lng);
  }

  void _promptImportOsmCoordinates(
      BuildContext context, WidgetRef ref, double lat, double lng) {
    final controller =
        TextEditingController(text: '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa coordinate da OSM'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Incolla lat, lng (es. 41.902800, 12.496400)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              final parts = controller.text.split(',');
              if (parts.length >= 2) {
                final lat_ = double.tryParse(parts[0].trim());
                final lng_ = double.tryParse(parts[1].trim());
                if (lat_ != null && lng_ != null) {
                  ref.read(surveyProvider.notifier).updateLatLng(lat_, lng_);
                  final addr = await reverseGeocode(lat_, lng_);
                  if (addr != null && addr.isNotEmpty) {
                    ref.read(surveyProvider.notifier).updateAddress(addr);
                  }
                }
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Importa'),
          ),
        ],
      ),
    );
  }

  // ── Sliders ────────────────────────────────────────────────────────

  Widget _buildMqSlider(WidgetRef ref, SurveyData survey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('M² Totali', style: AppTextStyles.labelLarge),
            const Spacer(),
            Text(
              '${survey.squareMeters.toInt()} m²',
              style: AppTextStyles.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Slider(
          value: survey.squareMeters,
          min: 0,
          max: 500,
          divisions: 50,
          label: '${survey.squareMeters.toInt()} m²',
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
              '${survey.avgHeight.toStringAsFixed(1)} m',
              style: AppTextStyles.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Slider(
          value: survey.avgHeight,
          min: 2,
          max: 4,
          divisions: 20,
          label: '${survey.avgHeight.toStringAsFixed(1)} m',
          onChanged: (value) {
            ref.read(surveyProvider.notifier).updateAvgHeight(value);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            const Text('2 m', style: AppTextStyles.bodySmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _promptManualHeight(context, ref, survey),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Inserisci manually'),
            ),
            const Spacer(),
            const Text('4 m', style: AppTextStyles.bodySmall),
          ],
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  void _promptManualHeight(
      BuildContext context, WidgetRef ref, SurveyData survey) {
    final controller =
        TextEditingController(text: survey.avgHeight.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Altezza media'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'es. 2.7'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.replaceAll(',', '.'));
              if (v != null && v >= 0) {
                ref.read(surveyProvider.notifier).updateAvgHeight(v);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Salva'),
          ),
        ],
      ),
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

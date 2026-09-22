import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/web_geolocation_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/onboarding/web_geolocation.dart';
import 'package:pre_ape/features/onboarding/web_map_widget_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/onboarding/web_map_widget.dart';

class Step1GeneralData extends ConsumerStatefulWidget {
  const Step1GeneralData({super.key});

  @override
  ConsumerState<Step1GeneralData> createState() => _Step1GeneralDataState();
}

class _Step1GeneralDataState extends ConsumerState<Step1GeneralData> {
  bool _locationInitiated = false;
  late final TextEditingController _addressController;
  late final FocusNode _addressFocus;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _addressFocus = FocusNode();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

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

    // Keep the text field in sync with the provider, unless the user is
    // currently typing in it (so GPS/map results never clobber keystrokes).
    if (!_addressFocus.hasFocus &&
        _addressController.text != (survey.address ?? '')) {
      _addressController.text = survey.address ?? '';
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Dati Generali', style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Inserisci le informazioni di base dell\'edificio',
            style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.xl),

        _buildAddressField(context, ref, survey),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Scrivi l\'indirizzo e premi la lente per cercarlo, oppure seleziona un punto sulla mappa.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),

        // Interactive Leaflet/OpenStreetMap (web only).
        if (kIsWeb)
          SizedBox(
            height: 300,
            child: WebMapWidget(
              latitude: survey.latitude,
              longitude: survey.longitude,
              onPointSelected: (lat, lng) => _onMapPointSelected(ref, lat, lng),
            ),
          ),

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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Icon(
                  survey.locating
                      ? Icons.hourglass_empty
                      : Icons.location_on_outlined,
                  color:
                      survey.locating ? AppColors.primary : AppColors.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _addressController,
                  focusNode: _addressFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchAddress(ref),
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: survey.locating
                        ? 'Rilevamento posizione…'
                        : 'Via Roma 1, Milano…',
                    hintStyle: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerca indirizzo sulla mappa',
                onPressed: () => _searchAddress(ref),
                icon: const Icon(Icons.search,
                    color: AppColors.primary, size: 20),
              ),
              IconButton(
                tooltip: 'Usa la mia posizione',
                onPressed:
                    survey.locating ? null : () => _useMyLocation(ref),
                icon: survey.locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location,
                        color: AppColors.primary, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Forward geocode the typed address: moves the map marker and replaces the
  /// text with the canonical address returned by Nominatim.
  Future<void> _searchAddress(WidgetRef ref) async {
    final query = _addressController.text.trim();
    if (query.isEmpty) return;

    final result = await forwardGeocode(query);
    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Indirizzo non trovato: prova a selezionarlo sulla mappa.'),
          backgroundColor: AppColors.surfaceElevated,
        ),
      );
      return;
    }

    ref
        .read(surveyProvider.notifier)
        .updateLatLng(result.lat, result.lng);
    ref.read(surveyProvider.notifier).updateAddress(result.name);
    _addressController.text = result.name;
    _addressController.selection =
        TextSelection.collapsed(offset: result.name.length);
  }

  /// Explicit GPS button: force a fresh geolocation + reverse geocode.
  Future<void> _useMyLocation(WidgetRef ref) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await ref.read(surveyProvider.notifier).fetchLocation(force: true);
    if (!mounted) return;
    final s = ref.read(surveyProvider).data;
    if (s.address == null && !s.locating) {
      ref.read(surveyProvider.notifier).updateAddress(
            '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}',
          );
    }
  }

  /// Called when the user taps or drags on the embedded map.
  /// Updates lat/lng in the provider and attempts reverse geocoding.
  void _onMapPointSelected(WidgetRef ref, double lat, double lng) {
    ref.read(surveyProvider.notifier).updateLatLng(lat, lng);
    // Best-effort reverse geocoding – non-blocking failure.
    reverseGeocode(lat, lng).then((addr) {
      if (addr != null && addr.isNotEmpty && mounted) {
        ref.read(surveyProvider.notifier).updateAddress(addr);
      }
    });
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
              label: const Text('Inserisci manualmente'),
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

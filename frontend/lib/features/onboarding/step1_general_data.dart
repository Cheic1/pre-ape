import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/models/energy.dart';
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
  late final TextEditingController _titleController;
  late final TextEditingController _clientController;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController();
    _addressFocus = FocusNode();
    final data = ref.read(surveyProvider).data;
    _titleController = TextEditingController(text: data.title ?? '');
    _clientController = TextEditingController(text: data.clientName ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _clientController.dispose();
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
        const StepHeader(
            'Dati generali', 'Pratica, indirizzo e dati climatici del comune'),

        _buildPracticeFields(ref),
        const SizedBox(height: AppSpacing.lg),

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

        const ClimateSection(),

        const WizardNav(showBack: false),
      ],
    );
  }

  // ── Practice header (title + client) ────────────────────────────────

  Widget _buildPracticeFields(WidgetRef ref) {
    final notifier = ref.read(surveyProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pratica', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        _boxedField(
          key: const ValueKey('survey_title'),
          controller: _titleController,
          hint: 'Riferimento pratica (es. APE 12/2026)',
          icon: Icons.folder_outlined,
          onChanged: notifier.updateTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        _boxedField(
          key: const ValueKey('survey_client'),
          controller: _clientController,
          hint: 'Cliente / committente',
          icon: Icons.person_outline,
          onChanged: notifier.updateClientName,
        ),
      ],
    );
  }

  Widget _boxedField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
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
            child: Icon(icon, color: AppColors.textMuted, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              key: key,
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
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
                  onChanged: (value) {
                    // Free-typed text enters the survey immediately so the
                    // report always has an address, even without geocoding.
                    ref.read(surveyProvider.notifier).updateAddress(value);
                  },
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                onPressed: survey.locating ? null : () => _useMyLocation(ref),
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
          content:
              Text('Indirizzo non trovato: prova a selezionarlo sulla mappa.'),
          backgroundColor: AppColors.surfaceElevated,
        ),
      );
      return;
    }

    ref.read(surveyProvider.notifier).updateLatLng(result.lat, result.lng);
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
}

/// Comune (zona climatica e gradi giorno DPR 412/93): ricavato
/// dall'indirizzo dal server, oppure scelto/corretto a mano.
class ClimateSection extends ConsumerWidget {
  const ClimateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(surveyProvider.notifier);
    final building = ref.watch(surveyProvider.select((n) => n.data.building));
    final result = ref.watch(surveyProvider.select((n) => n.data.result));
    final detected = result?.comune;
    final manual = building['comune'] != null;

    return SectionCard(
      title: 'Località e clima',
      icon: Icons.thermostat,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: result == null
              ? const Text('Calcolo in corso…', style: AppTextStyles.bodyMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      detected?.label ?? 'Comune non individuato',
                      key: const ValueKey('climate_comune'),
                      style: AppTextStyles.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Zona climatica ${result.zona} · ${result.gradiGiorno} gradi giorno'
                      '${detected?.altitudine != null ? ' · ${detected!.altitudine} m s.l.m.' : ''}',
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      manual
                          ? 'Comune scelto manualmente'
                          : detected == null
                              ? 'Inserisci l\'indirizzo o scegli il comune qui sotto'
                              : 'Ricavato dall\'indirizzo (DPR 412/93)',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        const FieldLabel('Comune', fieldKey: 'comune'),
        _ComuneAutocomplete(
          initial: building['comune'] as String?,
          onSelected: (c) => notifier.setBuildingAll({
            'comune': c.comune,
            'provincia': c.provincia,
          }),
          onCleared: manual
              ? () =>
                  notifier.setBuildingAll({'comune': null, 'provincia': null})
              : null,
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Correggi zona o gradi giorno',
                  style: AppTextStyles.bodyMedium),
              initiallyExpanded: building['zona_climatica'] != null ||
                  building['gradi_giorno'] != null,
              children: const [
                ChoiceField(
                    fieldKey: 'zona_climatica',
                    label: 'Zona climatica',
                    options: zonaOpts),
                NumberField(
                  fieldKey: 'gradi_giorno',
                  label: 'Gradi giorno',
                  integer: true,
                  max: 6000,
                  hint: 'dal regolamento comunale, se aggiornato',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ComuneAutocomplete extends ConsumerWidget {
  const _ComuneAutocomplete(
      {required this.initial, required this.onSelected, this.onCleared});

  final String? initial;
  final ValueChanged<ComuneInfo> onSelected;
  final VoidCallback? onCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    return Autocomplete<ComuneInfo>(
      key: ValueKey('comune_${initial ?? ''}'),
      initialValue: TextEditingValue(text: initial ?? ''),
      displayStringForOption: (c) => c.comune,
      optionsBuilder: (value) async {
        final q = value.text.trim();
        if (q.length < 2) return const <ComuneInfo>[];
        try {
          return await api.searchComuni(q);
        } catch (_) {
          return const <ComuneInfo>[];
        }
      },
      onSelected: (c) {
        FocusManager.instance.primaryFocus?.unfocus();
        onSelected(c);
      },
      optionsViewBuilder: (context, onSelect, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: AppColors.surfaceElevated,
          elevation: 6,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final c in options)
                  ListTile(
                    dense: true,
                    title: Text(c.label, style: AppTextStyles.bodyLarge),
                    subtitle: Text('Zona ${c.zona} · ${c.gradiGiorno} GG',
                        style: AppTextStyles.bodySmall),
                    onTap: () => onSelect(c),
                  ),
              ],
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
        key: const ValueKey('comune_field'),
        controller: controller,
        focusNode: focus,
        style: AppTextStyles.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Cerca il comune…',
          prefixIcon:
              const Icon(Icons.location_city, color: AppColors.textMuted),
          suffixIcon: onCleared == null
              ? null
              : IconButton(
                  tooltip: 'Torna al comune dell\'indirizzo',
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () {
                    controller.clear();
                    onCleared!();
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

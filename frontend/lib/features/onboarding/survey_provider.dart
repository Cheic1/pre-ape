import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/models/energy.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

import 'web_geolocation_stub.dart'
    if (dart.library.js_interop) 'web_geolocation.dart';
import 'web_media.dart';

/// Default centre of Italy (near Rome) used when the browser Geolocation
/// API is unavailable or the user denies the permission prompt.
const _defaultLatLng = (lat: 41.9028, lng: 12.4964);

class SurveyData {
  /// Server id once the survey has been saved at least once (null = new).
  String? surveyId;

  /// Practice header: reference/title and client name; free-text notes.
  String? title;
  String? clientName;
  String? notes;

  /// `draft` | `completed` (server status).
  String status = 'draft';

  String? address;

  /// Superficie utile (m²). Default 80 m² – alloggio tipo.
  double squareMeters = 80.0;

  /// Default 2.7 m – standard residential floor-to-ceiling height.
  double avgHeight = 2.7;

  /// Coordinates – initialised to centre of Italy; updated by
  /// browser Geolocation when available.
  double latitude = _defaultLatLng.lat;
  double longitude = _defaultLatLng.lng;

  /// True while the browser Geolocation request is in flight.
  bool locating = false;

  /// Input del calcolo energetico (schema `BuildingInputs` del backend,
  /// valori in `energy_options.dart`). Chiave assente = dato non rilevato:
  /// il server usa un valore tipico e lo elenca in `result.assunzioni`.
  Map<String, Object?> building = {};

  /// Ultima stima calcolata dal server (null finché non arriva).
  EnergyResult? result;

  /// True while an estimate request is in flight.
  bool estimating = false;

  /// Photos captured for the survey, keyed by slot label
  /// (e.g. 'Facciata') and valued as a base64 data-URL.
  Map<String, String> photos = {};

  /// Additional photos of the survey, valued as base64 data-URLs.
  /// Order = stable index used by [SurveyNotifier.removeAdditionalPhoto];
  /// capped at [kMaxAdditionalPhotos].
  List<String> additionalPhotos = [];

  /// Score 0–100 for the gauge (server `punteggio`), null before the first
  /// estimate.
  double? get score => result?.punteggio;

  SurveyData copyWith({
    String? surveyId,
    String? title,
    String? clientName,
    String? notes,
    String? status,
    String? address,
    double? squareMeters,
    double? avgHeight,
    double? latitude,
    double? longitude,
    bool? locating,
    Map<String, Object?>? building,
    EnergyResult? result,
    bool? estimating,
    Map<String, String>? photos,
    List<String>? additionalPhotos,
  }) {
    return SurveyData()
      ..surveyId = surveyId ?? this.surveyId
      ..title = title ?? this.title
      ..clientName = clientName ?? this.clientName
      ..notes = notes ?? this.notes
      ..status = status ?? this.status
      ..address = address ?? this.address
      ..photos = photos ?? this.photos
      ..additionalPhotos = additionalPhotos ?? this.additionalPhotos
      ..squareMeters = squareMeters ?? this.squareMeters
      ..avgHeight = avgHeight ?? this.avgHeight
      ..latitude = latitude ?? this.latitude
      ..longitude = longitude ?? this.longitude
      ..locating = locating ?? this.locating
      ..building = building ?? this.building
      ..result = result ?? this.result
      ..estimating = estimating ?? this.estimating;
  }
}

/// First-MVP flat columns → `building` keys (old surveys keep their answers).
const _legacyHeating = {
  'Pompa di Calore': 'pompa_calore_aria_acqua',
  'Condensazione': 'caldaia_condensazione',
  'Pellet': 'stufa_pellet',
  'Gas': 'caldaia_tradizionale',
  'Caldaia a Condensazione': 'caldaia_condensazione',
  'Caldaia Tradizionale': 'caldaia_tradizionale',
  'Stufa a Pellet': 'stufa_pellet',
  'Pompa Calore Aria-Aria': 'split_aria_aria',
};

Map<String, Object?> _buildingFrom(SurveyRead s) {
  final b = <String, Object?>{...?s.building};
  void legacy(String key, Object? value, List<Opt> allowed) {
    if (b.containsKey(key) || value == null) return;
    if (allowed.any((o) => o.value == value)) b[key] = value;
  }

  legacy('spessore_muri', s.wallThickness, spessoreOpts);
  legacy('telaio', s.windowFrame, telaioOpts);
  legacy('vetro', s.windowGlass, vetroOpts);
  legacy('generatore',
      _legacyHeating[s.generatorType] ?? _legacyHeating[s.heatingType], generatoreOpts);
  if (!b.containsKey('anno_generatore') && s.generatorYear != null) {
    b['anno_generatore'] = s.generatorYear;
  }
  if (!b.containsKey('potenza_kw') && s.generatorPowerKw != null) {
    b['potenza_kw'] = s.generatorPowerKw;
  }
  return b;
}

class SurveyNotifier extends ChangeNotifier {
  SurveyNotifier({
    ApiClient? api,
    this.estimateDebounce = const Duration(milliseconds: 500),
  }) : _api = api;

  /// Client used for the live estimate (null in unit tests: no estimate).
  final ApiClient? _api;
  final Duration estimateDebounce;

  static const int totalSteps = 6;

  SurveyData _data = SurveyData();
  int _currentStep = 1;
  bool _locationFetched = false;
  bool _saving = false;
  bool _dirty = false;
  Timer? _estimateTimer;
  int _estimateSeq = 0;
  bool _disposed = false;

  SurveyData get data => _data;
  int get currentStep => _currentStep;

  /// True while a save request is in flight.
  bool get saving => _saving;

  /// True when there are changes not yet saved to the server.
  bool get dirty => _dirty;

  void _touch() => _dirty = true;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _estimateTimer?.cancel();
    super.dispose();
  }

  /// Start a brand-new survey (fresh state, GPS lookup allowed again).
  void startNew() {
    _data = SurveyData();
    _currentStep = 1;
    _locationFetched = false;
    _dirty = false;
    notifyListeners();
    _scheduleEstimate(immediate: true);
  }

  /// Load a survey fetched from the server into the wizard.
  void loadFrom(SurveyRead s) {
    final data = SurveyData()
      ..surveyId = s.id
      ..title = s.title
      ..clientName = s.clientName
      ..notes = s.notes
      ..status = s.status
      ..address = s.address
      ..squareMeters = s.squareMeters ?? 80.0
      ..avgHeight = s.avgHeight ?? 2.7
      ..latitude = s.latitude ?? _defaultLatLng.lat
      ..longitude = s.longitude ?? _defaultLatLng.lng
      ..building = _buildingFrom(s)
      ..result = s.energyResult
      ..photos = Map<String, String>.of(s.photos ?? const {})
      ..additionalPhotos = List<String>.of(s.additionalPhotos ?? const []);
    _data = data;
    _currentStep = 1;
    // An existing survey already has its position: never overwrite it via GPS.
    _locationFetched = true;
    _dirty = false;
    notifyListeners();
    if (data.result == null) _scheduleEstimate(immediate: true);
  }

  /// Energy-relevant subset of the survey (body of `POST /estimate`).
  Map<String, Object?> estimateBody() => <String, Object?>{
        'square_meters': _data.squareMeters,
        'avg_height': _data.avgHeight,
        if (_data.address != null && _data.address!.isNotEmpty)
          'address': _data.address,
        'latitude': _data.latitude,
        'longitude': _data.longitude,
        'building': <String, Object?>{
          for (final e in _data.building.entries)
            if (e.value != null) e.key: e.value,
        },
      };

  /// Wire DTO for POST/PUT.
  SurveyCreate toWire({String? status}) {
    return SurveyCreate(
      title: _data.title,
      clientName: _data.clientName,
      notes: _data.notes,
      status: status,
      address: _data.address,
      latitude: _data.latitude,
      longitude: _data.longitude,
      squareMeters: _data.squareMeters,
      avgHeight: _data.avgHeight,
      building: Map<String, Object?>.of(_data.building),
      photos: _data.photos,
      additionalPhotos: _data.additionalPhotos,
    );
  }

  /// Save to the server (create the first time, then update).
  ///
  /// [complete] marks the survey as `completed`. Throws [ApiException] on
  /// failure (state untouched, still dirty).
  Future<void> save(ApiClient api, {bool complete = false}) async {
    if (_saving) return;
    _saving = true;
    notifyListeners();
    try {
      final body = toWire(status: complete ? 'completed' : null);
      final id = _data.surveyId;
      final saved = id == null
          ? await api.createSurvey(body)
          : await api.updateSurvey(id, body);
      _data = _data.copyWith(
        surveyId: saved.id,
        status: saved.status,
        result: saved.energyResult,
      );
      _dirty = false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // ── Live estimate ────────────────────────────────────────────────────

  void _scheduleEstimate({bool immediate = false}) {
    if (_api == null) return;
    _estimateTimer?.cancel();
    _estimateTimer = Timer(
      immediate ? Duration.zero : estimateDebounce,
      refreshEstimate,
    );
  }

  /// Ask the server for a fresh estimate now. Errors keep the previous
  /// result (a failed preview must never block the survey).
  Future<void> refreshEstimate() async {
    final api = _api;
    if (api == null || !api.isAuthenticated) return;
    final seq = ++_estimateSeq;
    _data = _data.copyWith(estimating: true);
    notifyListeners();
    try {
      final result = await api.estimate(estimateBody());
      if (seq != _estimateSeq || _disposed) return;
      _data = _data.copyWith(result: result, estimating: false);
    } on ApiException {
      if (seq != _estimateSeq || _disposed) return;
      _data = _data.copyWith(estimating: false);
    }
    notifyListeners();
  }

  // ── Field updates ────────────────────────────────────────────────────

  void updateTitle(String value) {
    _data = _data.copyWith(title: value);
    _touch();
    notifyListeners();
  }

  void updateClientName(String value) {
    _data = _data.copyWith(clientName: value);
    _touch();
    notifyListeners();
  }

  void updateNotes(String value) {
    _data = _data.copyWith(notes: value);
    _touch();
    notifyListeners();
  }

  void updateAddress(String address) {
    _data = _data.copyWith(address: address);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  void updateSquareMeters(double mq) {
    _data = _data.copyWith(squareMeters: mq);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  void updateAvgHeight(double height) {
    _data = _data.copyWith(avgHeight: height);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  void updateLatLng(double lat, double lng) {
    _data = _data.copyWith(latitude: lat, longitude: lng);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  /// Value of a `building` input (null = not surveyed).
  Object? building(String key) => _data.building[key];

  /// Set (or clear, with null) a `building` input and refresh the estimate.
  void setBuilding(String key, Object? value) {
    final updated = Map<String, Object?>.of(_data.building);
    if (value == null) {
      updated.remove(key);
    } else {
      updated[key] = value;
    }
    _data = _data.copyWith(building: updated);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  /// Set several `building` inputs at once (e.g. comune + provincia).
  void setBuildingAll(Map<String, Object?> values) {
    final updated = Map<String, Object?>.of(_data.building);
    values.forEach((k, v) => v == null ? updated.remove(k) : updated[k] = v);
    _data = _data.copyWith(building: updated);
    _touch();
    notifyListeners();
    _scheduleEstimate();
  }

  /// Attach (or replace) the photo for a slot label.
  ///
  /// Returns false (state untouched) when [dataUrl] is not an
  /// `data:image/*;base64,` URL, exceeds the per-photo cap
  /// [kMaxPhotoBytes] or would push the whole photo state over
  /// [kMaxTotalPhotoBytes].
  bool updatePhoto(String slot, String dataUrl) {
    if (!isImageDataUrl(dataUrl)) return false;
    final bytes = dataUrlBytes(dataUrl);
    if (bytes > kMaxPhotoBytes) return false;
    final previous = _data.photos[slot];
    final freed = previous == null ? 0 : dataUrlBytes(previous);
    if (!_withinPhotoBudget(bytes, freedBytes: freed)) return false;
    _data = _data.copyWith(photos: {..._data.photos, slot: dataUrl});
    _touch();
    notifyListeners();
    return true;
  }

  /// Add an additional photo (M4), at the end of the list.
  ///
  /// Returns false (state untouched) when the cap [kMaxAdditionalPhotos] is
  /// reached or the payload fails validation (image prefix, per-photo cap,
  /// total state cap).
  bool addAdditionalPhoto(String dataUrl) {
    if (_data.additionalPhotos.length >= kMaxAdditionalPhotos) return false;
    if (!isImageDataUrl(dataUrl)) return false;
    final bytes = dataUrlBytes(dataUrl);
    if (bytes > kMaxPhotoBytes) return false;
    if (!_withinPhotoBudget(bytes)) return false;
    _data = _data.copyWith(
      additionalPhotos: [..._data.additionalPhotos, dataUrl],
    );
    _touch();
    notifyListeners();
    return true;
  }

  /// Remove the additional photo at [index] (stable index: remaining photos
  /// keep their relative order).  Returns false when the index is out of
  /// range.
  bool removeAdditionalPhoto(int index) {
    if (index < 0 || index >= _data.additionalPhotos.length) return false;
    final updated = [..._data.additionalPhotos]..removeAt(index);
    _data = _data.copyWith(additionalPhotos: updated);
    _touch();
    notifyListeners();
    return true;
  }

  /// Total decoded bytes currently held by slot + additional photos.
  int _photoBytesUsed() {
    var total = 0;
    for (final photo in _data.photos.values) {
      total += dataUrlBytes(photo);
    }
    for (final photo in _data.additionalPhotos) {
      total += dataUrlBytes(photo);
    }
    return total;
  }

  /// True when storing [incomingBytes] (after freeing [freedBytes]) stays
  /// within [kMaxTotalPhotoBytes].
  bool _withinPhotoBudget(int incomingBytes, {int freedBytes = 0}) =>
      _photoBytesUsed() - freedBytes + incomingBytes <= kMaxTotalPhotoBytes;

  /// Remove the photo stored for a slot label, if any.
  void removePhoto(String slot) {
    if (!_data.photos.containsKey(slot)) return;
    final updated = {..._data.photos}..remove(slot);
    _data = _data.copyWith(photos: updated);
    _touch();
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < totalSteps) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 1) {
      _currentStep--;
      notifyListeners();
    }
  }

  /// Jump to a step (step indicator, "completa i dati" links).
  void goToStep(int step) {
    if (step < 1 || step > totalSteps || step == _currentStep) return;
    _currentStep = step;
    notifyListeners();
  }

  /// Attempt to fetch the user's coordinates via the browser Geolocation API
  /// and reverse-geocode them through Nominatim.  On failure, silently keeps
  /// the Italy default so the survey can proceed without blocking the user.
  ///
  /// Safe to call multiple times; only the first invocation triggers the flow
  /// unless [force] is true (explicit "Usa la mia posizione" button press).
  Future<void> fetchLocation({bool force = false}) async {
    if (_locationFetched && !force) return;
    _locationFetched = true;
    if (!kIsWeb) return;

    _data = _data.copyWith(locating: true);
    notifyListeners();

    try {
      final pos = await fetchBrowserGeolocation(
        timeout: const Duration(seconds: 8),
      );
      _data = _data.copyWith(
        latitude: pos.lat,
        longitude: pos.lng,
      );
      notifyListeners();
      _scheduleEstimate();

      // Best-effort reverse geocoding – non-blocking failure.
      final addr = await reverseGeocode(pos.lat, pos.lng);
      if (addr != null && addr.isNotEmpty) {
        _data = _data.copyWith(address: addr);
        notifyListeners();
        _scheduleEstimate();
      }
    } catch (_) {
      // Permission denied or timeout – keep Italy default.
    } finally {
      _data = _data.copyWith(locating: false);
      notifyListeners();
    }
  }
}

final surveyProvider = ChangeNotifierProvider<SurveyNotifier>((ref) {
  return SurveyNotifier(api: ref.watch(apiClientProvider));
});

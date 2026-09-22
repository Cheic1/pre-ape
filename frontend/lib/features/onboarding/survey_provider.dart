import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/scoring.dart';

import 'web_geolocation_stub.dart'
    if (dart.library.js_interop) 'web_geolocation.dart';

/// Default centre of Italy (near Rome) used when the browser Geolocation
/// API is unavailable or the user denies the permission prompt.
const _defaultLatLng = (lat: 41.9028, lng: 12.4964);

class SurveyData {
  String? address;

  /// Default 60 m² – typical apartment in Italy.
  double squareMeters = 60.0;

  /// Default 2.7 m – standard residential floor-to-ceiling height.
  double avgHeight = 2.7;

  /// Coordinates – initialised to centre of Italy; updated by
  /// browser Geolocation when available.
  double latitude = _defaultLatLng.lat;
  double longitude = _defaultLatLng.lng;

  /// True while the browser Geolocation request is in flight.
  bool locating = false;

  double currentScore = 30.0;

  String? wallThickness;
  String? windowType;
  String? heatingType;
  String? generatorType;
  List<String>? photoPaths;

  /// Photos captured for the survey, keyed by slot label
  /// (e.g. 'Facciata') and valued as a base64 data-URL.
  Map<String, String> photos = {};

  SurveyData copyWith({
    String? address,
    double? squareMeters,
    double? avgHeight,
    double? latitude,
    double? longitude,
    bool? locating,
    double? currentScore,
    String? wallThickness,
    String? windowType,
    String? heatingType,
    String? generatorType,
    List<String>? photoPaths,
    Map<String, String>? photos,
  }) {
    return SurveyData()
      ..address = address ?? this.address
      ..photos = photos ?? this.photos
      ..squareMeters = squareMeters ?? this.squareMeters
      ..avgHeight = avgHeight ?? this.avgHeight
      ..latitude = latitude ?? this.latitude
      ..longitude = longitude ?? this.longitude
      ..locating = locating ?? this.locating
      ..currentScore = currentScore ?? this.currentScore
      ..wallThickness = wallThickness ?? this.wallThickness
      ..windowType = windowType ?? this.windowType
      ..heatingType = heatingType ?? this.heatingType
      ..generatorType = generatorType ?? this.generatorType
      ..photoPaths = photoPaths ?? this.photoPaths;
  }
}

class SurveyNotifier extends ChangeNotifier {
  SurveyData _data = SurveyData();
  int _currentStep = 1;
  bool _locationFetched = false;

  SurveyData get data => _data;
  int get currentStep => _currentStep;

  void updateAddress(String address) {
    _data = _data.copyWith(address: address);
    _recalculateScore();
    notifyListeners();
  }

  void updateSquareMeters(double mq) {
    _data = _data.copyWith(squareMeters: mq);
    _recalculateScore();
    notifyListeners();
  }

  void updateAvgHeight(double height) {
    _data = _data.copyWith(avgHeight: height);
    _recalculateScore();
    notifyListeners();
  }

  void updateLatLng(double lat, double lng) {
    _data = _data.copyWith(latitude: lat, longitude: lng);
    notifyListeners();
  }

  void updateWallThickness(String wt) {
    _data = _data.copyWith(wallThickness: wt);
    _recalculateScore();
    notifyListeners();
  }

  void updateWindowType(String wt) {
    _data = _data.copyWith(windowType: wt);
    _recalculateScore();
    notifyListeners();
  }

  void updateHeatingType(String ht) {
    _data = _data.copyWith(heatingType: ht);
    _recalculateScore();
    notifyListeners();
  }

  void updateGeneratorType(String gt) {
    _data = _data.copyWith(generatorType: gt);
    _recalculateScore();
    notifyListeners();
  }

  /// Attach (or replace) the photo for a slot label.
  void updatePhoto(String slot, String dataUrl) {
    _data = _data.copyWith(photos: {..._data.photos, slot: dataUrl});
    notifyListeners();
  }

  /// Remove the photo stored for a slot label, if any.
  void removePhoto(String slot) {
    if (!_data.photos.containsKey(slot)) return;
    final updated = {..._data.photos}..remove(slot);
    _data = _data.copyWith(photos: updated);
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < 4) {
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

      // Best-effort reverse geocoding – non-blocking failure.
      final addr = await reverseGeocode(pos.lat, pos.lng);
      if (addr != null && addr.isNotEmpty) {
        _data = _data.copyWith(address: addr);
        notifyListeners();
      }
    } catch (_) {
      // Permission denied or timeout – keep Italy default.
    } finally {
      _data = _data.copyWith(locating: false);
      notifyListeners();
    }
  }

  /// Score formula extracted to `lib/core/scoring.dart` (single source).
  void _recalculateScore() {
    _data = _data.copyWith(currentScore: computeScore(_data));
  }
}

final surveyProvider = ChangeNotifierProvider<SurveyNotifier>((ref) {
  return SurveyNotifier();
});

// Web-only Geolocation + Nominatim reverse geocoding using package:web + dart:js_interop.
// Only imported on web builds via the conditional import pattern.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<({double lat, double lng})> fetchBrowserGeolocation({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<({double lat, double lng})>();

  web.window.navigator.geolocation.getCurrentPosition(
    ([web.GeolocationPosition? pos]) {
      if (pos == null) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Geolocation returned null position'));
        }
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(
          (lat: pos.coords.latitude, lng: pos.coords.longitude),
        );
      }
    },
    ([web.GeolocationPositionError? err]) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Geolocation denied or unavailable (code ${err?.code})'),
        );
      }
    },
    web.PositionOptions()
      ..timeout = timeout.inMilliseconds
      ..enableHighAccuracy = true
      ..maximumAge = 60000,
  );

  return completer.future;
}

Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final url =
        'https://nominatim.openstreetmap.org/reverse?format=json'
        '&lat=$lat&lon=$lng&zoom=18&addressdetails=1';

    final resp = await web.window
        .fetch(url.toJS, web.RequestInit(
          method: 'GET',
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'PreAPE/1.0 (energy-survey-app)',
          }.jsify(),
        ).toJS)
        .toDart;

    if (!resp.ok) return null;

    final text = await resp.text().toDart;
    final idx = text.indexOf('"display_name"');
    if (idx == -1) return null;
    final colon = text.indexOf(':', idx) + 1;
    final valStart = text.indexOf('"', colon) + 1;
    final valEnd = text.indexOf('"', valStart);
    if (valEnd <= valStart) return null;
    final display = text.substring(valStart, valEnd);
    return display.isNotEmpty ? display : null;
  } catch (_) {
    return null;
  }
}

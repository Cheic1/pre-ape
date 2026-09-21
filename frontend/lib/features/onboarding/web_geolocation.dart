// Conditional import for web-only Geolocation + Nominatim reverse geocoding.
// Only imported on web builds via the stub pattern.

import 'dart:async';
import 'dart:html' as html;

/// Returns (lat, lng) from the browser Geolocation API,
/// or throws on timeout / user denial.
Future<({double lat, double lng})> fetchBrowserGeolocation({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<({double lat, double lng})>();

  html.window.navigator.geolocation.getCurrentPosition(
    (html.GeolocationPosition pos) {
      if (!completer.isCompleted) {
        completer.complete(
          (lat: pos.coords!.latitude!, lng: pos.coords!.longitude!),
        );
      }
    },
    (html.GeolocationPositionError err) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Geolocation denied (code ${err.code})'),
        );
      }
    },
    html.PositionOptions(
      timeout: timeout.inMilliseconds,
      enableHighAccuracy: true,
      maximumAge: 60000,
    ),
  );

  return completer.future;
}

/// Best-effort reverse geocoding via OpenStreetMap Nominatim.
/// Returns a display-name string or null on any failure.
Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final url =
        'https://nominatim.openstreetmap.org/reverse?format=json'
        '&lat=$lat&lon=$lng&zoom=18&addressdetails=1';

    final req = await html.HttpRequest.request(
      url,
      method: 'GET',
      requestHeaders: {
        'Accept': 'application/json',
        'User-Agent': 'PreAPE/1.0 (energy-survey-app)',
      },
    );

    final body = req.responseText ?? '';
    // Minimal parse – extract "display_name" without importing dart:convert.
    final idx = body.indexOf('"display_name"');
    if (idx == -1) return null;
    final colon = body.indexOf(':', idx) + 1;
    final valStart = body.indexOf('"', colon) + 1;
    final valEnd = body.indexOf('"', valStart);
    if (valEnd <= valStart) return null;
    final display = body.substring(valStart, valEnd);
    return display.isNotEmpty ? display : null;
  } catch (_) {
    return null;
  }
}

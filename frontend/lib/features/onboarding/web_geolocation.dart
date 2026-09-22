// Web-only Geolocation + Nominatim geocoding using package:web + dart:js_interop.
// Only imported on web builds via the conditional import pattern.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<({double lat, double lng})> fetchBrowserGeolocation({
  Duration timeout = const Duration(seconds: 10),
}) async {
  final completer = Completer<({double lat, double lng})>();

  // PositionCallback and PositionErrorCallback are JSFunction typedefs.
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition pos) {
      if (!completer.isCompleted) {
        completer.complete(
          (lat: pos.coords.latitude, lng: pos.coords.longitude),
        );
      }
    }).toJS,
    ((web.GeolocationPositionError err) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Geolocation denied or unavailable (code ${err.code})'),
        );
      }
    }).toJS,
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

    // Build headers as a JSObject.
    final headers = web.Headers();
    headers.set('Accept', 'application/json');
    headers.set('User-Agent', 'PreAPE/1.0 (energy-survey-app)');

    final resp = await web.window
        .fetch(
          url.toJS,
          web.RequestInit(
            method: 'GET',
            headers: headers,
          ),
        )
        .toDart;

    if (!resp.ok) return null;

    final text = (await resp.text().toDart).toDart;
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

/// Forward geocode: turn a typed address (e.g. "Via Roma 1, Milano") into
/// coordinates + canonical display name via Nominatim `/search`.
/// Returns null when nothing is found or the request fails.
Future<({double lat, double lng, String name})?> forwardGeocode(
    String query) async {
  try {
    final q = Uri.encodeComponent(query);
    final url = 'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=1&accept-language=it&q=$q';

    final resp = await web.window
        .fetch(url.toJS, web.RequestInit(method: 'GET'))
        .toDart;

    if (!resp.ok) return null;

    final text = (await resp.text().toDart).toDart;
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map) return null;

    final lat = (first['lat'] as num?)?.toDouble();
    final lng = (first['lon'] as num?)?.toDouble();
    final name = first['display_name'] as String?;
    if (lat == null || lng == null || name == null || name.isEmpty) {
      return null;
    }
    return (lat: lat, lng: lng, name: name);
  } catch (_) {
    return null;
  }
}

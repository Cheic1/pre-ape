// Non-web stub – Geolocation and reverse geocoding are not available
// outside the browser.

import 'dart:async';

Future<({double lat, double lng})> fetchBrowserGeolocation({
  Duration timeout = const Duration(seconds: 10),
}) {
  throw UnsupportedError(
    'Browser geolocation is only available on Flutter web builds.',
  );
}

Future<String?> reverseGeocode(double lat, double lng) async => null;

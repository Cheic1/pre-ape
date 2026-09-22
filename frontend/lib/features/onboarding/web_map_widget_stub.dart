import 'package:flutter/material.dart';

/// Non-web stub – map widget is not available outside the browser.
class WebMapWidget extends StatelessWidget {
  final double latitude;
  final double longitude;
  final void Function(double lat, double lng)? onPointSelected;

  const WebMapWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    this.onPointSelected,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

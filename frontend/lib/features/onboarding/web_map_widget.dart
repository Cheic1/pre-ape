import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Shared counter for unique platform-view IDs across the app.
int _viewIdCounter = 0;

/// Interactive Leaflet/OpenStreetMap map for Flutter web.
///
/// Renders an OSM map inside an [HtmlElementView] (iframe with srcdoc).
/// The user can pan, zoom, and click/tap to select a point.
class WebMapWidget extends StatefulWidget {
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
  State<WebMapWidget> createState() => _WebMapWidgetState();
}

class _WebMapWidgetState extends State<WebMapWidget> {
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  bool _iframeReady = false;
  final List<Map<String, dynamic>> _pendingMessages = [];
  StreamSubscription<dynamic>? _messageSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'preape-map-${_viewIdCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createIframe);
    _messageSub = web.window.onMessage.listen(_onMessage);
  }

  // -- Platform view factory ------------------------------------------------

  web.HTMLIFrameElement _createIframe(int viewId) {
    final iframe =
        web.document.createElement('iframe') as web.HTMLIFrameElement;
    iframe.srcdoc = _buildMapHtml().toJS;
    iframe.style.cssText = 'width:100%;height:100%;border:none';

    // Once the iframe (and Leaflet) finishes loading, flush buffered messages.
    iframe.onLoad.listen((_) {
      _iframeReady = true;
      for (final msg in _pendingMessages) {
        _sendToMap(msg);
      }
      _pendingMessages.clear();
    });

    _iframe = iframe;
    return iframe;
  }

  // -- Message handling -----------------------------------------------------

  void _onMessage(dynamic event) {
    if (!mounted) return;
    try {
      final raw = (event as web.MessageEvent).data;
      if (raw == null) return;
      final dartStr = (raw as JSString).toDart;
      final decoded = jsonDecode(dartStr);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] != 'point-selected') return;
      final lat = (decoded['lat'] as num).toDouble();
      final lng = (decoded['lng'] as num).toDouble();
      widget.onPointSelected?.call(lat, lng);
    } catch (_) {
      // Not our message – ignore.
    }
  }

  void _sendToMap(Map<String, dynamic> data) {
    final cw = _iframe?.contentWindow;
    if (cw == null) return;
    cw.postMessage(jsonEncode(data).toJS, '*'.toJS);
  }

  void _sendOrBuffer(Map<String, dynamic> data) {
    if (_iframeReady) {
      _sendToMap(data);
    } else {
      _pendingMessages.add(data);
    }
  }

  // -- HTML generation ------------------------------------------------------

  String _buildMapHtml() {
    final lat = widget.latitude;
    final lng = widget.longitude;
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<link rel="stylesheet"
  href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden}
#map{width:100%;height:100%}
.leaflet-control-attribution{font-size:9px!important}
</style>
</head>
<body>
<div id="map"></div>
<script>
(function(){
  var map=L.map('map',{zoomControl:true}).setView([$lat,$lng],16);
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{
    attribution:'&copy; OSM',maxZoom:19
  }).addTo(map);
  var marker=L.marker([$lat,$lng],{draggable:true}).addTo(map);
  function notify(lat,lng){
    parent.postMessage(
      JSON.stringify({type:'point-selected',lat:lat,lng:lng}),'*');
  }
  map.on('click',function(e){
    marker.setLatLng(e.latlng);
    notify(e.latlng.lat,e.latlng.lng);
  });
  marker.on('dragend',function(e){
    var p=e.target.getLatLng();
    notify(p.lat,p.lng);
  });
  window.addEventListener('message',function(e){
    try{
      var d=typeof e.data==='string'?JSON.parse(e.data):e.data;
      if(d&&d.type==='set-view'){
        map.setView([d.lat,d.lng],16);
        marker.setLatLng([d.lat,d.lng]);
      }
    }catch(err){}
  });
})();
</script>
</body>
</html>''';
  }

  // -- Widget lifecycle -----------------------------------------------------

  @override
  void didUpdateWidget(covariant WebMapWidget old) {
    super.didUpdateWidget(old);
    if (old.latitude != widget.latitude ||
        old.longitude != widget.longitude) {
      _sendOrBuffer({
        'type': 'set-view',
        'lat': widget.latitude,
        'lng': widget.longitude,
      });
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

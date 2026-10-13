// Web-only: re-encode su <canvas> per rimuovere i metadati EXIF/geotag (il
// canvas produce un JPEG pulito), ridurre il lato lungo a [maxSide] px e
// comprimere a [quality], riducendo le dimensioni finché non rientra in
// [maxBytes].  Importato solo tramite import condizionale da `web_media.dart`.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'media_rules.dart';

Future<String?> encodePhotoDataUrl(
  String rawDataUrl, {
  required int maxSide,
  required double quality,
  required int maxBytes,
}) async {
  try {
    final img = await _loadImage(rawDataUrl);
    final naturalW = img.naturalWidth;
    final naturalH = img.naturalHeight;
    if (naturalW <= 0 || naturalH <= 0) return null;

    final longest = naturalW > naturalH ? naturalW : naturalH;
    var scale = longest > maxSide ? maxSide / longest : 1.0;

    final canvas =
        web.document.createElement('canvas') as web.HTMLCanvasElement;
    // getContext('2d') restituisce sempre un CanvasRenderingContext2D per
    // l'ID '2d' (RenderingContext è solo il typedef JSObject del binding).
    final ctx = canvas.getContext('2d');
    if (ctx == null) return null;
    final context2d = ctx as web.CanvasRenderingContext2D;
    final jsQuality = quality.toJS;

    // Il JPEG a qualità fitta non entra nel cap? Riduci il lato lungo di un
    // quarto a tentativi (max 6 passi) prima di rifiutare la foto.
    for (var attempt = 0; attempt < 6; attempt++) {
      var w = (naturalW * scale).round();
      var h = (naturalH * scale).round();
      if (w < 1) w = 1;
      if (h < 1) h = 1;
      canvas.width = w;
      canvas.height = h;
      context2d.drawImage(img, 0, 0, w, h);
      final encoded = canvas.toDataURL('image/jpeg', jsQuality);
      if (!isImageDataUrl(encoded)) return null;
      if (dataUrlBytes(encoded) <= maxBytes) return encoded;
      scale *= 0.75;
      if (w == 1 && h == 1) break;
    }
    return null;
  } catch (_) {
    // Decode fallito o canvas non disponibile: la foto viene rifiutata.
    return null;
  }
}

Future<web.HTMLImageElement> _loadImage(String src) {
  final completer = Completer<web.HTMLImageElement>();
  final img = web.document.createElement('img') as web.HTMLImageElement;
  final onLoad = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(img);
  }).toJS;
  final onError = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Immagine non caricata'));
    }
  }).toJS;
  img.addEventListener('load', onLoad);
  img.addEventListener('error', onError);
  img.src = src;
  return completer.future;
}

// Non-web (VM/mobile): niente <canvas>, quindi nessun re-encode.  Il file
// passa invariato solo se è già conforme (prefisso `data:image/*;base64,` e
// ≤ [maxBytes]); altrimenti viene rifiutato.  Importato solo tramite import
// condizionale da `web_media.dart`.

import 'media_rules.dart';

/// "Re-encode" senza canvas: valida e restituisce il data-URL già conforme,
/// oppure null se non è un'immagine o supera [maxBytes].
///
/// [maxSide] e [quality] sono applicati solo dalla implementazione web
/// (`web_media_encoder_web.dart`).
Future<String?> encodePhotoDataUrl(
  String rawDataUrl, {
  required int maxSide,
  required double quality,
  required int maxBytes,
}) async {
  if (!isImageDataUrl(rawDataUrl)) return null;
  if (dataUrlBytes(rawDataUrl) > maxBytes) return null;
  return rawDataUrl;
}

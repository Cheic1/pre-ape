/// Normalizzazione foto (M5): strip EXIF/geotag via re-encode su canvas,
/// downscale a [kMaxImageSide] px, JPEG ~[kJpegQuality], cap [kMaxPhotoBytes]
/// per foto e validazione del prefisso `data:image/*;base64,`.
///
/// Il re-encode avviene solo sulla build web (`web_media_encoder_web.dart`):
/// su VM/mobile l'encoder passa il file solo se già conforme, altrimenti
/// restituisce null.
library;

import 'media_rules.dart';
import 'web_media_encoder_stub.dart'
    if (dart.library.js_interop) 'web_media_encoder_web.dart';

export 'media_rules.dart';

/// Normalizza un data-URL immagine prima di metterlo in stato (slot o foto
/// aggiuntive).
///
/// - rifiuta subito i prefissi diversi da `data:image/*;base64,`;
/// - su web re-encode su canvas (rimuove EXIF/geotag, riduce il lato lungo a
///   [kMaxImageSide] px, comprime in JPEG ~[kJpegQuality]) riducendo ulteriormente
///   le dimensioni finché non rientra in [kMaxPhotoBytes];
/// - restituisce null se il risultato non è un'immagine o supera il cap.
Future<String?> normalizeImageForState(String rawDataUrl) async {
  if (!isImageDataUrl(rawDataUrl)) return null;
  final encoded = await encodePhotoDataUrl(
    rawDataUrl,
    maxSide: kMaxImageSide,
    quality: kJpegQuality,
    maxBytes: kMaxPhotoBytes,
  );
  return validateImageDataUrl(encoded);
}

// Web: download di bytes via Blob + object URL.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Avvia il download di [bytes] come [filename]; true se avviato.
bool downloadBytes(String filename, Uint8List bytes, String mimeType) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
  return true;
}

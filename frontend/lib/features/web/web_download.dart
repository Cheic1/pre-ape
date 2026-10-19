// Web-only file download via Blob + object URL.
// Only imported on web builds via the conditional import pattern.

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Trigger a browser download of [content] as [filename].
void downloadTextFile(String filename, String content, String mimeType) {
  _download(filename, <JSAny>[content.toJS].toJS, mimeType);
}

/// Trigger a browser download of binary [bytes] as [filename].
void downloadBytesFile(String filename, Uint8List bytes, String mimeType) {
  _download(filename, <JSAny>[bytes.toJS].toJS, mimeType);
}

void _download(String filename, JSArray<JSAny> parts, String mimeType) {
  final blob = web.Blob(parts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = filename;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Revoke on the next tick so the download has time to start.
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
}

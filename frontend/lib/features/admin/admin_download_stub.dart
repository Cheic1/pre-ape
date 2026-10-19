// Non-web stub: il download dei documenti è previsto solo su Flutter web.
import 'dart:typed_data';

/// Restituisce false: nessun download possibile su questa piattaforma.
bool downloadBytes(String filename, Uint8List bytes, String mimeType) => false;

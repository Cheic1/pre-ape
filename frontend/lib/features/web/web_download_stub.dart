// Non-web stub – file download is only wired for Flutter web builds.

import 'dart:typed_data';

void downloadTextFile(String filename, String content, String mimeType) {
  // No-op: on Android/iOS the report should be shared via the share sheet
  // (image_picker/share_plus) once those features land.
}

void downloadBytesFile(String filename, Uint8List bytes, String mimeType) {}

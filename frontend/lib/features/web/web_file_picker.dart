// Web-only multi-file picker using a native <input type="file"> element.
// On mobile browsers `capture` opens the camera directly; on desktop it is
// ignored and the OS file dialog (gallery/folder) opens instead.
// `multiple` enables multi-selection of the additional photos (M4/E2E).
// Only imported on web builds via the conditional import pattern.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Open the camera ([camera] = true) or the gallery/file dialog and return
/// every selected image as base64 data-URLs, or null if the user cancels
/// or no file could be read.
Future<List<({String dataUrl, String name})>?> pickImageFiles({
  bool camera = false,
  bool multiple = false,
}) =>
    _pickFiles(accept: 'image/*', camera: camera, multiple: multiple);

/// Open the file dialog for a single document (PDF/JPEG/PNG by default) and
/// return it as a base64 data-URL, or null if the user cancels.
Future<({String dataUrl, String name})?> pickDocumentFile({
  String accept = 'application/pdf,image/jpeg,image/png',
}) async {
  final files = await _pickFiles(accept: accept);
  return files == null || files.isEmpty ? null : files.first;
}

Future<List<({String dataUrl, String name})>?> _pickFiles({
  required String accept,
  bool camera = false,
  bool multiple = false,
}) async {
  final completer = Completer<List<({String dataUrl, String name})>?>();

  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = accept;
  input.multiple = multiple;
  if (camera) {
    input.setAttribute('capture', 'environment');
  }
  input.style.display = 'none';

  // Some platforms never fire `change` when the dialog is cancelled; the
  // window regains focus instead. Complete(null) in that case.
  late final JSFunction focusHandler;
  focusHandler = ((web.Event _) {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (!completer.isCompleted) completer.complete(null);
      web.window.removeEventListener('focus', focusHandler);
    });
  }).toJS;

  void cleanup() {
    web.window.removeEventListener('focus', focusHandler);
    input.remove();
  }

  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      cleanup();
      return;
    }
    final results = <({String dataUrl, String name})>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i)!;
      final dataUrl = await _readAsDataUrl(file);
      if (dataUrl != null) {
        results.add((dataUrl: dataUrl, name: file.name));
      }
    }
    if (!completer.isCompleted) {
      completer.complete(results.isEmpty ? null : results);
    }
    cleanup();
  });

  web.document.body?.appendChild(input);
  web.window.addEventListener('focus', focusHandler);
  input.click();
  return completer.future;
}

Future<String?> _readAsDataUrl(web.File file) {
  final completer = Completer<String?>();
  final reader = web.FileReader();

  final onLoad = ((web.Event _) {
    final result = reader.result;
    if (!completer.isCompleted) {
      completer.complete(result == null ? null : (result as JSString).toDart);
    }
  }).toJS;

  final onError = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  reader.addEventListener('load', onLoad);
  reader.addEventListener('error', onError);
  reader.readAsDataURL(file);
  return completer.future;
}

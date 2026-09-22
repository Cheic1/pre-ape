// Web-only image picker using a native <input type="file"> element.
// On mobile browsers `capture` opens the camera directly; on desktop it is
// ignored and the OS file dialog (gallery/folder) opens instead.
// Only imported on web builds via the conditional import pattern.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Open the camera ([camera] = true) or the gallery/file dialog and return
/// the selected image as a base64 data-URL, or null if the user cancels.
Future<({String dataUrl, String name})?> pickImageFile({
  bool camera = false,
}) async {
  final completer = Completer<({String dataUrl, String name})?>();

  final input = web.document.createElement('input') as web.HTMLInputElement;
  input.type = 'file';
  input.accept = 'image/*';
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

  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      cleanup();
      return;
    }
    final file = files.item(0)!;
    final reader = web.FileReader();

    final onLoad = ((web.Event _) {
      final result = reader.result;
      if (result == null) {
        if (!completer.isCompleted) completer.complete(null);
      } else {
        final dataUrl = (result as JSString).toDart;
        if (!completer.isCompleted) {
          completer.complete((dataUrl: dataUrl, name: file.name));
        }
      }
      cleanup();
    }).toJS;

    final onError = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
      cleanup();
    }).toJS;

    reader.addEventListener('load', onLoad);
    reader.addEventListener('error', onError);
    reader.readAsDataURL(file);
  });

  web.document.body?.appendChild(input);
  web.window.addEventListener('focus', focusHandler);
  input.click();
  return completer.future;
}

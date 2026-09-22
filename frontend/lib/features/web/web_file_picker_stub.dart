// Non-web stub – the native file/camera picker is only wired for Flutter web
// (Android/iOS need image_picker + platform permissions, see AGENTS.md).

Future<({String dataUrl, String name})?> pickImageFile({
  bool camera = false,
}) async =>
    null;

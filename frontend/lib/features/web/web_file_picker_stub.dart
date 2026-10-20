// Non-web stub – the native file/camera picker is only wired for Flutter web
// (Android/iOS need image_picker + platform permissions, see AGENTS.md).

Future<List<({String dataUrl, String name})>?> pickImageFiles({
  bool camera = false,
  bool multiple = false,
}) async =>
    null;

Future<({String dataUrl, String name})?> pickDocumentFile({
  String accept = 'application/pdf,image/jpeg,image/png',
}) async =>
    null;

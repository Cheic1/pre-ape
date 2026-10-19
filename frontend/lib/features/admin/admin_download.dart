// Download di un documento (bytes) nel browser; no-op fuori dal web.
export 'admin_download_stub.dart'
    if (dart.library.js_interop) 'admin_download_web.dart';

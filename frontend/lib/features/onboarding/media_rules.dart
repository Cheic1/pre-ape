/// Regole sui media del rilievo (M5): validazione dei data-URL, cap per foto
/// e cap totale dello stato.  Logica pura e senza dipendenze di piattaforma,
/// così resta testabile anche fuori dal browser (dove il re-encode canvas non
/// esiste, vedi `web_media.dart`).
library;

/// Lato lungo massimo (px) dopo il downscale della foto.
const int kMaxImageSide = 1600;

/// Qualità JPEG del re-encode (~0.82).
const double kJpegQuality = 0.82;

/// Cap per foto (~500 KB) misurato **dopo** l'encode.
const int kMaxPhotoBytes = 500 * 1024;

/// Cap foto aggiuntive in stato (M4).
const int kMaxAdditionalPhotos = 6;

/// Cap totale dello stato foto: margine per 4 slot + 6 aggiuntive.
const int kMaxTotalPhotoBytes = 8 * kMaxPhotoBytes;

/// True se [value] è un data-URL immagine base64 (`data:image/*;base64,...`),
/// l'unico formato accettato come `src` delle immagini nel report e come foto
/// in stato.  Qualsiasi altro prefisso (`data:text/html`, `javascript:`, URL
/// esterni, …) viene rifiutato.
bool isImageDataUrl(String value) {
  final normalized = value.toLowerCase();
  return normalized.startsWith('data:image/') &&
      normalized.contains(';base64,');
}

/// Byte decodificati stimati da un data-URL base64, senza decodificarlo
/// (lunghezza payload base64 × 3/4).
int dataUrlBytes(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) return 0;
  final payload = value.substring(comma + 1).replaceAll('=', '');
  return (payload.length * 3) ~/ 4;
}

/// Valida un data-URL immagine: prefisso `data:image/*;base64,` e dimensione
/// ≤ [kMaxPhotoBytes].  Restituisce il valore valido, oppure null.
String? validateImageDataUrl(String? value) {
  if (value == null) return null;
  if (!isImageDataUrl(value)) return null;
  if (dataUrlBytes(value) > kMaxPhotoBytes) return null;
  return value;
}

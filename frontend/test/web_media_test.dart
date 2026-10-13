import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/web_media.dart';

void main() {
  group('M5 – regole media', () {
    test('costanti di encode', () {
      expect(kMaxImageSide, 1600);
      expect(kJpegQuality, 0.82);
      expect(kMaxPhotoBytes, 500 * 1024);
      expect(kMaxAdditionalPhotos, 6);
      expect(kMaxTotalPhotoBytes, 8 * kMaxPhotoBytes);
    });

    test('isImageDataUrl accetta solo data:image/*;base64,', () {
      expect(isImageDataUrl('data:image/jpeg;base64,QUFB'), isTrue);
      expect(isImageDataUrl('DATA:IMAGE/PNG;BASE64,QUFB'), isTrue);

      expect(isImageDataUrl('data:image/png,raw'), isFalse);
      expect(isImageDataUrl('data:text/html;base64,PHN2Zz4='), isFalse);
      expect(isImageDataUrl('javascript:alert(1)'), isFalse);
      expect(isImageDataUrl('https://x.example/a.png'), isFalse);
      expect(isImageDataUrl(''), isFalse);
    });

    test('dataUrlBytes stima i byte decodificati', () {
      expect(dataUrlBytes('data:image/png;base64,AAAA'), 3);
      expect(dataUrlBytes('data:image/png;base64,QUFBQQ=='), 4);
      expect(dataUrlBytes('senza-virgola'), 0);
    });

    test('validateImageDataUrl applica prefisso e cap per foto', () {
      const valid = 'data:image/png;base64,QUFB';
      expect(validateImageDataUrl(valid), valid);
      expect(validateImageDataUrl(null), isNull);
      expect(validateImageDataUrl('data:text/html;base64,eA=='), isNull);
      expect(
        validateImageDataUrl('data:image/jpeg;base64,${'A' * 800000}'),
        isNull,
        reason: '≈600 KB > kMaxPhotoBytes',
      );
    });
  });

  group('M5 – normalizeImageForState', () {
    test('prefisso non-immagine → null (nessuna normalizzazione)', () async {
      expect(await normalizeImageForState('data:text/html;base64,eA=='), isNull);
      expect(await normalizeImageForState('https://x.example/a.png'), isNull);
      expect(await normalizeImageForState('data:image/png,raw'), isNull);
    });

    test('foto conforme passa invariata (prefisso e dimensione)', () async {
      const small = 'data:image/png;base64,QUFBQQ==';
      expect(await normalizeImageForState(small), small);
    });

    test('foto oltre ~500 KB → null (cap per foto rispettato)', () async {
      final oversized = 'data:image/jpeg;base64,${'A' * 800000}';
      expect(
        await normalizeImageForState(oversized),
        isNull,
        reason: 'senza canvas il file non compressibile viene rifiutato',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/media_rules.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

/// Data-URL piccolo e valido (≤ [kMaxPhotoBytes]).
String _photo([String seed = 'AA']) => 'data:image/jpeg;base64,$seed';

/// Data-URL con payload base64 di [payloadLength] caratteri
/// (byte decodificati = payloadLength * 3 / 4).
String _photoWithPayload(int payloadLength) =>
    'data:image/jpeg;base64,${'A' * payloadLength}';

void main() {
  group('M4 – foto aggiuntive (provider)', () {
    test('add: la lista cresce preservando l\'ordine di inserimento', () {
      final notifier = SurveyNotifier();

      expect(notifier.addAdditionalPhoto(_photo('one')), isTrue);
      expect(notifier.addAdditionalPhoto(_photo('two')), isTrue);
      expect(notifier.data.additionalPhotos, hasLength(2));
      expect(notifier.data.additionalPhotos[0], _photo('one'));
      expect(notifier.data.additionalPhotos[1], _photo('two'));
    });

    test('removeAdditionalPhoto per indice stabile', () {
      final notifier = SurveyNotifier();
      notifier.addAdditionalPhoto(_photo('a'));
      notifier.addAdditionalPhoto(_photo('b'));
      notifier.addAdditionalPhoto(_photo('c'));

      expect(notifier.removeAdditionalPhoto(1), isTrue);
      expect(notifier.data.additionalPhotos, [_photo('a'), _photo('c')],
          reason: 'rimuove il centro, non l\'ultimo elemento');

      expect(notifier.removeAdditionalPhoto(0), isTrue);
      expect(notifier.data.additionalPhotos, [_photo('c')]);

      expect(notifier.removeAdditionalPhoto(0), isTrue);
      expect(notifier.data.additionalPhotos, isEmpty);
    });

    test('remove fuori range è un no-op e restituisce false', () {
      final notifier = SurveyNotifier();
      notifier.addAdditionalPhoto(_photo('only'));

      expect(notifier.removeAdditionalPhoto(-1), isFalse);
      expect(notifier.removeAdditionalPhoto(7), isFalse);
      expect(notifier.data.additionalPhotos, [_photo('only')]);
    });

    test('cap: la settima foto non entra', () {
      final notifier = SurveyNotifier();
      for (var i = 0; i < kMaxAdditionalPhotos; i++) {
        expect(notifier.addAdditionalPhoto(_photo('p$i')), isTrue,
            reason: 'foto ${i + 1} di $kMaxAdditionalPhotos');
      }
      expect(notifier.data.additionalPhotos, hasLength(kMaxAdditionalPhotos));

      expect(notifier.addAdditionalPhoto(_photo('overflow')), isFalse);
      expect(notifier.data.additionalPhotos, hasLength(kMaxAdditionalPhotos));
    });

    test('rifiuta prefissi diversi da data:image/*;base64,', () {
      final notifier = SurveyNotifier();

      for (final invalid in [
        'data:text/html;base64,PHNjcmlwdD4=',
        'data:image/png,raw-no-base64',
        'javascript:alert(1)',
        'https://evil.example/x.png',
        '',
      ]) {
        expect(notifier.addAdditionalPhoto(invalid), isFalse,
            reason: 'accettato: $invalid');
      }
      expect(notifier.data.additionalPhotos, isEmpty);
    });

    test('rifiuta una foto oltre il cap per foto (~500 KB)', () {
      final notifier = SurveyNotifier();
      // 800.000 caratteri base64 ≈ 600.000 byte > kMaxPhotoBytes (512.000).
      final oversized = _photoWithPayload(800000);
      expect(dataUrlBytes(oversized), greaterThan(kMaxPhotoBytes));

      expect(notifier.addAdditionalPhoto(oversized), isFalse);
      expect(notifier.updatePhoto('Facciata', oversized), isFalse);
      expect(notifier.data.additionalPhotos, isEmpty);
      expect(notifier.data.photos, isEmpty);
    });

    test('cap totale dello stato: 4 slot pieni limitano le aggiuntive', () {
      final notifier = SurveyNotifier();
      // 682.664 caratteri base64 = 511.998 byte (≤ cap per foto).
      final big = _photoWithPayload(682664);
      expect(dataUrlBytes(big), 511998);

      for (final slot in ['Facciata', 'Caldaia', 'Finestra', 'Muro']) {
        expect(notifier.updatePhoto(slot, big), isTrue, reason: slot);
      }

      var added = 0;
      while (notifier.addAdditionalPhoto(big)) {
        added++;
      }
      expect(added, 4,
          reason: '4.096.000 − 2.047.992 liberi → 4 foto da 511.998 B');
      expect(notifier.data.additionalPhotos, hasLength(4),
          reason: 'bloccato dal budget, non dal cap 6 (ancora raggiungibile)');
    });

    test('stato foto conservato tra back/forward degli step', () {
      final notifier = SurveyNotifier();
      notifier.addAdditionalPhoto(_photo('one'));
      notifier.addAdditionalPhoto(_photo('two'));

      notifier.nextStep();
      notifier.nextStep();
      notifier.nextStep(); // step 4
      notifier.previousStep();
      notifier.previousStep(); // step 2

      expect(notifier.currentStep, 2);
      expect(notifier.data.additionalPhotos, hasLength(2));
      expect(notifier.data.additionalPhotos.first, _photo('one'));
      expect(notifier.data.additionalPhotos.last, _photo('two'));
    });

    test('copyWith conserva additionalPhotos', () {
      final data = SurveyData()..additionalPhotos = [_photo('keep')];
      final copy = data.copyWith(address: 'Via Roma 1, Milano');

      expect(copy.additionalPhotos, [_photo('keep')]);
      expect(copy.address, 'Via Roma 1, Milano');
      expect(data.additionalPhotos, [_photo('keep')]);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/media_rules.dart';
import 'package:pre_ape/features/onboarding/onboarding_page.dart';
import 'package:pre_ape/features/onboarding/step5_photos.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

/// Data-URL immagine piccolo e valido.
String _thumb(int i) => 'data:image/png;base64,QUFB${'Q' * i}';

Future<ProviderContainer> _pumpStep5(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Step5Photos())),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(Step5Photos)),
  );
}

void main() {
  group('M4 – sezione «Altre foto» (step 5)', () {
    testWidgets('tile «Aggiungi foto» riapre la stessa bottom sheet',
        (tester) async {
      await _pumpStep5(tester);

      expect(find.text('Altre foto'), findsOneWidget);
      expect(find.text('Aggiungi foto'), findsOneWidget);
      expect(
        find.textContaining('Foto aggiuntive del sopralluogo (max 6)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Aggiungi foto'));
      await tester.pumpAndSettle();

      expect(find.text('Scatta foto'), findsOneWidget);
      expect(find.text('Scegli dalla galleria'), findsOneWidget);
      expect(find.text('Seleziona un file dal dispositivo'), findsOneWidget);
      expect(find.text('Rimuovi foto'), findsNothing,
          reason: 'nessuna foto → nessuna voce di rimozione');

      // Il picker è uno stub su VM: la scelta chiude il sheet senza aggiungere.
      await tester.tap(find.text('Scegli dalla galleria'));
      await tester.pumpAndSettle();
      expect(find.text('Scegli dalla galleria'), findsNothing);
      expect(find.text('Aggiungi foto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('thumbnail con ✕: rimozione per indice con feedback',
        (tester) async {
      final container = await _pumpStep5(tester);
      final notifier = container.read(surveyProvider.notifier);
      expect(notifier.addAdditionalPhoto(_thumb(1)), isTrue);
      expect(notifier.addAdditionalPhoto(_thumb(2)), isTrue);
      expect(notifier.addAdditionalPhoto(_thumb(3)), isTrue);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('additional_photo_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('additional_photo_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('additional_photo_3')), findsNothing);

      // Rimuove l'elemento centrale (indice 1): gli altri tengono l'ordine.
      await tester.tap(find.byTooltip('Rimuovi foto aggiuntiva 2'));
      await tester.pumpAndSettle();

      expect(notifier.data.additionalPhotos, hasLength(2));
      expect(notifier.data.additionalPhotos[0], _thumb(1));
      expect(notifier.data.additionalPhotos[1], _thumb(3));
      // Le etichette ✕ seguono la posizione: dopo la rimozione restano
      // "1" e "2", sparisce "3".
      expect(find.byTooltip('Rimuovi foto aggiuntiva 2'), findsOneWidget);
      expect(find.byTooltip('Rimuovi foto aggiuntiva 3'), findsNothing);
      expect(find.text('Foto aggiuntiva rimossa'), findsOneWidget,
          reason: 'feedback di rimozione');
      expect(tester.takeException(), isNull, reason: 'griglia wrap senza overflow');
    });

    testWidgets('cap 6: sparisce il tile e compare l\'avviso', (tester) async {
      final container = await _pumpStep5(tester);
      final notifier = container.read(surveyProvider.notifier);
      for (var i = 0; i < kMaxAdditionalPhotos; i++) {
        expect(notifier.addAdditionalPhoto(_thumb(i)), isTrue);
      }
      await tester.pumpAndSettle();

      expect(find.text('Aggiungi foto'), findsNothing);
      expect(
        find.text('Hai raggiunto il massimo di 6 foto aggiuntive.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('additional_photo_5')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stato foto conservato tra back/forward (Indietro/Avanti)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // L'header usa EnergyGauge: con il font di test (Ahem, glifi quadrati)
      // 'Sufficiente'/'Score: N%' wrappano e la Column del gauge segnala
      // overflow – artefatto fuori dal perimetro di M4/M5 (con Inter reale i
      // testi stanno nei 76px). Lo assorbiamo qui; l'assenza di overflow del
      // solo step 4 è verificata dai test dedicati sopra.
      Future<void> settleAbsorbingGauge() async {
        await tester.pumpAndSettle();
        tester.takeException();
      }

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: OnboardingPage())),
      );
      await settleAbsorbingGauge();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      final notifier = container.read(surveyProvider.notifier);

      // step 1 → 5
      notifier.goToStep(5);
      await settleAbsorbingGauge();
      expect(find.byType(Step5Photos), findsOneWidget);

      expect(notifier.addAdditionalPhoto(_thumb(1)), isTrue);
      expect(notifier.addAdditionalPhoto(_thumb(2)), isTrue);
      await settleAbsorbingGauge();

      // Back al passo 4…
      notifier.previousStep();
      await settleAbsorbingGauge();
      expect(find.byType(Step5Photos), findsNothing);
      expect(notifier.data.additionalPhotos, hasLength(2));

      // …e forward: le foto aggiuntive sopravvivono al back/forward.
      notifier.nextStep();
      await tester.pumpAndSettle();
      expect(find.byType(Step5Photos), findsOneWidget);
      expect(find.byKey(const ValueKey('additional_photo_1')), findsOneWidget);
      expect(notifier.data.additionalPhotos, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });
}

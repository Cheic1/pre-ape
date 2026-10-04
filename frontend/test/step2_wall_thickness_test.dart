import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/step2_enclosure.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

/// Caption normativa attesa sotto il selettore (M3) – **mai** DPR 59/2009.
const String kExpectedCaption =
    'Riferimento: D.Lgs. 192/2005, D.M. 26/06/2015 (UNI TS 11300) — '
    'lo spessore è un proxy della trasmittanza U, non definisce la classe APE';

Future<SurveyNotifier> _pumpStep2(
  WidgetTester tester, {
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Step2Enclosure())),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(Step2Enclosure)),
  ).read(surveyProvider);
}

void main() {
  group('M3 – spessore muri (step 2)', () {
    testWidgets('sublabel in cm esatte sotto Sottile/Medio/Spesso',
        (tester) async {
      await _pumpStep2(tester);

      expect(find.text('Sottile'), findsOneWidget);
      expect(find.text('Medio'), findsOneWidget);
      expect(find.text('Spesso'), findsOneWidget);

      expect(find.text('< 30 cm'), findsOneWidget);
      expect(find.text('30 – 40 cm'), findsOneWidget);
      expect(find.text('> 40 cm'), findsOneWidget);

      expect(tester.takeException(), isNull, reason: 'nessun overflow');
    });

    testWidgets('caption normativa presente, DPR 59/2009 mai citato',
        (tester) async {
      await _pumpStep2(tester);

      expect(find.text(kExpectedCaption), findsOneWidget);
      expect(find.textContaining('D.Lgs. 192/2005'), findsOneWidget);
      expect(
        find.textContaining('D.M. 26/06/2015 (UNI TS 11300)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('proxy della trasmittanza U'),
        findsOneWidget,
      );
      expect(find.textContaining('non definisce la classe APE'), findsOneWidget);

      expect(find.textContaining('DPR 59/2009'), findsNothing);
      expect(find.textContaining('59/2009'), findsNothing);
    });

    testWidgets('card telaio/vetro invariate: sublabel solo sulle card muri',
        (tester) async {
      await _pumpStep2(tester);

      for (final label in [
        'Legno',
        'PVC',
        'Alluminio',
        'Singolo',
        'Doppio',
        'Triplo',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'card $label');
      }

      final cmLabels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((data) => data.endsWith(' cm'))
          .toList();
      expect(cmLabels, hasLength(3),
          reason: 'solo le 3 card muri hanno una sublabel in cm');

      expect(tester.takeException(), isNull, reason: 'nessun overflow');
    });

    testWidgets('semanticLabel distinti per label e sublabel', (tester) async {
      // Il handle va creato prima del pump e disposto esplicitamente a fine
      // test (addTearDown girerebbe dopo la verifica di flutter_test).
      final semantics = tester.ensureSemantics();
      await _pumpStep2(tester);

      expect(find.bySemanticsLabel('Opzione Sottile'), findsOneWidget);
      expect(find.bySemanticsLabel('Opzione Medio'), findsOneWidget);
      expect(find.bySemanticsLabel('Opzione Spesso'), findsOneWidget);
      expect(find.bySemanticsLabel('Intervallo < 30 cm'), findsOneWidget);
      expect(find.bySemanticsLabel('Intervallo 30 – 40 cm'), findsOneWidget);
      expect(find.bySemanticsLabel('Intervallo > 40 cm'), findsOneWidget);

      final card = tester.getSemantics(find.bySemanticsLabel('Opzione Medio'));
      final range =
          tester.getSemantics(find.bySemanticsLabel('Intervallo 30 – 40 cm'));
      expect(identical(card, range), isFalse,
          reason: 'label e sublabel devono restare nodi distinti');
      expect(card.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'la card resta attivabile dallo screen reader');
      semantics.dispose();
    });

    testWidgets('tap su Medio seleziona; nessun overflow a 412px',
        (tester) async {
      final notifier =
          await _pumpStep2(tester, size: const Size(412, 1600));
      expect(notifier.data.wallThickness, isNull);

      await tester.tap(find.text('Medio'));
      await tester.pumpAndSettle();

      expect(notifier.data.wallThickness, '30-40cm',
          reason: 'il valore grezzo resta solo nello stato/scoring');
      expect(tester.takeException(), isNull, reason: 'nessun overflow a 412px');
    });
  });
}

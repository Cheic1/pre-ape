/// Passi del wizard energetico: input `building`, sezioni condizionali,
/// pagina risultati.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pre_ape/features/onboarding/onboarding_page.dart';
import 'package:pre_ape/features/onboarding/step2_building.dart';
import 'package:pre_ape/features/onboarding/step3_envelope.dart';
import 'package:pre_ape/features/onboarding/step4_systems.dart';
import 'package:pre_ape/features/onboarding/step6_results.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/energy.dart';
import 'package:pre_ape/models/survey.dart';

Future<SurveyNotifier> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(412, 3000), bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  settle ? await tester.pumpAndSettle() : await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)))
      .read(surveyProvider);
}

final _result = EnergyResult.fromJson({
  'classe': 'F',
  'punteggio': 12.0,
  'rapporto_ep': 3.0,
  'metodo': 'Stima preliminare',
  'clima': {
    'zona': 'E',
    'gradi_giorno': 2404,
    'comune': {'comune': 'Milano', 'provincia': 'MI', 'zona': 'E', 'gradi_giorno': 2404},
  },
  'ep': {'gl_nren': 128.4, 'gl_ren': 5.0, 'h_nd': 71.1, 'h_nren': 108.0, 'w_nren': 20.4},
  'riferimento': {'gl_nren_rif_standard': 42.7},
  'qualita_involucro_invernale': 'bassa',
  'trasmittanze': {'pareti': 1.15, 'copertura': 1.8, 'pavimento': 1.6, 'finestre': 4.73},
  'trasmittanze_limite': {'pareti': 0.26, 'copertura': 0.22, 'pavimento': 0.26, 'finestre': 1.4},
  'geometria': {'pareti_opache': 47.7, 'superfici_finestrate': 10.0},
  'impianto': {'eta_h_globale': 0.73},
  'consumi': [
    {'vettore': 'metano', 'kwh': 9200, 'quantita': 958, 'unita': 'Smc', 'costo_eur': 1104},
    {'vettore': 'elettricita', 'kwh': 270, 'quantita': 270, 'unita': 'kWh', 'costo_eur': 73},
  ],
  'costo_annuo_eur': 1178,
  'co2_kg_anno': 1936,
  'fotovoltaico': {'produzione_kwh': 0, 'autoconsumo_kwh': 0},
  'interventi': [
    {'codice': 'cappotto', 'intervento': 'Isolamento a cappotto delle pareti (12 cm)',
     'classe': 'D', 'riduzione_ep_pct': 45.2, 'risparmio_annuo_eur': 428,
     'investimento_eur': 6200, 'tempo_ritorno_anni': 14.5, 'classi_guadagnate': 2},
    {'codice': 'riqualificazione_globale', 'intervento': 'Riqualificazione completa',
     'classe': 'A3', 'riduzione_ep_pct': 81.1, 'risparmio_annuo_eur': 731,
     'investimento_eur': 25700, 'tempo_ritorno_anni': 35.2, 'classi_guadagnate': 7},
  ],
  'assunzioni': [
    {'campo': 'anno_costruzione', 'descrizione': 'Anno di costruzione', 'valore': 1970},
    {'campo': 'generatore', 'descrizione': 'Generatore di calore', 'valore': 'caldaia'},
  ],
});

void main() {
  testWidgets('involucro: chip imposta e (ritoccato) cancella il dato', (tester) async {
    final n = await _pump(tester, const Step3Envelope());
    await tester.tap(find.byKey(const ValueKey('muratura_pietra')));
    await tester.pump();
    expect(n.data.building['muratura'], 'pietra');
    expect(n.dirty, isTrue);
    await tester.tap(find.byKey(const ValueKey('muratura_pietra')));
    await tester.pump();
    expect(n.data.building.containsKey('muratura'), isFalse);

    await tester.tap(find.byKey(const ValueKey('isolamento_pareti_cm_10')));
    await tester.pump();
    expect(n.data.building['isolamento_pareti_cm'], 10);
  });

  testWidgets('involucro: copertura solo per ultimo piano, pavimento per piano terra',
      (tester) async {
    final n = await _pump(tester, const Step3Envelope());
    expect(find.text('Copertura'), findsNothing);
    expect(find.text('Pavimento'), findsNothing);
    n.setBuilding('piano', 'ultimo');
    await tester.pumpAndSettle();
    expect(find.text('Copertura'), findsOneWidget);
    n.setBuilding('tipologia', 'villetta');
    await tester.pumpAndSettle();
    expect(find.text('Copertura'), findsOneWidget);
    expect(find.text('Pavimento'), findsOneWidget);
    expect(find.textContaining('AR'), findsNothing);
  });

  testWidgets('edificio: piano per appartamento, piani riscaldati per villetta',
      (tester) async {
    final n = await _pump(tester, const Step2Building());
    expect(find.text('Posizione dell\'alloggio'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tipologia_villetta')));
    await tester.pumpAndSettle();
    expect(n.data.building['tipologia'], 'villetta');
    expect(find.text('Piani riscaldati'), findsOneWidget);
    expect(find.text('Posizione dell\'alloggio'), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('num_anno_costruzione')), '1968');
    await tester.pump();
    expect(n.data.building['anno_costruzione'], 1968);
    await tester.enterText(find.byKey(const ValueKey('num_anno_costruzione')), '');
    await tester.pump();
    expect(n.data.building.containsKey('anno_costruzione'), isFalse);
  });

  testWidgets('impianti: combustibile solo per le caldaie', (tester) async {
    final n = await _pump(tester, const Step4Systems());
    expect(find.text('Combustibile'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('generatore_pompa_calore_aria_acqua')));
    await tester.pumpAndSettle();
    expect(n.data.building['generatore'], 'pompa_calore_aria_acqua');
    expect(find.text('Combustibile'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('num_fotovoltaico_kwp')), '4,5');
    await tester.pump();
    expect(n.data.building['fotovoltaico_kwp'], 4.5);
  });

  testWidgets('risultati: classe, dati da rilevare, interventi; nessun overflow su telefono',
      (tester) async {
    final n = await _pump(tester, const Step6Results(),
        size: const Size(360, 4000), settle: false); // spinner until the estimate
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    n.loadFrom(SurveyRead(
      id: 's-1',
      status: 'draft',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      energyResult: _result,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result_class')), findsOneWidget);
    expect(find.text('Dati da rilevare (2)'), findsOneWidget);
    expect(find.text('Riqualificazione completa'), findsOneWidget);
    expect(find.textContaining('Milano (MI)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Generatore di calore'));
    await tester.pump();
    expect(n.currentStep, 4);
  });

  testWidgets('wizard: 6 passi raggiungibili dall\'indicatore', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: OnboardingPage())));
    await tester.pumpAndSettle();
    final n = ProviderScope.containerOf(tester.element(find.byType(OnboardingPage)))
        .read(surveyProvider);
    for (final (step, title) in [
      (2, 'Edificio'), (3, 'Involucro'), (4, 'Impianti'), (6, 'Risultati'), (1, 'Dati generali'),
    ]) {
      await tester.tap(find.byKey(ValueKey('step_dot_$step')));
      // step 6 shows a spinner while no estimate is available (not logged in)
      step == 6 ? await tester.pump(const Duration(milliseconds: 300)) : await tester.pumpAndSettle();
      expect(n.currentStep, step);
      expect(find.text(title), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';

/// Step 3 – involucro: pareti, copertura, pavimento, serramenti.
class Step3Envelope extends ConsumerWidget {
  const Step3Envelope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(surveyProvider.select((n) => n.data.building));
    final isFlat = b['tipologia'] == null || b['tipologia'] == 'appartamento';
    final piano = isFlat ? (b['piano'] ?? 'intermedio') : 'unico';
    final roofExposed = piano == 'ultimo' || piano == 'unico';
    final floorExposed = piano == 'terra' || piano == 'unico';
    final area = ref.watch(surveyProvider.select((n) => n.data.squareMeters));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const StepHeader('Involucro', 'Pareti, copertura, pavimento e serramenti'),
        const SectionCard(
          title: 'Pareti esterne',
          icon: Icons.view_agenda_outlined,
          children: [
            ChoiceField(fieldKey: 'muratura', label: 'Tipo di muratura', options: murOpts),
            ChoiceField(
              fieldKey: 'spessore_muri',
              label: 'Spessore muri',
              options: spessoreOpts,
              help: 'Misurabile su davanzali o vani porta',
            ),
            ChoiceField(
              fieldKey: 'isolamento_pareti_cm',
              label: 'Isolamento (cappotto o intercapedine)',
              options: isolamentoOpts,
            ),
          ],
        ),
        if (roofExposed)
          const SectionCard(
            title: 'Copertura',
            icon: Icons.roofing,
            children: [
              ChoiceField(fieldKey: 'copertura', label: 'Sopra l\'alloggio c\'è', options: coperturaOpts),
              ChoiceField(
                fieldKey: 'isolamento_copertura_cm',
                label: 'Isolamento copertura / solaio sottotetto',
                options: isolamentoOpts,
              ),
            ],
          ),
        if (floorExposed)
          const SectionCard(
            title: 'Pavimento',
            icon: Icons.layers_outlined,
            children: [
              ChoiceField(fieldKey: 'pavimento', label: 'Sotto l\'alloggio c\'è', options: pavimentoOpts),
              ChoiceField(
                fieldKey: 'isolamento_pavimento_cm',
                label: 'Isolamento del solaio',
                options: isolamentoOpts,
              ),
            ],
          ),
        SectionCard(
          title: 'Serramenti',
          icon: Icons.window_outlined,
          children: [
            const ChoiceField(fieldKey: 'telaio', label: 'Telaio', options: telaioOpts),
            const ChoiceField(fieldKey: 'vetro', label: 'Vetro', options: vetroOpts),
            NumberField(
              fieldKey: 'superficie_finestrata',
              label: 'Superficie finestrata totale',
              suffix: 'm²',
              max: 2000,
              hint: 'circa ${(area / 8).toStringAsFixed(0)} m² se non misurata',
              help: 'Somma di finestre e portefinestre (luce del vano)',
            ),
          ],
        ),
        const WizardNav(),
      ],
    );
  }
}

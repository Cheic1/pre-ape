import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';

/// Step 4 – impianti: riscaldamento, acqua calda, raffrescamento, rinnovabili.
class Step4Systems extends ConsumerWidget {
  const Step4Systems({super.key});

  static const _local = {'stufa_pellet', 'stufa_legna', 'split_aria_aria', 'radiatori_elettrici'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gen = ref.watch(surveyProvider.select((n) => n.data.building['generatore']));
    final isLocal = _local.contains(gen);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const StepHeader('Impianti', 'Riscaldamento, acqua calda, raffrescamento e rinnovabili'),
        SectionCard(
          title: 'Riscaldamento',
          icon: Icons.local_fire_department_outlined,
          children: [
            const ChoiceField(fieldKey: 'generatore', label: 'Generatore', options: generatoreOpts),
            if (usesFuel(gen))
              const ChoiceField(fieldKey: 'combustibile', label: 'Combustibile', options: combustibileOpts),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: NumberField(
                    fieldKey: 'anno_generatore',
                    label: 'Anno installazione',
                    integer: true,
                    min: 1950,
                    max: 2100,
                    hint: 'da libretto',
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: NumberField(
                    fieldKey: 'potenza_kw',
                    label: 'Potenza',
                    suffix: 'kW',
                    max: 2000,
                    hint: 'da targa',
                  ),
                ),
              ],
            ),
            if (!isLocal)
              const ChoiceField(fieldKey: 'impianto', label: 'Impianto', options: impiantoOpts),
            const ChoiceField(fieldKey: 'terminali', label: 'Terminali di emissione', options: terminaliOpts),
            const ChoiceField(fieldKey: 'regolazione', label: 'Regolazione', options: regolazioneOpts),
          ],
        ),
        const SectionCard(
          title: 'Acqua calda sanitaria',
          icon: Icons.shower_outlined,
          children: [
            ChoiceField(fieldKey: 'acs', label: 'Produzione ACS', options: acsOpts),
            SwitchField(
              fieldKey: 'solare_termico',
              label: 'Solare termico',
              help: 'Pannelli per l\'acqua calda (copertura tipica 50–60%)',
            ),
          ],
        ),
        const SectionCard(
          title: 'Raffrescamento e ventilazione',
          icon: Icons.ac_unit,
          children: [
            ChoiceField(fieldKey: 'raffrescamento', label: 'Climatizzazione estiva', options: raffrescamentoOpts),
            ChoiceField(fieldKey: 'vmc', label: 'Ventilazione', options: vmcOpts),
          ],
        ),
        const SectionCard(
          title: 'Fotovoltaico',
          icon: Icons.solar_power_outlined,
          children: [
            NumberField(
              fieldKey: 'fotovoltaico_kwp',
              label: 'Potenza installata a servizio dell\'unità',
              suffix: 'kWp',
              max: 200,
              hint: '0 se assente',
            ),
          ],
        ),
        const WizardNav(),
      ],
    );
  }
}

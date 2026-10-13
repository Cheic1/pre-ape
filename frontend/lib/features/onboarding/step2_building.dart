import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';

/// Step 2 – tipologia, epoca e geometria dell'unità immobiliare.
class Step2Building extends ConsumerWidget {
  const Step2Building({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipologia = ref.watch(surveyProvider.select((n) => n.data.building['tipologia']));
    final isFlat = tipologia == null || tipologia == 'appartamento';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const StepHeader('Edificio', 'Tipologia, epoca di costruzione e dimensioni'),
        SectionCard(
          title: 'Tipologia',
          icon: Icons.home_outlined,
          children: [
            const ChoiceField(fieldKey: 'tipologia', label: 'Tipo di immobile', options: tipologiaOpts),
            const NumberField(
              fieldKey: 'anno_costruzione',
              label: 'Anno di costruzione',
              integer: true,
              min: 1800,
              max: 2100,
              hint: 'es. 1975',
              help: 'Determina muratura e isolamento tipici dell\'epoca',
            ),
            if (isFlat)
              const ChoiceField(
                fieldKey: 'piano',
                label: 'Posizione dell\'alloggio',
                options: pianoOpts,
                help: 'Ultimo piano = disperde dal tetto; piano terra = dal pavimento',
              )
            else
              const ChoiceField(fieldKey: 'numero_piani', label: 'Piani riscaldati', options: pianiOpts),
          ],
        ),
        SectionCard(
          title: 'Dimensioni',
          icon: Icons.square_foot,
          children: [
            _AreaSlider(),
            const SizedBox(height: AppSpacing.md),
            _HeightSlider(),
          ],
        ),
        const SectionCard(
          title: 'Esposizione',
          icon: Icons.wb_sunny_outlined,
          children: [
            ChoiceField(
              fieldKey: 'lati_esposti',
              label: 'Lati con pareti verso l\'esterno',
              options: latiOpts,
              help: 'Appartamento d\'angolo: 2–3; villetta isolata: 4',
            ),
            ChoiceField(
              fieldKey: 'orientamento',
              label: 'Orientamento prevalente delle finestre',
              options: orientamentoOpts,
            ),
          ],
        ),
        const WizardNav(),
      ],
    );
  }
}

class _AreaSlider extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(surveyProvider.select((n) => n.data.squareMeters));
    final v = value.clamp(20, 400).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: FieldLabel('Superficie utile riscaldata', fieldKey: 'square_meters')),
            _EditableValue(
              key: const ValueKey('area_value'),
              text: '${value.round()} m²',
              title: 'Superficie utile (m²)',
              initial: value.round().toString(),
              onSaved: (x) {
                if (x >= 10 && x <= 100000) ref.read(surveyProvider.notifier).updateSquareMeters(x);
              },
            ),
          ],
        ),
        Slider(
          value: v,
          min: 20,
          max: 400,
          divisions: 76,
          label: '${value.round()} m²',
          onChanged: (x) => ref.read(surveyProvider.notifier).updateSquareMeters(x.roundToDouble()),
        ),
        const Text('Calpestabile, al netto dei muri', style: AppTextStyles.bodySmall),
      ],
    );
  }
}

class _HeightSlider extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(surveyProvider.select((n) => n.data.avgHeight));
    final v = value.clamp(2.2, 4.5).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: FieldLabel('Altezza netta interna', fieldKey: 'avg_height')),
            _EditableValue(
              key: const ValueKey('height_value'),
              text: '${value.toStringAsFixed(2)} m',
              title: 'Altezza media (m)',
              initial: value.toStringAsFixed(2),
              onSaved: (x) {
                if (x >= 1.5 && x <= 20) ref.read(surveyProvider.notifier).updateAvgHeight(x);
              },
            ),
          ],
        ),
        Slider(
          value: v,
          min: 2.2,
          max: 4.5,
          divisions: 46,
          label: '${value.toStringAsFixed(2)} m',
          onChanged: (x) => ref
              .read(surveyProvider.notifier)
              .updateAvgHeight(double.parse(x.toStringAsFixed(2))),
        ),
      ],
    );
  }
}

/// Value shown next to a slider; tap to type it.
class _EditableValue extends StatelessWidget {
  const _EditableValue({
    super.key,
    required this.text,
    required this.title,
    required this.initial,
    required this.onSaved,
  });

  final String text;
  final String title;
  final String initial;
  final ValueChanged<double> onSaved;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        final controller = TextEditingController(text: initial);
        final value = await showDialog<double>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annulla')),
              TextButton(
                onPressed: () => Navigator.of(ctx)
                    .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
                child: const Text('Salva'),
              ),
            ],
          ),
        );
        if (value != null) onSaved(value);
      },
      icon: const Icon(Icons.edit, size: 14),
      label: Text(text, style: AppTextStyles.titleMedium),
    );
  }
}

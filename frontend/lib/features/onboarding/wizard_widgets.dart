/// Building blocks shared by the wizard steps.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/onboarding/energy_options.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';

/// Step title + subtitle.
class StepHeader extends StatelessWidget {
  const StepHeader(this.title, this.subtitle, {super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.headlineLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: AppTextStyles.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Grouped card with a section title.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.icon, required this.children});

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(child: Text(title, style: AppTextStyles.titleMedium)),
          ]),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );
  }
}

/// True when the server filled [key] with a typical value (not surveyed).
bool isAssumed(WidgetRef ref, String key) {
  final result = ref.watch(surveyProvider.select((n) => n.data.result));
  return result?.assunzioni.any((a) => a.campo == key) ?? false;
}

/// Field label with an optional "stimato" pill.
class FieldLabel extends ConsumerWidget {
  const FieldLabel(this.text, {super.key, this.fieldKey, this.help});

  final String text;
  final String? fieldKey;
  final String? help;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assumed = fieldKey != null && isAssumed(ref, fieldKey!);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(text, style: AppTextStyles.labelLarge)),
              if (assumed) ...[
                const SizedBox(width: AppSpacing.sm),
                const _Pill('da rilevare', AppColors.warning),
              ],
            ],
          ),
          if (help != null) ...[
            const SizedBox(height: 2),
            Text(help!, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Single-choice chips bound to a `building` key. Tapping the selected chip
/// clears the answer (back to "da rilevare").
class ChoiceField extends ConsumerWidget {
  const ChoiceField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.options,
    this.help,
  });

  final String fieldKey;
  final String label;
  final List<Opt> options;
  final String? help;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(surveyProvider.select((n) => n.data.building[fieldKey]));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label, fieldKey: fieldKey, help: help),
          ChoiceChips(
            options: options,
            selected: value,
            keyPrefix: fieldKey,
            onSelected: (v) => ref
                .read(surveyProvider.notifier)
                .setBuilding(fieldKey, v == value ? null : v),
          ),
        ],
      ),
    );
  }
}

class ChoiceChips extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.keyPrefix = 'opt',
  });

  final List<Opt> options;
  final Object? selected;
  final ValueChanged<Object> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final o in options)
          _Chip(
            key: ValueKey('${keyPrefix}_${o.value}'),
            option: o,
            selected: o.value == selected,
            onTap: () => onSelected(o.value),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.option, required this.selected, required this.onTap});

  final Opt option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.15)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: 18, color: color),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label,
                        style: TextStyle(
                          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        )),
                    if (option.hint != null)
                      Text(option.hint!, style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numeric input bound to a `building` key (empty = not surveyed).
class NumberField extends ConsumerStatefulWidget {
  const NumberField({
    super.key,
    required this.fieldKey,
    required this.label,
    this.suffix,
    this.hint,
    this.help,
    this.integer = false,
    this.min = 0,
    this.max = 100000,
  });

  final String fieldKey;
  final String label;
  final String? suffix;
  final String? hint;
  final String? help;
  final bool integer;
  final num min;
  final num max;

  @override
  ConsumerState<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends ConsumerState<NumberField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(ref.read(surveyProvider).building(widget.fieldKey)));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(Object? v) {
    if (v == null) return '';
    if (v is double && v == v.roundToDouble()) return v.toInt().toString();
    return '$v'.replaceAll('.', ',');
  }

  void _onChanged(String text) {
    final notifier = ref.read(surveyProvider.notifier);
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) {
      setState(() => _error = null);
      notifier.setBuilding(widget.fieldKey, null);
      return;
    }
    final num? v = widget.integer ? int.tryParse(t) : double.tryParse(t);
    if (v == null || v < widget.min || v > widget.max) {
      setState(() => _error = 'Valore tra ${widget.min} e ${widget.max}');
      return;
    }
    setState(() => _error = null);
    notifier.setBuilding(widget.fieldKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(surveyProvider.select((n) => n.data.building[widget.fieldKey]));
    if (!_focus.hasFocus && _error == null && _controller.text != _format(value)) {
      _controller.text = _format(value);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label, fieldKey: widget.fieldKey, help: widget.help),
          TextField(
            key: ValueKey('num_${widget.fieldKey}'),
            controller: _controller,
            focusNode: _focus,
            onChanged: _onChanged,
            keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(widget.integer ? r'[0-9]' : r'[0-9.,]')),
            ],
            style: AppTextStyles.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixText: widget.suffix,
              errorText: _error,
              filled: true,
              fillColor: AppColors.surfaceElevated,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yes/no switch bound to a boolean `building` key.
class SwitchField extends ConsumerWidget {
  const SwitchField({super.key, required this.fieldKey, required this.label, this.help});

  final String fieldKey;
  final String label;
  final String? help;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(surveyProvider.select((n) => n.data.building[fieldKey])) == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: FieldLabel(label, help: help)),
          Switch(
            key: ValueKey('switch_$fieldKey'),
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => ref.read(surveyProvider.notifier).setBuilding(fieldKey, v),
          ),
        ],
      ),
    );
  }
}

/// Back / next buttons at the bottom of each step.
class WizardNav extends ConsumerWidget {
  const WizardNav({super.key, this.nextLabel = 'Avanti', this.onNext, this.showBack = true});

  final String nextLabel;
  final VoidCallback? onNext;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(surveyProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
      child: Row(
        children: [
          if (showBack) ...[
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('wizard_back'),
                onPressed: notifier.previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: const Text('Indietro'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: FilledButton(
              key: const ValueKey('wizard_next'),
              onPressed: onNext ?? notifier.nextStep,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(nextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

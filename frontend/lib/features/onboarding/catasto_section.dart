/// Step 1 – "Dati catastali": unità immobiliari modificabili e documenti del
/// catasto (visura, planimetria, estratto di mappa) allegati al sopralluogo.
///
/// Dalla visura PDF il server propone le unità (`DocumentMeta.extracted`): il
/// tecnico le vede in anteprima e le applica con "Applica dati della visura".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/survey_save.dart';
import 'package:pre_ape/features/onboarding/wizard_widgets.dart';
import 'package:pre_ape/features/web/web_download_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_download.dart';
import 'package:pre_ape/features/web/web_file_picker_stub.dart'
    if (dart.library.js_interop) 'package:pre_ape/features/web/web_file_picker.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

/// File scelto dall'utente: data-URL base64 + nome originale.
typedef PickedDocument = ({String dataUrl, String name});

/// Selettore di file (iniettabile nei test; default: `<input type=file>`).
typedef DocumentPicker = Future<PickedDocument?> Function();

/// Massimo documenti per sopralluogo (`MAX_DOCUMENTS_PER_SURVEY`).
const int kMaxDocumentsPerSurvey = 10;

String _fmtNum(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString().replaceAll('.', ',');
  }
  return v.toString();
}

/// Numero scritto all'italiana (`1.032,91`) o con il punto decimale (`95.5`).
double? _parseNum(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return double.tryParse(
      t.contains(',') ? t.replaceAll('.', '').replaceAll(',', '.') : t);
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// Messaggio leggibile per gli errori dei documenti.
String describeDocumentError(ApiException e) {
  if (e.statusCode == 0) return 'Server non raggiungibile: riprova più tardi.';
  if (e.statusCode == 413) return 'File troppo grande (massimo 10 MB).';
  if (e.statusCode == 415) {
    return 'Formato non supportato: carica un PDF, JPEG o PNG.';
  }
  if (e.statusCode == 409) {
    return 'Limite di $kMaxDocumentsPerSurvey documenti per sopralluogo raggiunto.';
  }
  if (e.statusCode == 404) return 'Documento o sopralluogo non trovato.';
  return 'Operazione non riuscita (${e.statusCode}): ${e.message}';
}

class CatastoSection extends ConsumerStatefulWidget {
  const CatastoSection({super.key, this.pickFile});

  /// Override del selettore di file (test); null = selettore del browser.
  final DocumentPicker? pickFile;

  @override
  ConsumerState<CatastoSection> createState() => _CatastoSectionState();
}

class _CatastoSectionState extends ConsumerState<CatastoSection> {
  List<DocumentMeta> _docs = const [];
  String? _docsFor;
  bool _loadingDocs = false;
  bool _uploading = false;

  /// Unità proposte dall'ultima visura caricata (anteprima da applicare).
  List<CadastralUnit>? _proposal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocs());
  }

  Future<void> _loadDocs() async {
    final id = ref.read(surveyProvider).data.surveyId;
    if (!mounted || id == null || id == _docsFor) return;
    setState(() {
      _loadingDocs = true;
      _docsFor = id;
    });
    try {
      final docs = await ref.read(apiClientProvider).listDocuments(id);
      if (mounted) setState(() => _docs = docs);
    } on ApiException catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _handleError(ApiException e) async {
    if (!mounted) return;
    if (e is UnauthorizedException) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      await ref.read(authProvider).handleUnauthorized();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(describeDocumentError(e)),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 6),
    ));
  }

  void _info(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: AppColors.primaryDark,
    ));
  }

  Future<void> _upload() async {
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Tipo di documento'),
        children: [
          for (final e in kDocumentKinds.entries)
            SimpleDialogOption(
              key: ValueKey('document_kind_${e.key}'),
              onPressed: () => Navigator.of(ctx).pop(e.key),
              child: Text(e.value, style: AppTextStyles.bodyLarge),
            ),
        ],
      ),
    );
    if (kind == null || !mounted) return;

    final picked = await (widget.pickFile ?? pickDocumentFile)();
    if (picked == null || !mounted) return;
    final comma = picked.dataUrl.indexOf(',');
    if (!picked.dataUrl.startsWith('data:') ||
        comma < 0 ||
        !picked.dataUrl.substring(0, comma).endsWith(';base64')) {
      _info('File non leggibile.');
      return;
    }

    setState(() => _uploading = true);
    try {
      // Il documento si aggancia al sopralluogo: se è nuovo lo salva prima.
      if (ref.read(surveyProvider).data.surveyId == null) {
        final ok = await saveSurvey(context, ref, quiet: true);
        if (!ok || !mounted) return;
      }
      final id = ref.read(surveyProvider).data.surveyId!;
      final meta = await ref.read(apiClientProvider).uploadDocument(
            id,
            kind: kind,
            filename: picked.name.isEmpty ? 'documento' : picked.name,
            contentBase64: picked.dataUrl.substring(comma + 1),
          );
      if (!mounted) return;
      setState(() {
        _docs = [..._docs, meta];
        _docsFor = id;
        final extracted = meta.extracted;
        if (meta.kind == 'visura' && extracted != null) {
          final useful = extracted.where((u) => !u.isEmpty).toList();
          _proposal = useful.isEmpty ? null : useful;
        }
      });
      if (meta.kind == 'visura' &&
          meta.extracted != null &&
          _proposal == null) {
        _info('Nessun dato catastale riconosciuto nella visura: '
            'inseriscili a mano.');
      } else {
        _info('Documento caricato: ${meta.filename}');
      }
    } on ApiException catch (e) {
      await _handleError(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _download(DocumentMeta doc) async {
    try {
      final bytes = await ref.read(apiClientProvider).downloadDocument(doc.id);
      downloadBytesFile(doc.filename, bytes, doc.mimeType);
    } on ApiException catch (e) {
      await _handleError(e);
    }
  }

  Future<void> _delete(DocumentMeta doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminare il documento?'),
        content: Text('"${doc.filename}" verrà eliminato definitivamente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            key: const ValueKey('document_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Elimina', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).deleteDocument(doc.id);
      if (mounted) {
        setState(() => _docs = _docs.where((d) => d.id != doc.id).toList());
      }
    } on ApiException catch (e) {
      await _handleError(e);
    }
  }

  void _applyProposal() {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(surveyProvider.notifier).applyCadastralProposal(_proposal!);
    setState(() => _proposal = null);
    _info('Dati della visura applicati: verificali prima di salvare.');
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(surveyProvider.notifier);
    final units = ref.watch(surveyProvider.select((n) => n.data.cadastral));
    // Survey salvato altrove (es. pulsante Salva): carica i suoi documenti.
    final surveyId = ref.watch(surveyProvider.select((n) => n.data.surveyId));
    if (surveyId != null &&
        surveyId != _docsFor &&
        !_loadingDocs &&
        !_uploading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDocs());
    }

    return SectionCard(
      title: 'Dati catastali',
      icon: Icons.account_balance_outlined,
      children: [
        Text(
          'Identificativi delle unità immobiliari. Carica la visura in PDF '
          'per compilarli automaticamente, poi verificali.',
          style: AppTextStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_proposal != null) _proposalCard(_proposal!),
        for (var i = 0; i < units.length; i++)
          _CadastralUnitCard(
            key: ValueKey('cadastral_unit_$i'),
            index: i,
            unit: units[i],
          ),
        if (units.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Nessuna unità inserita.',
                style: AppTextStyles.bodyMedium
                    .copyWith(fontStyle: FontStyle.italic)),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('cadastral_add'),
              onPressed: units.length >= kMaxCadastralUnits
                  ? null
                  : () => notifier.addCadastralUnit(),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi unità'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('document_upload'),
              onPressed: _uploading || _docs.length >= kMaxDocumentsPerSurvey
                  ? null
                  : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: const Text('Carica documento'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Documenti del catasto', style: AppTextStyles.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        if (_loadingDocs)
          const LinearProgressIndicator(color: AppColors.primary)
        else if (_docs.isEmpty)
          Text('Nessun documento allegato (visura, planimetria, estratto di mappa).',
              style: AppTextStyles.bodySmall)
        else
          for (final d in _docs) _documentRow(d),
      ],
    );
  }

  Widget _proposalCard(List<CadastralUnit> proposal) {
    return Container(
      key: const ValueKey('visura_proposal'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dalla visura: ${proposal.length} '
            '${proposal.length == 1 ? 'unità trovata' : 'unità trovate'}',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final u in proposal)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                [
                  u.label,
                  if (u.categoria != null) 'Cat. ${u.categoria}',
                  if (u.classe != null) 'Cl. ${u.classe}',
                  if (u.consistenza != null) u.consistenza!,
                  if (u.superficieMq != null) '${_fmtNum(u.superficieMq)} m²',
                  if (u.renditaEuro != null)
                    'Rendita € ${u.renditaEuro!.toStringAsFixed(2).replaceAll('.', ',')}',
                  if (u.comune != null) u.comune!,
                ].join(' · '),
                style: AppTextStyles.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilledButton(
                key: const ValueKey('visura_apply'),
                onPressed: _applyProposal,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Applica dati della visura'),
              ),
              TextButton(
                key: const ValueKey('visura_dismiss'),
                onPressed: () => setState(() => _proposal = null),
                child: const Text('Ignora'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _documentRow(DocumentMeta d) {
    final isPdf = d.mimeType == 'application/pdf';
    return Container(
      key: ValueKey('document_${d.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge),
                Text(
                  [
                    d.kindLabel,
                    _fmtSize(d.sizeBytes),
                    _fmtDate(d.createdAt),
                    if (d.uploadedBy != null) d.uploadedBy!.display,
                  ].join(' · '),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('document_download_${d.id}'),
            tooltip: 'Scarica',
            onPressed: () => _download(d),
            icon: const Icon(Icons.download_outlined, color: AppColors.primary),
          ),
          IconButton(
            key: ValueKey('document_delete_${d.id}'),
            tooltip: 'Elimina',
            onPressed: () => _delete(d),
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

/// Editor di una unità catastale (campi del contratto `CadastralUnit`).
class _CadastralUnitCard extends ConsumerWidget {
  const _CadastralUnitCard({super.key, required this.index, required this.unit});

  final int index;
  final CadastralUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(builder: (context, c) {
        const gap = AppSpacing.sm;
        final full = c.maxWidth;
        final half = (full - gap) / 2;
        final third = (full - 2 * gap) / 3;
        final quarter = (full - 3 * gap) / 4;
        Widget f(String key, String label, double width,
                {String? hint, String? suffix}) =>
            SizedBox(
              width: width,
              child: _UnitField(
                index: index,
                fieldKey: key,
                label: label,
                value: unit[key],
                hint: hint,
                suffix: suffix,
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('Unità ${index + 1}',
                    style: AppTextStyles.labelLarge),
              ),
              IconButton(
                key: ValueKey('cadastral_remove_$index'),
                tooltip: 'Rimuovi unità',
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  ref.read(surveyProvider.notifier).removeCadastralUnit(index);
                },
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textMuted, size: 20),
              ),
            ]),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                f('foglio', 'Foglio', third),
                f('particella', 'Particella', third),
                f('subalterno', 'Sub.', third),
                f('sezione_urbana', 'Sezione urbana', third),
                f('categoria', 'Categoria', third, hint: 'A/2'),
                f('classe', 'Classe', third),
                f('consistenza', 'Consistenza', half, hint: '5,5 vani'),
                f('superficie_mq', 'Superficie catastale', half, suffix: 'm²'),
                f('rendita_euro', 'Rendita', half, suffix: '€'),
                f('piano', 'Piano', half),
                f('comune', 'Comune', half),
                f('codice_comune', 'Cod. comune', quarter, hint: 'F205'),
                f('provincia', 'Prov.', quarter, hint: 'MI'),
                f('indirizzo', 'Indirizzo', full),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _UnitField extends ConsumerStatefulWidget {
  const _UnitField({
    required this.index,
    required this.fieldKey,
    required this.label,
    required this.value,
    this.hint,
    this.suffix,
  });

  final int index;
  final String fieldKey;
  final String label;
  final Object? value;
  final String? hint;
  final String? suffix;

  @override
  ConsumerState<_UnitField> createState() => _UnitFieldState();
}

class _UnitFieldState extends ConsumerState<_UnitField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  String? _error;

  bool get _numeric => CadastralUnit.numericKeys.contains(widget.fieldKey);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmtNum(widget.value));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final notifier = ref.read(surveyProvider.notifier);
    final t = text.trim();
    if (!_numeric) {
      setState(() => _error = null);
      notifier.setCadastralField(widget.index, widget.fieldKey,
          widget.fieldKey == 'provincia' ? t.toUpperCase() : t);
      return;
    }
    if (t.isEmpty) {
      setState(() => _error = null);
      notifier.setCadastralField(widget.index, widget.fieldKey, null);
      return;
    }
    final v = _parseNum(t);
    final max = widget.fieldKey == 'superficie_mq' ? 100000 : 10000000;
    if (v == null || v < 0 || v > max) {
      setState(() => _error = 'Valore non valido');
      return;
    }
    setState(() => _error = null);
    notifier.setCadastralField(widget.index, widget.fieldKey, v);
  }

  @override
  Widget build(BuildContext context) {
    // Valori cambiati fuori dal campo (visura applicata, unità rimossa).
    if (!_focus.hasFocus && _error == null) {
      final differs = _numeric
          ? _parseNum(_controller.text) != (widget.value as num?)?.toDouble()
          : _controller.text != _fmtNum(widget.value);
      if (differs) _controller.text = _fmtNum(widget.value);
    }
    final maxLen = CadastralUnit.maxLength[widget.fieldKey];
    return TextField(
      key: ValueKey('cadastral_${widget.index}_${widget.fieldKey}'),
      controller: _controller,
      focusNode: _focus,
      onChanged: _onChanged,
      keyboardType: _numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: [
        if (_numeric) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        if (maxLen != null) LengthLimitingTextInputFormatter(maxLen),
      ],
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        suffixText: widget.suffix,
        errorText: _error,
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

/// Documenti legali (informativa privacy, termini d'uso, DPA) scaricati da
/// `GET /api/v1/legal/{doc}` e resi con un piccolo renderer Markdown
/// (titoli, paragrafi, elenchi, citazioni, tabelle, **grassetto**/*corsivo*):
/// basta per i testi in `backend/app/legal/` senza dipendenze aggiuntive.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/models/legal.dart';
import 'package:pre_ape/services/api_client.dart';

/// Apre il documento [doc] (`LegalDoc.privacy` | `termini` | `dpa`).
Future<void> openLegalPage(BuildContext context, String doc) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LegalPage(doc: doc)),
  );
}

class LegalPage extends ConsumerStatefulWidget {
  const LegalPage({super.key, required this.doc});

  final String doc;

  @override
  ConsumerState<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends ConsumerState<LegalPage> {
  LegalDocument? _document;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final doc =
          await ref.read(apiClientProvider).getLegalDocument(widget.doc);
      if (mounted) setState(() => _document = doc);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 0
          ? 'Server non raggiungibile. Controlla la connessione.'
          : 'Impossibile caricare il documento (${e.statusCode}).');
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(title: Text(document?.title ?? LegalDoc.label(widget.doc))),
      body: document != null
          ? SelectionArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (!document.complete) const DraftBanner(),
                  ...MarkdownLite.render(document.markdown),
                ],
              ),
            )
          : Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, style: AppTextStyles.bodyMedium),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton(onPressed: _load, child: const Text('Riprova')),
                      ],
                    ),
            ),
    );
  }
}

/// Avviso mostrato finché il gestore non ha completato i dati dei documenti.
class DraftBanner extends StatelessWidget {
  const DraftBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('legal_draft_banner'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Bozza da far verificare a un legale prima della pubblicazione: '
              'alcuni dati del gestore sono ancora da completare.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renderer Markdown minimo per i documenti legali.
class MarkdownLite {
  static final _inline = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');

  static List<Widget> render(String markdown) {
    final widgets = <Widget>[];
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final paragraph = <String>[];
    final table = <List<String>>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      widgets.add(_block(_text(paragraph.join(' '), AppTextStyles.bodyMedium)));
      paragraph.clear();
    }

    void flushTable() {
      if (table.isEmpty) return;
      widgets.add(_table(List.of(table)));
      table.clear();
    }

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('|')) {
        flushParagraph();
        final cells = line
            .substring(1, line.endsWith('|') ? line.length - 1 : line.length)
            .split('|')
            .map((c) => c.trim())
            .toList();
        final isSeparator = cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));
        if (!isSeparator) table.add(cells);
        continue;
      }
      flushTable();
      if (line.trim().isEmpty) {
        flushParagraph();
      } else if (line.startsWith('# ')) {
        flushParagraph();
        widgets.add(_block(_text(line.substring(2), AppTextStyles.headlineMedium),
            top: AppSpacing.sm));
      } else if (line.startsWith('## ')) {
        flushParagraph();
        widgets.add(_block(_text(line.substring(3), AppTextStyles.titleLarge),
            top: AppSpacing.md));
      } else if (line.startsWith('### ')) {
        flushParagraph();
        widgets.add(_block(_text(line.substring(4), AppTextStyles.titleMedium),
            top: AppSpacing.sm));
      } else if (line.startsWith('> ')) {
        flushParagraph();
        widgets.add(_block(Container(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.border, width: 3)),
          ),
          child: _text(line.substring(2), AppTextStyles.bodyMedium),
        )));
      } else if (line.startsWith('- ')) {
        flushParagraph();
        widgets.add(_block(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: AppTextStyles.bodyMedium),
              Expanded(child: _text(line.substring(2), AppTextStyles.bodyMedium)),
            ],
          ),
          bottom: AppSpacing.xs,
          left: AppSpacing.sm,
        ));
      } else {
        paragraph.add(line.trim());
      }
    }
    flushParagraph();
    flushTable();
    return widgets;
  }

  static Widget _block(Widget child,
          {double top = 0, double bottom = AppSpacing.sm, double left = 0}) =>
      Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom, left: left),
        child: child,
      );

  /// Testo con **grassetto** e *corsivo*.
  static Widget _text(String source, TextStyle style) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(source)) {
      if (m.start > last) spans.add(TextSpan(text: source.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700)));
      } else {
        spans.add(TextSpan(
            text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < source.length) spans.add(TextSpan(text: source.substring(last)));
    return Text.rich(TextSpan(
        style: style.copyWith(color: style.color ?? AppColors.textPrimary),
        children: spans));
  }

  static Widget _table(List<List<String>> rows) {
    final columns = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return _block(
      Table(
        border: TableBorder.all(color: AppColors.border),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: i == 0
                  ? const BoxDecoration(color: AppColors.surfaceElevated)
                  : null,
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs + 2),
                    child: _text(
                      c < rows[i].length ? rows[i][c] : '',
                      i == 0
                          ? AppTextStyles.bodySmall
                              .copyWith(fontWeight: FontWeight.w700)
                          : AppTextStyles.bodySmall,
                    ),
                  ),
              ],
            ),
        ],
      ),
      top: AppSpacing.xs,
      bottom: AppSpacing.md,
    );
  }
}

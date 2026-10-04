import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/onboarding_page.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/models/survey.dart';
import 'package:pre_ape/services/api_client.dart';

/// Home dopo il login: elenco dei sopralluoghi del tecnico.
class SurveyListPage extends ConsumerStatefulWidget {
  const SurveyListPage({super.key});

  @override
  ConsumerState<SurveyListPage> createState() => _SurveyListPageState();
}

class _SurveyListPageState extends ConsumerState<SurveyListPage> {
  List<SurveySummary>? _surveys;
  String? _error;
  bool _loading = false;
  bool _opening = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(apiClientProvider).listSurveys();
      if (!mounted) return;
      setState(() => _surveys = rows);
    } on UnauthorizedException {
      await ref.read(authProvider).handleUnauthorized();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.statusCode == 0
          ? 'Server non raggiungibile. Controlla la connessione.'
          : 'Impossibile caricare i sopralluoghi (${e.statusCode}).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWizard() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OnboardingPage()),
    );
    if (mounted) _refresh();
  }

  Future<void> _newSurvey() async {
    ref.read(surveyProvider).startNew();
    await _openWizard();
  }

  Future<void> _openSurvey(SurveySummary row) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final full = await ref.read(apiClientProvider).getSurvey(row.id);
      ref.read(surveyProvider).loadFrom(full);
      if (!mounted) return;
      setState(() => _opening = false);
      await _openWizard();
    } on UnauthorizedException {
      await ref.read(authProvider).handleUnauthorized();
    } on ApiException catch (e) {
      _snack('Impossibile aprire il sopralluogo: ${e.message}', error: true);
    } finally {
      if (mounted && _opening) setState(() => _opening = false);
    }
  }

  Future<void> _deleteSurvey(SurveySummary row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Eliminare il sopralluogo?'),
        content: Text(
          '"${_titleOf(row)}" e tutte le sue foto verranno eliminati '
          'definitivamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiClientProvider).deleteSurvey(row.id);
      _snack('Sopralluogo eliminato');
      _refresh();
    } on UnauthorizedException {
      await ref.read(authProvider).handleUnauthorized();
    } on ApiException catch (e) {
      _snack('Eliminazione non riuscita: ${e.message}', error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.error : AppColors.surfaceElevated,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final rows = _filtered();

    return Scaffold(
      appBar: AppBar(
        title: const Text('I miei sopralluoghi'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            color: AppColors.surface,
            onSelected: (v) {
              if (v == 'logout') ref.read(authProvider).logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  user == null ? '' : '${user.name}\n${user.email}',
                  style: AppTextStyles.bodySmall,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 8),
                  Text('Esci'),
                ]),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('new_survey'),
        onPressed: _newSurvey,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nuovo sopralluogo'),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: _buildBody(rows),
          ),
          if (_opening)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  List<SurveySummary> _filtered() {
    final all = _surveys ?? const <SurveySummary>[];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((s) => [s.title, s.clientName, s.address]
            .whereType<String>()
            .any((v) => v.toLowerCase().contains(q)))
        .toList(growable: false);
  }

  Widget _buildBody(List<SurveySummary> rows) {
    if (_surveys == null && _loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _surveys == null) {
      return _Message(
        icon: Icons.cloud_off,
        title: _error!,
        action: OutlinedButton(onPressed: _refresh, child: const Text('Riprova')),
      );
    }
    if ((_surveys ?? const []).isEmpty) {
      return const _Message(
        icon: Icons.home_work_outlined,
        title: 'Nessun sopralluogo ancora',
        subtitle:
            'Tocca "Nuovo sopralluogo" per raccogliere dati e foto del primo edificio.',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 96),
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Cerca per cliente, pratica o indirizzo',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: Text('Nessun risultato per "$_query"',
                textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
          ),
        for (final row in rows)
          _SurveyCard(
            key: ValueKey('survey_${row.id}'),
            row: row,
            title: _titleOf(row),
            onTap: () => _openSurvey(row),
            onDelete: () => _deleteSurvey(row),
          ),
      ],
    );
  }
}

String _titleOf(SurveySummary s) {
  for (final v in [s.title, s.clientName, s.address]) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return 'Sopralluogo senza titolo';
}

String _formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

class _SurveyCard extends StatelessWidget {
  const _SurveyCard({
    super.key,
    required this.row,
    required this.title,
    required this.onTap,
    required this.onDelete,
  });

  final SurveySummary row;
  final String title;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (row.clientName != null &&
          row.clientName!.isNotEmpty &&
          row.clientName != title)
        row.clientName!,
      if (row.address != null && row.address!.isNotEmpty && row.address != title)
        row.address!,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _ClassBadge(letter: row.estimatedClass),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleLarge),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusChip(completed: row.isCompleted),
                          Text(_formatDate(row.updatedAt),
                              style: AppTextStyles.bodySmall),
                          if (row.photoCount > 0)
                            Text('📷 ${row.photoCount}',
                                style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Elimina',
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.textMuted),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassBadge extends StatelessWidget {
  const _ClassBadge({required this.letter});

  final String? letter;

  static const _colors = <String, Color>{
    'A4': Color(0xFF15803D),
    'A3': Color(0xFF16A34A),
    'A2': Color(0xFF22C55E),
    'A1': Color(0xFF4ADE80),
    'B': Color(0xFF84CC16),
    'C': Color(0xFFEAB308),
    'D': Color(0xFFF59E0B),
    'E': Color(0xFFF97316),
    'F': Color(0xFFEF4444),
    'G': Color(0xFFB91C1C),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[letter] ?? AppColors.border;
    return Tooltip(
      message: 'Classe indicativa (stima preliminare, non APE)',
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color),
        ),
        child: Text(
          letter ?? '–',
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        completed ? 'Completato' : 'Bozza',
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // ListView so RefreshIndicator keeps working on empty/error states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 64, color: AppColors.textMuted),
        const SizedBox(height: AppSpacing.md),
        Text(title,
            textAlign: TextAlign.center, style: AppTextStyles.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(subtitle!,
              textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
        ],
        if (action != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(child: action),
        ],
      ],
    );
  }
}

/// Pannello "Amministrazione": utenti → sopralluoghi → documenti, registro
/// accessi. Ogni chiamata passa da `/api/v1/admin/*` (registrata lato server).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/admin/admin_download.dart';
import 'package:pre_ape/features/admin/admin_models.dart';
import 'package:pre_ape/features/admin/delete_user_dialog.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/onboarding_page.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/features/onboarding/survey_save.dart';
import 'package:pre_ape/models/survey.dart' show SurveySummary;
import 'package:pre_ape/services/admin_api.dart';
import 'package:pre_ape/services/api_client.dart';

/// Client admin condiviso (stessa base URL e JWT di [apiClientProvider]).
final adminApiProvider = Provider<AdminApi>((ref) {
  return AdminApi.from(ref.watch(apiClientProvider));
});

// ── Helpers ─────────────────────────────────────────────────────────────

/// Gestione comune degli errori: 401 → login, 403 → avviso, altro → snack.
Future<void> _handleError(
    BuildContext context, WidgetRef ref, Object error, String what) async {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (error is UnauthorizedException) {
    navigator.popUntil((route) => route.isFirst);
    await ref.read(authProvider).handleUnauthorized();
    return;
  }
  final String text;
  if (error is ForbiddenException) {
    text = 'Accesso riservato agli amministratori.';
  } else if (error is ApiException) {
    text = error.statusCode == 0
        ? 'Server non raggiungibile. Controlla la connessione.'
        : '$what non riuscito: ${error.message}';
  } else {
    text = '$what non riuscito.';
  }
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: AppColors.error,
  ));
}

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: AppColors.surfaceElevated,
  ));
}

/// Dialog di conferma generico per le eliminazioni.
Future<bool> _confirmDelete(
    BuildContext context, String title, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          key: const ValueKey('confirm_delete'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Elimina'),
        ),
      ],
    ),
  );
  return ok == true;
}

String _surveyTitle(SurveySummary s) {
  for (final v in [s.title, s.clientName, s.address]) {
    if (v != null && v.trim().isNotEmpty) return v.trim();
  }
  return 'Sopralluogo senza titolo';
}

/// Apre il sopralluogo di un altro utente nel wizard in modalità admin:
/// lettura da `GET /admin/surveys/{id}`, salvataggio con
/// `PUT /admin/surveys/{id}` (override di [surveySaveApiProvider]).
Future<void> openSurveyAsAdmin(
    BuildContext context, WidgetRef ref, String surveyId) async {
  final admin = ref.read(adminApiProvider);
  final navigator = Navigator.of(context);
  final full = await admin.getSurvey(surveyId);
  ref.read(surveyProvider).loadFrom(full);
  await navigator.push(MaterialPageRoute<void>(
    builder: (_) => ProviderScope(
      overrides: [
        surveySaveApiProvider.overrideWithValue(AdminSurveyClient(admin)),
      ],
      child: const OnboardingPage(),
    ),
  ));
  // il wizard condiviso non deve restare sul sopralluogo di un altro utente
  ref.read(surveyProvider).startNew();
}

/// Lista con caricamento/errore/vuoto e pull-to-refresh.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.items,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.emptyText,
    required this.itemBuilder,
    this.footer,
  });

  final List<T>? items;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final String emptyText;
  final Widget Function(T item) itemBuilder;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final rows = items;
    Widget child;
    if (rows == null && loading) {
      child = const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    } else if (rows == null) {
      child = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(error ?? 'Errore di caricamento',
              textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: OutlinedButton(
                onPressed: onRefresh, child: const Text('Riprova')),
          ),
        ],
      );
    } else {
      child = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: Text(emptyText,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium),
            ),
          for (final r in rows) itemBuilder(r),
          if (footer != null) footer!,
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.title,
    required this.lines,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final List<String> lines;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: AppColors.border),
          ),
          leading: leading,
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleLarge),
          subtitle: lines.isEmpty
              ? null
              : Text(lines.join('\n'), style: AppTextStyles.bodySmall),
          isThreeLine: lines.length > 1,
          trailing: trailing,
          onTap: onTap,
        ),
      ),
    );
  }
}

// ── Utenti ──────────────────────────────────────────────────────────────

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  List<AdminUser>? _users;
  bool _loading = false;
  String? _error;

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
      final rows = await ref.read(adminApiProvider).listUsers();
      if (mounted) setState(() => _users = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossibile caricare gli utenti.');
      if (mounted) await _handleError(context, ref, e, 'Caricamento');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openUser(AdminUser user) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminUserSurveysPage(user: user),
    ));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amministrazione · Utenti'),
        actions: [
          IconButton(
            key: const ValueKey('admin_audit'),
            tooltip: 'Registro accessi',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AdminAuditPage()),
            ),
          ),
        ],
      ),
      body: _AsyncList<AdminUser>(
        items: _users,
        loading: _loading,
        error: _error,
        onRefresh: _refresh,
        emptyText: 'Nessun utente registrato',
        itemBuilder: (u) => _Tile(
          key: ValueKey('admin_user_${u.id}'),
          leading: Icon(
            u.isAdmin ? Icons.admin_panel_settings : Icons.person_outline,
            color: u.isAdmin ? AppColors.primary : AppColors.textMuted,
          ),
          title: u.email,
          lines: [
            [if (u.name.isNotEmpty) u.name, if (u.isAdmin) 'amministratore']
                .join(' · '),
            'Registrato il ${formatAdminDate(u.createdAt)} · '
                'ultimo accesso ${formatAdminDate(u.lastLogin)}',
            '${u.surveyCount} sopralluoghi · ${u.documentCount} documenti',
          ].where((l) => l.isNotEmpty).toList(),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openUser(u),
        ),
      ),
    );
  }
}

// ── Sopralluoghi di un utente ───────────────────────────────────────────

class AdminUserSurveysPage extends ConsumerStatefulWidget {
  const AdminUserSurveysPage({super.key, required this.user});

  final AdminUser user;

  @override
  ConsumerState<AdminUserSurveysPage> createState() =>
      _AdminUserSurveysPageState();
}

class _AdminUserSurveysPageState extends ConsumerState<AdminUserSurveysPage> {
  List<SurveySummary>? _surveys;
  bool _loading = false;
  bool _opening = false;
  String? _error;

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
      final rows =
          await ref.read(adminApiProvider).listUserSurveys(widget.user.id);
      if (mounted) setState(() => _surveys = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossibile caricare i sopralluoghi.');
        await _handleError(context, ref, e, 'Caricamento');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SurveySummary s) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openSurveyAsAdmin(context, ref, s.id);
    } catch (e) {
      if (mounted) await _handleError(context, ref, e, 'Apertura');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (mounted) _refresh();
  }

  Future<void> _delete(SurveySummary s) async {
    final ok = await _confirmDelete(
      context,
      'Eliminare il sopralluogo?',
      '"${_surveyTitle(s)}" di ${widget.user.email} verrà eliminato '
          'definitivamente con foto e documenti.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminApiProvider).deleteSurvey(s.id);
      if (mounted) _snack(context, 'Sopralluogo eliminato');
      _refresh();
    } catch (e) {
      if (mounted) await _handleError(context, ref, e, 'Eliminazione');
    }
  }

  Future<void> _deleteUser() async {
    final user = widget.user;
    if (!await showDeleteUserDialog(context, user.email) || !mounted) return;
    try {
      await ref
          .read(adminApiProvider)
          .deleteUser(user.id, confirmEmail: user.email);
      if (!mounted) return;
      _snack(context, 'Utente ${user.email} eliminato');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) await _handleError(context, ref, e, 'Eliminazione utente');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final isSelf = me != null &&
        (me.id == widget.user.id ||
            me.email.toLowerCase() == widget.user.email.toLowerCase());
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user.email, overflow: TextOverflow.ellipsis),
        actions: [
          if (!isSelf)
            IconButton(
              key: const ValueKey('admin_delete_user'),
              tooltip: 'Elimina utente',
              icon: const Icon(Icons.person_remove_outlined,
                  color: AppColors.error),
              onPressed: _deleteUser,
            ),
        ],
      ),
      body: Stack(
        children: [
          _AsyncList<SurveySummary>(
            items: _surveys,
            loading: _loading,
            error: _error,
            onRefresh: _refresh,
            emptyText: 'Nessun sopralluogo',
            itemBuilder: (s) => _Tile(
              key: ValueKey('admin_survey_${s.id}'),
              title: _surveyTitle(s),
              lines: [
                [
                  s.status == 'completed' ? 'Completato' : 'Bozza',
                  if (s.estimatedClass != null)
                    'classe stimata ${s.estimatedClass}',
                  'agg. ${formatAdminDate(s.updatedAt)}',
                ].join(' · '),
                if (s.address != null && s.address!.isNotEmpty) s.address!,
              ],
              onTap: () => _open(s),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('admin_docs_${s.id}'),
                    tooltip: 'Documenti',
                    icon: const Icon(Icons.folder_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminDocumentsPage(
                          surveyId: s.id,
                          surveyTitle: _surveyTitle(s),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('admin_delete_survey_${s.id}'),
                    tooltip: 'Elimina',
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.textMuted),
                    onPressed: () => _delete(s),
                  ),
                ],
              ),
            ),
          ),
          if (_opening)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
            ),
        ],
      ),
    );
  }
}

// ── Documenti di un sopralluogo ─────────────────────────────────────────

class AdminDocumentsPage extends ConsumerStatefulWidget {
  const AdminDocumentsPage({
    super.key,
    required this.surveyId,
    required this.surveyTitle,
  });

  final String surveyId;
  final String surveyTitle;

  @override
  ConsumerState<AdminDocumentsPage> createState() => _AdminDocumentsPageState();
}

class _AdminDocumentsPageState extends ConsumerState<AdminDocumentsPage> {
  List<DocumentMeta>? _docs;
  bool _loading = false;
  String? _error;

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
      final rows =
          await ref.read(adminApiProvider).listDocuments(widget.surveyId);
      if (mounted) setState(() => _docs = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossibile caricare i documenti.');
        await _handleError(context, ref, e, 'Caricamento');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(DocumentMeta d) async {
    try {
      final file = await ref.read(adminApiProvider).downloadDocument(d.id);
      final started =
          downloadBytes(file.filename ?? d.filename, file.bytes, file.mimeType);
      if (!started && mounted) {
        _snack(context, 'Download disponibile solo dalla versione web.');
      }
    } catch (e) {
      if (mounted) await _handleError(context, ref, e, 'Download');
    }
  }

  Future<void> _delete(DocumentMeta d) async {
    final ok = await _confirmDelete(
      context,
      'Eliminare il documento?',
      '"${d.filename}" verrà eliminato definitivamente.',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminApiProvider).deleteDocument(d.id);
      if (mounted) _snack(context, 'Documento eliminato');
      _refresh();
    } catch (e) {
      if (mounted) await _handleError(context, ref, e, 'Eliminazione');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Documenti · ${widget.surveyTitle}',
            overflow: TextOverflow.ellipsis),
      ),
      body: _AsyncList<DocumentMeta>(
        items: _docs,
        loading: _loading,
        error: _error,
        onRefresh: _refresh,
        emptyText: 'Nessun documento allegato',
        itemBuilder: (d) => _Tile(
          key: ValueKey('admin_doc_${d.id}'),
          leading: Icon(
            d.mimeType == 'application/pdf'
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
            color: AppColors.textMuted,
          ),
          title: d.filename,
          lines: [
            '${d.kindLabel} · ${_size(d.sizeBytes)}',
            'Caricato da ${d.uploadedBy?.email ?? 'utente eliminato'} '
                'il ${formatAdminDate(d.createdAt)}',
          ],
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: ValueKey('admin_download_${d.id}'),
                tooltip: 'Scarica',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _download(d),
              ),
              IconButton(
                key: ValueKey('admin_delete_doc_${d.id}'),
                tooltip: 'Elimina',
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.textMuted),
                onPressed: () => _delete(d),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

// ── Registro accessi ────────────────────────────────────────────────────

class AdminAuditPage extends ConsumerStatefulWidget {
  const AdminAuditPage({super.key, this.pageSize = 50});

  final int pageSize;

  @override
  ConsumerState<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends ConsumerState<AdminAuditPage> {
  List<AuditEntry>? _entries;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final offset = reset ? 0 : (_entries?.length ?? 0);
      final page = await ref
          .read(adminApiProvider)
          .listAudit(limit: widget.pageSize, offset: offset);
      if (!mounted) return;
      setState(() {
        _entries = [if (!reset) ...?_entries, ...page];
        _hasMore = page.length >= widget.pageSize;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Impossibile caricare il registro.');
        await _handleError(context, ref, e, 'Caricamento');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro accessi')),
      body: _AsyncList<AuditEntry>(
        items: _entries,
        loading: _loading,
        error: _error,
        onRefresh: _refresh,
        emptyText: 'Nessuna azione registrata',
        itemBuilder: (e) => _Tile(
          key: ValueKey('audit_${e.id}'),
          title: e.actionLabel,
          lines: [
            '${formatAdminDate(e.createdAt)} · '
                '${e.adminEmail ?? 'amministratore eliminato'}',
            if (e.targetType != null || e.targetId != null)
              [e.targetType, e.targetId].whereType<String>().join(' '),
            if (e.detailText.isNotEmpty) e.detailText,
          ],
        ),
        footer: _hasMore && (_entries?.isNotEmpty ?? false)
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: OutlinedButton(
                    key: const ValueKey('audit_more'),
                    onPressed: _loading ? null : () => _load(reset: false),
                    child: const Text('Carica altri'),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

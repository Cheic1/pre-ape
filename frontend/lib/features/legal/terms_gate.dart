/// Accettazione dei documenti legali dopo il login: se l'utente non ha
/// accettato la versione corrente (`terms_accepted == false`, utenti
/// registrati prima o dopo un aggiornamento dei testi) un dialogo bloccante
/// chiede "Accetto" (POST /auth/accept-terms) oppure "Esci" (logout).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/legal/legal_page.dart';
import 'package:pre_ape/models/legal.dart';

/// Link tappabile a un documento legale.
class LegalLink extends StatelessWidget {
  const LegalLink(this.doc, {super.key, this.label});

  final String doc;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('legal_link_$doc'),
      onTap: () => openLegalPage(context, doc),
      child: Text(
        label ?? LegalDoc.label(doc),
        style: const TextStyle(
          color: AppColors.primaryGlow,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.primaryGlow,
        ),
      ),
    );
  }
}

/// Elenco dei tre documenti (menu "Privacy e termini").
Future<void> showLegalDocumentsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (doc, icon) in const [
            (LegalDoc.privacy, Icons.privacy_tip_outlined),
            (LegalDoc.termini, Icons.gavel_outlined),
            (LegalDoc.dpa, Icons.handshake_outlined),
          ])
            ListTile(
              leading: Icon(icon, color: AppColors.textSecondary),
              title: Text(LegalDoc.label(doc)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                openLegalPage(context, doc);
              },
            ),
        ],
      ),
    ),
  );
}

/// "Ho letto l'Informativa privacy e accetto i Termini d'uso e l'Accordo sul
/// trattamento dei dati" con i tre link.
class LegalConsentText extends StatelessWidget {
  const LegalConsentText({super.key, this.prefix = 'Ho letto l\''});

  final String prefix;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.textSecondary, fontSize: 13);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(prefix, style: style),
        const LegalLink(LegalDoc.privacy, label: 'Informativa privacy'),
        const Text(' e accetto i ', style: style),
        const LegalLink(LegalDoc.termini, label: "Termini d'uso"),
        const Text(' e l\'', style: style),
        const LegalLink(LegalDoc.dpa,
            label: 'Accordo sul trattamento dei dati'),
      ],
    );
  }
}

/// Avvolge la home dopo il login e mostra il dialogo bloccante se serve.
class TermsGate extends ConsumerStatefulWidget {
  const TermsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends ConsumerState<TermsGate> {
  bool _dialogOpen = false;

  void _maybeAsk() {
    final auth = ref.read(authProvider);
    if (_dialogOpen ||
        auth.status != AuthStatus.signedIn ||
        auth.termsAccepted) {
      return;
    }
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _AcceptTermsDialog(),
      );
      _dialogOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authProvider.select((a) => a.termsAccepted));
    _maybeAsk();
    return widget.child;
  }
}

class _AcceptTermsDialog extends ConsumerStatefulWidget {
  const _AcceptTermsDialog();

  @override
  ConsumerState<_AcceptTermsDialog> createState() => _AcceptTermsDialogState();
}

class _AcceptTermsDialogState extends ConsumerState<_AcceptTermsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authProvider);
    final ok = await auth.acceptTerms();
    if (!mounted) return;
    if (ok || auth.status != AuthStatus.signedIn) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = auth.error ?? 'Impossibile registrare l\'accettazione.';
      });
    }
  }

  Future<void> _exit() async {
    final auth = ref.read(authProvider);
    Navigator.of(context).pop();
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('terms_dialog'),
        backgroundColor: AppColors.surface,
        title: const Text('Documenti aggiornati'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Per continuare a usare Pre-APE devi accettare la versione '
                'corrente dei documenti.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              const LegalConsentText(),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('terms_exit'),
            onPressed: _busy ? null : _exit,
            child: const Text('Esci'),
          ),
          FilledButton(
            key: const ValueKey('terms_accept'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _busy ? null : _accept,
            child: const Text('Accetto', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

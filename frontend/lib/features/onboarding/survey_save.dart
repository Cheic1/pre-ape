import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/onboarding/survey_provider.dart';
import 'package:pre_ape/services/api_client.dart';

/// Saves the wizard to the server and reports the outcome with a SnackBar.
///
/// Returns true on success. On an expired session it goes back to the login
/// screen (the wizard route is popped so the AuthGate underneath is visible).
Future<bool> saveSurvey(
  BuildContext context,
  WidgetRef ref, {
  bool complete = false,
  bool quiet = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await ref
        .read(surveyProvider)
        .save(ref.read(apiClientProvider), complete: complete);
    if (!quiet) {
      messenger.showSnackBar(SnackBar(
        content: Text(complete
            ? 'Sopralluogo completato e salvato'
            : 'Bozza salvata'),
        backgroundColor: AppColors.primaryDark,
      ));
    }
    return true;
  } on UnauthorizedException {
    navigator.popUntil((route) => route.isFirst);
    await ref.read(authProvider).handleUnauthorized();
    return false;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(_describe(e)),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 6),
    ));
    return false;
  }
}

String _describe(ApiException e) {
  if (e.statusCode == 0) {
    return 'Server non raggiungibile: i dati restano qui, riprova a salvare '
        'quando torna la connessione.';
  }
  if (e.statusCode == 413) return 'Foto troppo pesanti: rimuovine qualcuna.';
  if (e.statusCode == 422) return 'Dati non validi: ${e.message}';
  return 'Salvataggio non riuscito (${e.statusCode}): ${e.message}';
}

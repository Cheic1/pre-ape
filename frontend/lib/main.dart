import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/theme/app_theme.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';
import 'package:pre_ape/features/auth/login_page.dart';
import 'package:pre_ape/features/surveys/survey_list_page.dart';

void main() {
  runApp(const ProviderScope(child: PreAPEApp()));
}

class PreAPEApp extends StatelessWidget {
  const PreAPEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pre-APE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

/// Login → elenco sopralluoghi; il wizard si apre sopra l'elenco.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider).restore());
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authProvider.select((a) => a.status));
    switch (status) {
      case AuthStatus.restoring:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );
      case AuthStatus.signedOut:
        return const LoginPage();
      case AuthStatus.signedIn:
        return const SurveyListPage();
    }
  }
}

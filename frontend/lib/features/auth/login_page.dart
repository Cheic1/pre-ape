import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/features/auth/auth_provider.dart';

/// Accesso / registrazione del tecnico.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registerMode = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = ref.read(authProvider);
    if (_registerMode) {
      await auth.register(_email.text, _password.text, name: _name.text);
    } else {
      await auth.login(_email.text, _password.text);
    }
  }

  void _toggleMode() {
    ref.read(authProvider).clearError();
    setState(() => _registerMode = !_registerMode);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.energy_savings_leaf,
                          color: AppColors.primary, size: 56),
                      const SizedBox(height: AppSpacing.md),
                      const Text('Pre-APE',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.displayMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Sopralluoghi per la certificazione energetica',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        _registerMode ? 'Crea il tuo account' : 'Accedi',
                        style: AppTextStyles.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_registerMode) ...[
                        TextFormField(
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: _decoration('Nome e cognome (facoltativo)',
                              Icons.person_outline),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      TextFormField(
                        key: const ValueKey('login_email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: _decoration('Email', Icons.mail_outline),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return 'Inserisci la tua email';
                          final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value);
                          return ok ? null : 'Email non valida';
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        key: const ValueKey('login_password'),
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          _registerMode
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) => _submit(),
                        decoration:
                            _decoration('Password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Mostra' : 'Nascondi',
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          final value = v ?? '';
                          if (value.isEmpty) return 'Inserisci la password';
                          if (_registerMode && value.length < 8) {
                            return 'Almeno 8 caratteri';
                          }
                          return null;
                        },
                      ),
                      if (auth.error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            auth.error!,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          key: const ValueKey('login_submit'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          onPressed: auth.busy ? null : _submit,
                          child: auth.busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(
                                  _registerMode ? 'Registrati' : 'Accedi',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white),
                                ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: auth.busy ? null : _toggleMode,
                        child: Text(
                          _registerMode
                              ? 'Hai già un account? Accedi'
                              : 'Non hai un account? Registrati gratis',
                          style: const TextStyle(color: AppColors.primaryGlow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surfaceElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}

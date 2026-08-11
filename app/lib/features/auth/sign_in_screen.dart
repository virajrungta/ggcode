import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_service.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/mesh_background.dart';
import '../../design/tokens.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = ref.read(authServiceProvider);
    try {
      if (_isSignUp) {
        await auth.signUp(_email.text, _password.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      // No navigation here: authStateChanges drives the root widget, so the
      // app switches screens on its own. Popping manually would race it.
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email first, then tap reset.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_email.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MeshBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GGSpacing.l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Centred, not stretched: the parent Column is
                      // CrossAxisAlignment.stretch so the form fields fill the
                      // width, and that was pulling the 68px icon tile into a
                      // full-width green bar.
                      const Center(
                        child: GGIconTile(
                            icon: Icons.eco_rounded, size: 68, iconSize: 32),
                      ),
                      const SizedBox(height: GGSpacing.l),
                      const Text(
                        'GreenGenius',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: GGColors.textPrimary,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: GGSpacing.xs),
                      Text(
                        _isSignUp
                            ? 'Create an account to track your plants'
                            : 'Sign in to your plants',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 14,
                          color: GGColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: GGSpacing.xl),

                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: _decoration('Email', Icons.mail_outline_rounded),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'Enter your email';
                          if (!t.contains('@') || !t.contains('.')) {
                            return 'That does not look like an email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: GGSpacing.m),

                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: [
                          _isSignUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password
                        ],
                        decoration: _decoration(
                          'Password',
                          Icons.lock_outline_rounded,
                          suffix: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Enter your password';
                          // Firebase's own minimum. Enforcing it here gives a
                          // useful message instead of a weak-password error
                          // after a network round trip.
                          if (_isSignUp && v!.length < 6) {
                            return 'Use at least 6 characters';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: GGSpacing.m),
                        Container(
                          padding: const EdgeInsets.all(GGSpacing.m - 2),
                          decoration: BoxDecoration(
                            color: GGColors.badContainer,
                            borderRadius: GGRadius.mAll,
                            border: Border.all(
                                color: GGColors.bad.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 18, color: GGColors.bad),
                              const SizedBox(width: GGSpacing.s + 2),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: GGColors.badText,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: GGSpacing.l),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(_isSignUp ? 'Create account' : 'Sign in'),
                        ),
                      ),

                      const SizedBox(height: GGSpacing.s),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _isSignUp = !_isSignUp;
                                  _error = null;
                                }),
                        child: Text(_isSignUp
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account'),
                      ),
                      if (!_isSignUp)
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Forgot password?'),
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

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: GGColors.surface,
      border: OutlineInputBorder(
        borderRadius: GGRadius.mAll,
        borderSide: const BorderSide(color: GGColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: GGRadius.mAll,
        borderSide: const BorderSide(color: GGColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: GGRadius.mAll,
        borderSide: const BorderSide(color: GGColors.primary, width: 1.6),
      ),
    );
  }
}

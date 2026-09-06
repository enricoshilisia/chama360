import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/biometric_providers.dart';
import '../../../../core/utils/phone_identity.dart';
import '../../../../core/widgets/glass_container.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _usePhone = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authRepositoryProvider);
      if (_usePhone) {
        await auth.signInWithPhone(
          phone: _phoneCtrl.text,
          password: _passwordCtrl.text,
        );
      } else {
        await auth.signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      // Signing in with a password proves identity — no need to also
      // demand biometrics right after. The app-lock screen only kicks in
      // on a later cold start of an already-signed-in session.
      ref.read(isAppUnlockedProvider.notifier).state = true;
      // Navigation happens automatically via the router's auth listener.
    } on AuthException catch (e) {
      // Supabase reports a wrong synthetic-email lookup the same way it
      // reports a wrong password, which would read as nonsense to someone
      // who typed a phone number.
      setState(() => _error = _usePhone && e.message.toLowerCase().contains('credential')
          ? 'That phone number or password isn\'t right'
          : e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    Center(
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        width: 96,
                        height: 96,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Chama360',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage your chama, together.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 32),
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Members get a phone-number login from their
                          // chairperson; chairpersons register with email.
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.email_outlined, size: 18),
                                label: Text('Email'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.phone_outlined, size: 18),
                                label: Text('Phone'),
                              ),
                            ],
                            selected: {_usePhone},
                            onSelectionChanged: (s) => setState(() {
                              _usePhone = s.first;
                              _error = null;
                            }),
                            showSelectedIcon: false,
                          ),
                          const SizedBox(height: 16),
                          if (_usePhone)
                            TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                hintText: '07XX XXX XXX',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (v) => PhoneIdentity.looksLikePhone(v ?? '')
                                  ? null
                                  : 'Enter a valid phone number',
                            )
                          else
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (v) => (v == null || !v.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: _usePhone ? 'Password or PIN' : 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Enter your password or PIN' : null,
                          ),
                          if (!_usePhone)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () async {
                                  if (_emailCtrl.text.trim().isEmpty) return;
                                  await ref
                                      .read(authRepositoryProvider)
                                      .resetPassword(_emailCtrl.text.trim());
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Password reset email sent.')),
                                    );
                                  }
                                },
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          if (_usePhone)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Forgot it? Ask your chairperson to reset your login.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: 4),
                            Text(_error!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center),
                          ],
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Sign In'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // No self-serve signup: an account only comes from a
                    // chama registration being approved, or from a
                    // chairperson creating a login for a member.
                    TextButton(
                      onPressed: () => context.push('/register'),
                      child: const Text('Want to run a chama? Register one'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

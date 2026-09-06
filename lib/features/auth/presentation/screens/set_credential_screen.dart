import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/biometric_providers.dart';
import '../../../../core/utils/credential_validator.dart';
import '../../../../core/widgets/glass_container.dart';
import '../providers/auth_providers.dart';

/// Shown over the whole app when an account still carries the temporary
/// password the chairperson handed out. There is deliberately no way past
/// it other than setting a new credential — a shared temporary password is
/// only safe for as long as it takes to use once.
class SetCredentialScreen extends ConsumerStatefulWidget {
  const SetCredentialScreen({super.key});

  @override
  ConsumerState<SetCredentialScreen> createState() => _SetCredentialScreenState();
}

class _SetCredentialScreenState extends ConsumerState<SetCredentialScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).setNewCredential(_newCtrl.text);
      // The must_change_password flag is cleared as part of that call, which
      // drops this screen automatically. Offer biometrics on the way out —
      // they've just typed a credential, so the pitch lands better here
      // than buried in settings later.
      final supported = await ref.read(biometricServiceProvider).isDeviceSupported();
      final alreadyOn = ref.read(biometricEnabledProvider).value ?? false;
      if (supported && !alreadyOn) {
        ref.read(offerBiometricSetupProvider.notifier).state = true;
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPin = CredentialValidator.looksLikePin(_newCtrl.text);

    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/icon/app_icon.png', width: 72, height: 72),
                    const SizedBox(height: 18),
                    const Text('Set your password',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'You signed in with a temporary password. Choose something only '
                      'you know — either a 4 or 6 digit PIN, or a longer password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, height: 1.4),
                    ),
                    const SizedBox(height: 28),
                    GlassContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _newCtrl,
                            obscureText: _obscure,
                            keyboardType:
                                isPin ? TextInputType.number : TextInputType.visiblePassword,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'New password or PIN',
                              prefixIcon: Icon(isPin ? Icons.pin_outlined : Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: CredentialValidator.validate,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: _obscure,
                            keyboardType:
                                isPin ? TextInputType.number : TextInputType.visiblePassword,
                            decoration: const InputDecoration(
                              labelText: 'Enter it again',
                              prefixIcon: Icon(Icons.check_circle_outline_rounded),
                            ),
                            validator: (v) =>
                                v == _newCtrl.text ? null : 'The two entries don\'t match',
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center),
                          ],
                          const SizedBox(height: 18),
                          ElevatedButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Save and continue'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => ref.read(authRepositoryProvider).signOut(),
                      child: const Text('Sign out instead'),
                    ),
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

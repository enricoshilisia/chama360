import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/biometric_providers.dart';
import '../../../../core/widgets/glass_container.dart';
import '../providers/auth_providers.dart';

/// Shown on top of everything (see app.dart's MaterialApp.builder) whenever
/// there's a valid, already-persisted Supabase session AND the user turned
/// on biometric unlock AND this app launch hasn't been unlocked yet.
///
/// This is deliberately separate from sign-in: "Sign out" in Profile fully
/// clears the session, and biometrics can't bring back a session that no
/// longer exists — nor should they, that would defeat the point of signing
/// out. This screen only ever guards an *existing* session on a fresh
/// app launch, the same way a banking app's PIN/Face ID lock does.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptUnlock());
  }

  Future<void> _attemptUnlock() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ref.read(biometricServiceProvider).authenticate(
          reason: 'Unlock Chama360',
        );
    if (ok && mounted) {
      ref.read(isAppUnlockedProvider.notifier).state = true;
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: GlassContainer(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/icon/app_icon.png', width: 84, height: 84),
                    const SizedBox(height: 20),
                    const Text('Chama360 is locked',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      'Confirm it\'s you to continue',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 28),
                    _checking
                        ? const CircularProgressIndicator()
                        : IconButton.filled(
                            onPressed: _attemptUnlock,
                            iconSize: 32,
                            padding: const EdgeInsets.all(20),
                            icon: const Icon(Icons.fingerprint_rounded),
                          ),
                    const SizedBox(height: 24),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/biometric_providers.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final biometricSupported = ref.watch(biometricSupportedProvider).value ?? false;
    final biometricEnabled = ref.watch(biometricEnabledProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
        children: [
          GlassContainer(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(
                    (user?.email ?? '?').substring(0, 1).toUpperCase(),
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (user?.userMetadata?['full_name'] as String?) ??
                            user?.email ??
                            'Member',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(user?.email ?? '',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Appearance'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).setMode(m!),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('Light'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('Dark'),
                    value: ThemeMode.dark,
                  ),
                  RadioListTile<ThemeMode>(
                    title: Text('System default'),
                    value: ThemeMode.system,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Security'),
          Card(
            child: SwitchListTile(
              title: const Text('Unlock with biometrics'),
              subtitle: Text(
                biometricSupported
                    ? 'Use fingerprint or face unlock for quick sign-in'
                    : 'Not available on this device',
                style: const TextStyle(fontSize: 12),
              ),
              value: biometricEnabled,
              onChanged: biometricSupported
                  ? (v) => ref.read(biometricEnabledProvider.notifier).setEnabled(v)
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          if (biometricSupported && biometricEnabled) ...[
            // With biometrics on, "signing out" locks the app behind
            // Face ID/fingerprint instead of destroying the session — so
            // reopening the app always prompts biometric, never a password
            // form. A full account sign-out is still one tap away below,
            // for switching accounts or turning biometric off for good.
            OutlinedButton.icon(
              onPressed: () => ref.read(isAppUnlockedProvider.notifier).state = false,
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Lock app'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Sign out of account completely',
                  style: TextStyle(color: Colors.red)),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              icon: const Icon(Icons.logout_rounded, color: Colors.red),
              label: const Text('Sign out', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }
}

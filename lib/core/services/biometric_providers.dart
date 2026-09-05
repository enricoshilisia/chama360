import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to a separate "legacy" import in Riverpod 3.x.
import 'package:flutter_riverpod/legacy.dart';

import 'biometric_service.dart';

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Whether the app-lock screen has been passed this launch. Starts false
/// every cold start on purpose — that's what makes it a *lock* screen
/// rather than a one-time setting. Set true either by a successful
/// biometric check (AppLockScreen) or by signing in with a password
/// (LoginScreen), since typing your password already proves identity.
final isAppUnlockedProvider = StateProvider<bool>((ref) => false);

final biometricSupportedProvider = FutureProvider<bool>((ref) {
  return ref.watch(biometricServiceProvider).isDeviceSupported();
});

final biometricEnabledProvider =
    AsyncNotifierProvider<BiometricEnabledNotifier, bool>(
  BiometricEnabledNotifier.new,
);

class BiometricEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(biometricServiceProvider).isEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    final service = ref.read(biometricServiceProvider);
    if (enabled) {
      final ok = await service.authenticate(
        reason: 'Confirm it\'s you to enable biometric sign-in',
      );
      if (!ok) return;
    }
    await service.setEnabled(enabled);
    state = AsyncData(enabled);
  }
}

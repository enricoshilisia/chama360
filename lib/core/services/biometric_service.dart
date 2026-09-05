import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps device biometrics (fingerprint/face) and remembers, per-install,
/// whether the signed-in user opted in to "unlock with biometrics".
///
/// This does NOT replace Supabase auth — it gates access to an already
///-persisted Supabase session on-device. If the user disables it or the
/// device has no biometrics enrolled, they fall back to email/password.
class BiometricService {
  BiometricService()
      : _auth = LocalAuthentication(),
        _storage = const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _enabledKey = 'biometric_unlock_enabled';

  Future<bool> isDeviceSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> isEnabled() async {
    final value = await _storage.read(key: _enabledKey);
    return value == 'true';
  }

  Future<void> setEnabled(bool enabled) {
    return _storage.write(key: _enabledKey, value: enabled.toString());
  }

  /// Prompts the OS biometric sheet. Returns true only on a real success.
  Future<bool> authenticate({
    String reason = 'Unlock Chama360 with your fingerprint or face',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

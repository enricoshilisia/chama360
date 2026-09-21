import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/auth_redirects.dart';
import '../../../core/utils/phone_identity.dart';

/// Wraps Supabase Auth calls. Screens/providers never talk to
/// SupabaseClient directly — they go through repositories like this one,
/// the same separation Django's views/services give you.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// True while the account is still on the temporary password a
  /// chairperson handed out — the app blocks everything else until it's
  /// replaced. Set by the create-member-login Edge Function.
  bool get mustChangeCredential =>
      currentUser?.userMetadata?['must_change_password'] == true;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Members sign in with a phone number rather than an email. Their
  /// account is keyed to a synthetic address derived from that number —
  /// see PhoneIdentity for why, and keep the transform in step with the
  /// create-member-login Edge Function.
  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: PhoneIdentity.syntheticEmail(phone),
      password: password,
    );
  }

  /// Replaces the temporary password and clears the flag that forces the
  /// change screen. Both happen in one call so the app can't end up with a
  /// new password but a stale flag (or the reverse).
  Future<void> setNewCredential(String newCredential) async {
    await _client.auth.updateUser(
      UserAttributes(
        password: newCredential,
        data: {'must_change_password': false},
      ),
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Sends the "forgot password" email.
  ///
  /// Without an explicit redirect this falls back to the project's
  /// site_url, which points at the web build — so an Android user tapping
  /// the link in their inbox was dropped onto a web page instead of back
  /// into the app they started from. Each client now names its own return
  /// address.
  Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? AuthRedirects.web : AuthRedirects.appDeepLink,
    );
  }
}

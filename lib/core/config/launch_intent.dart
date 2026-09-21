/// What the app was opened *for*, read once at startup.
///
/// On web, Supabase consumes the URL fragment during initialisation — the
/// tokens and `type=recovery` are gone from the address bar before the
/// first widget builds. Anything relying purely on the
/// onAuthStateChange event can therefore miss a password recovery that
/// arrived in the very same frame, which left people signed in on the
/// home screen having reset nothing.
///
/// So the fragment is inspected before Supabase touches it, and the answer
/// kept here.
class LaunchIntent {
  LaunchIntent._();

  static bool _isPasswordRecovery = false;

  /// True when this launch came from a password-recovery link.
  static bool get isPasswordRecovery => _isPasswordRecovery;

  /// Call before Supabase initialises, while the fragment is still intact.
  static void captureFromUrl(Uri url) {
    final haystack = '${url.fragment}&${url.query}';
    _isPasswordRecovery = haystack.contains('type=recovery');
  }

  /// Cleared once a new password has actually been set, so a hot restart
  /// doesn't put someone back on the reset screen.
  static void clearPasswordRecovery() => _isPasswordRecovery = false;
}

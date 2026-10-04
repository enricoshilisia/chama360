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
  static String? _linkError;

  /// True when this launch came from a password-recovery link.
  static bool get isPasswordRecovery => _isPasswordRecovery;

  /// Why the link in the email did not work, if it did not.
  ///
  /// An expired or already-used reset link redirects here carrying an
  /// error and no session, which otherwise just shows the sign-in form
  /// with no hint that anything went wrong — and someone who has just
  /// tapped "reset my password" has every reason to think it worked.
  static String? get linkError => _linkError;

  /// Call before Supabase initialises, while the fragment is still intact.
  ///
  /// Two things are looked for, because either on its own has failed.
  /// `type=recovery` is what Supabase adds on the implicit flow and is
  /// absent entirely on PKCE, which hands back only `?code=...`; `mode=reset`
  /// is our own marker on the redirect URL and survives whichever flow is
  /// in play. Finding either is enough.
  static void captureFromUrl(Uri url) {
    final haystack = '${url.fragment}&${url.query}';
    _isPasswordRecovery =
        haystack.contains('type=recovery') || haystack.contains('mode=reset');
    _linkError = _readError(url);
  }

  /// Supabase returns link failures in the fragment, e.g.
  /// `#error=access_denied&error_code=otp_expired&error_description=...`.
  static String? _readError(Uri url) {
    for (final source in [url.fragment, url.query]) {
      if (source.isEmpty || !source.contains('error')) continue;
      final params = Uri.splitQueryString(source);
      final code = params['error_code'];
      final description = params['error_description'];
      if (code == null && description == null) continue;

      // Its own wording for the common case is vague about what to do.
      if (code == 'otp_expired' || code == 'access_denied') {
        return 'That link has expired or has already been used. '
            'Request a new one below.';
      }
      if (description != null && description.isNotEmpty) return description;
      return 'That link did not work. Request a new one below.';
    }
    return null;
  }

  static void clearLinkError() => _linkError = null;

  /// Cleared once a new password has actually been set, so a hot restart
  /// doesn't put someone back on the reset screen.
  static void clearPasswordRecovery() => _isPasswordRecovery = false;
}

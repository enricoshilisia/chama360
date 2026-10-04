/// Where Supabase should send someone back to after they follow an auth
/// link from their inbox.
///
/// These have to match what the project allows (Authentication → URL
/// Configuration); a value that isn't on that list is silently ignored and
/// Supabase falls back to site_url, which is how a phone user ends up on a
/// web page.
class AuthRedirects {
  AuthRedirects._();

  /// Opens the installed Android app. Registered as an intent-filter in
  /// AndroidManifest.xml and as a URL type in Info.plist.
  static const appDeepLink = 'com.enrico.chama360://auth/callback';

  /// The PWA. Also the project's site_url, so it's what anything without
  /// an explicit redirect falls back to.
  static const web = 'https://enricoshilisia.github.io/chama360/';

  /// Where a password-reset link comes back to.
  ///
  /// The marker is ours, not Supabase's. Supabase adds `type=recovery`
  /// itself on the implicit flow, but relying on that alone is what left
  /// people on the dashboard when the flow changed shape underneath us.
  /// A parameter we put there survives regardless of which flow is in
  /// play, and the allow-list already covers this path with its wildcard.
  static const webPasswordReset =
      'https://enricoshilisia.github.io/chama360/?mode=reset';

  static const appPasswordReset = 'com.enrico.chama360://auth/callback?mode=reset';
}

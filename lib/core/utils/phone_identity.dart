/// Members log in with a phone number, but Supabase Auth's phone provider is
/// OTP-only — it can't do "the chairperson set you a temporary password".
/// So each phone-based member gets a real Auth account keyed to a synthetic
/// email derived from their number. It's never a real inbox and never
/// receives mail; it exists so password auth has something to key on.
///
/// The transform must stay identical on both sides — the Edge Function that
/// creates the account and the login screen that signs in — or a member
/// simply can't log in. That's why it lives here rather than being inlined
/// in either place, and why the domain is a constant.
class PhoneIdentity {
  PhoneIdentity._();

  static const domain = 'members.chama360.app';

  /// Kenyan numbers arrive as 0712345678, +254712345678, 254712345678, or
  /// with spaces. They all have to land on the same string.
  static String normalize(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('254')) {
      // already country-coded
    } else if (digits.startsWith('0')) {
      digits = '254${digits.substring(1)}';
    } else if (digits.length == 9) {
      // 712345678 — no leading zero, no country code
      digits = '254$digits';
    }
    return digits;
  }

  static String syntheticEmail(String rawPhone) => '${normalize(rawPhone)}@$domain';

  /// True when this account is phone-based rather than a real email signup —
  /// lets the UI show the member their phone number instead of a synthetic
  /// address they've never seen before.
  static bool isSynthetic(String email) => email.endsWith('@$domain');

  /// Turns the synthetic address back into a displayable number.
  static String phoneFromEmail(String email) {
    if (!isSynthetic(email)) return email;
    return '+${email.split('@').first}';
  }

  static bool looksLikePhone(String raw) {
    final digits = normalize(raw);
    return digits.length == 12 && digits.startsWith('254');
  }
}

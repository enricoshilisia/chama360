import 'package:chama360/core/config/launch_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// Getting this wrong is what left people on the dashboard with the
/// password they came to change still working.
void main() {
  tearDown(() {
    LaunchIntent.clearPasswordRecovery();
    LaunchIntent.clearLinkError();
  });

  test('the implicit flow link, as Supabase returns it', () {
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/'
        '#access_token=eyJhbG&expires_at=1&refresh_token=x&token_type=bearer&type=recovery'));
    expect(LaunchIntent.isPasswordRecovery, isTrue);
  });

  test('the PKCE link, which says nothing about why it was sent', () {
    // Only our own marker identifies this one — there is no type=recovery.
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/?mode=reset&code=abc123'));
    expect(LaunchIntent.isPasswordRecovery, isTrue);
  });

  test('a PKCE link with neither marker is not mistaken for a reset', () {
    LaunchIntent.captureFromUrl(
        Uri.parse('https://enricoshilisia.github.io/chama360/?code=abc123'));
    expect(LaunchIntent.isPasswordRecovery, isFalse);
  });

  test('the native deep link carries the marker too', () {
    LaunchIntent.captureFromUrl(
        Uri.parse('com.enrico.chama360://auth/callback?mode=reset&code=abc'));
    expect(LaunchIntent.isPasswordRecovery, isTrue);
  });

  test('an ordinary launch is not a recovery', () {
    LaunchIntent.captureFromUrl(
        Uri.parse('https://enricoshilisia.github.io/chama360/#/home'));
    expect(LaunchIntent.isPasswordRecovery, isFalse);
  });

  test('an invite link is not a recovery', () {
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/#access_token=x&type=invite'));
    expect(LaunchIntent.isPasswordRecovery, isFalse);
  });

  test('an expired link is explained rather than landing silently', () {
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/?mode=reset'
        '#error=access_denied&error_code=otp_expired'
        '&error_description=Email+link+is+invalid+or+has+expired'));
    expect(LaunchIntent.linkError, contains('expired'));
    expect(LaunchIntent.linkError, contains('Request a new one'));
  });

  test('a working link reports no error', () {
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/?mode=reset#access_token=x&type=recovery'));
    expect(LaunchIntent.linkError, isNull);
  });

  test('it is cleared once a new password has been set', () {
    LaunchIntent.captureFromUrl(Uri.parse(
        'https://enricoshilisia.github.io/chama360/#type=recovery'));
    expect(LaunchIntent.isPasswordRecovery, isTrue);
    LaunchIntent.clearPasswordRecovery();
    expect(LaunchIntent.isPasswordRecovery, isFalse);
  });
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Initializes the Supabase client. Call once in main() after Env.load().
class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> init() {
    return Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      // PKCE on a phone, implicit on the web, and the difference matters
      // for password resets.
      //
      // PKCE keeps a code verifier in the browser that *asked* for the
      // reset, and hands back only `?code=...` with nothing saying what
      // the link was for. On an iPhone the request happens inside the
      // installed PWA while Mail opens the link in Safari — a different
      // store, no verifier — and even where it does exchange, the SDK
      // reports a plain sign-in. The app had no way to know a recovery
      // had happened, so it dropped people on the dashboard still using
      // the password they came to change.
      //
      // The implicit flow returns `#access_token=...&type=recovery`:
      // nothing to carry between browsers, and it says what it is. On
      // native the deep link comes back to the same app that asked, so
      // PKCE is both safe and reliable there.
      authOptions: FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

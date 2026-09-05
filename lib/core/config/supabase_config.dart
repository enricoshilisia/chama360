import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Initializes the Supabase client. Call once in main() after Env.load().
class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> init() {
    return Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}

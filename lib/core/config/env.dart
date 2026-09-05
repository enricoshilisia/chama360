import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Thin wrapper around the loaded .env file.
/// Call `Env.load()` once in main() before anything else touches these.
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty || value.startsWith('YOUR-')) {
      throw StateError(
        'Missing "$key" in .env. Copy .env.example to .env and fill in your '
        'Supabase project URL and anon key (Project Settings -> API).',
      );
    }
    return value;
  }
}

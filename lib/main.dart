import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/launch_intent.dart';
import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  // Before Supabase init: it strips the fragment that says why we were
  // opened, and a recovery link would otherwise go unnoticed.
  LaunchIntent.captureFromUrl(Uri.base);
  await SupabaseConfig.init();
  runApp(const ProviderScope(child: ChamaApp()));
}

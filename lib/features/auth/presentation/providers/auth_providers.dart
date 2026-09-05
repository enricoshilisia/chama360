import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseConfig.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Emits every time Supabase's auth state changes (sign in/out/refresh).
/// The router below listens to this to decide login vs. home.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Convenience: the currently signed-in user, or null.
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider).value;
  return authState?.session?.user ?? SupabaseConfig.client.auth.currentUser;
});

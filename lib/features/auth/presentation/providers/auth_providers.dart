import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/launch_intent.dart';
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

/// True once Supabase reports a password-recovery sign-in, until a new
/// password is actually set.
///
/// A recovery link signs the person in and nothing more — Supabase does
/// not mark the account as needing a new password. Without this the
/// "forgot password" flow quietly dropped people on the home screen,
/// still signed in with the password they had forgotten, having reset
/// nothing.
class PasswordRecoveryNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(authStateChangesProvider, (_, next) {
      if (next.value?.event == AuthChangeEvent.passwordRecovery) {
        state = true;
      }
    });
    // Seeded from the launch URL as well as the event, because on web the
    // event can fire before anything is listening.
    return LaunchIntent.isPasswordRecovery;
  }

  void clear() {
    LaunchIntent.clearPasswordRecovery();
    state = false;
  }
}

final passwordRecoveryProvider =
    NotifierProvider<PasswordRecoveryNotifier, bool>(PasswordRecoveryNotifier.new);

/// Convenience: the currently signed-in user, or null.
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateChangesProvider).value;
  return authState?.session?.user ?? SupabaseConfig.client.auth.currentUser;
});

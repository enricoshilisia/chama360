import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/services/biometric_providers.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/auth/presentation/providers/auth_providers.dart';
import 'features/auth/presentation/screens/app_lock_screen.dart';
import 'features/auth/presentation/screens/biometric_setup_screen.dart';
import 'features/auth/presentation/screens/set_credential_screen.dart';

class ChamaApp extends ConsumerWidget {
  const ChamaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Whenever connectivity flips from offline -> online, flush anything
    // queued locally (e.g. contributions recorded with no signal).
    ref.listen<bool>(isOnlineProvider, (previous, next) {
      if (previous == false && next == true) {
        SyncService(ref.read(supabaseClientProvider)).syncPendingActions();
      }
    });

    return MaterialApp.router(
      title: 'Chama360',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      // Overlays the app-lock screen on top of the whole navigated app
      // rather than folding it into go_router's redirect logic — it reacts
      // to isAppUnlockedProvider directly and doesn't need its own route.
      builder: (context, child) {
        final user = ref.watch(currentUserProvider);
        final loggedIn = user != null;
        final biometricEnabled = ref.watch(biometricEnabledProvider).value ?? false;
        final unlocked = ref.watch(isAppUnlockedProvider);

        if (loggedIn && biometricEnabled && !unlocked) {
          return const AppLockScreen();
        }
        // A member still on the temporary password the chairperson gave
        // them can't go anywhere else until they set their own.
        if (loggedIn && user.userMetadata?['must_change_password'] == true) {
          return const SetCredentialScreen();
        }
        // Offered once, straight after that — skippable.
        if (loggedIn && ref.watch(offerBiometricSetupProvider)) {
          return const BiometricSetupScreen();
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/glass_container.dart';

/// The frame the whole signed-in app sits inside: brand and account above,
/// navigation below, content between. Both bars are frosted strips floating
/// over the gradient backdrop.
///
/// Because the top bar belongs to the shell rather than to each screen,
/// individual screens don't declare their own AppBar for identity — they
/// only add one when they need a title or a back arrow.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onTap,
  });

  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      // Back from a tab root used to drop straight out of the app, leaving
      // the session unlocked behind it. Now it locks first and then leaves,
      // so the next launch starts at the biometric prompt.
      //
      // Not on web: there is no lock there (biometrics are unavailable),
      // and swallowing back would trap people in the PWA with no way out.
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || kIsWeb) return;
        lockApp(ref);
      },
      child: _shell(context),
    );
  }

  Widget _shell(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: const AppTopBar(),
      body: GradientBackdrop(child: child),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
              border: Border(
                top: BorderSide(
                  color: (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black)
                      .withValues(alpha: 0.06),
                ),
              ),
            ),
            child: SafeArea(
              child: NavigationBar(
                height: 64,
                selectedIndex: currentIndex,
                onDestinationSelected: onTap,
                backgroundColor: Colors.transparent,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  // Members, not Chamas: you are inside one chama at a time
                  // now, and switching between them belongs to the account
                  // popup rather than a whole tab.
                  NavigationDestination(
                    icon: Icon(Icons.people_outline_rounded),
                    selectedIcon: Icon(Icons.people_rounded),
                    label: 'Members',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.notifications_outlined),
                    selectedIcon: Icon(Icons.notifications_rounded),
                    label: 'Alerts',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';

import '../widgets/glass_container.dart';

/// Bottom-nav shell wrapping the four main tabs. The nav bar itself is a
/// frosted glass strip floating over the gradient backdrop, matching the
/// rest of the app's glassmorphic language.
class AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
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
                  NavigationDestination(
                    icon: Icon(Icons.groups_outlined),
                    selectedIcon: Icon(Icons.groups_rounded),
                    label: 'Chamas',
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

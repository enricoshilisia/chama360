import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/breakpoints.dart';
import '../services/app_lock.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/glass_container.dart';

/// The frame the whole signed-in app sits inside: brand and account above,
/// navigation below (or beside), content between. Both bars are frosted
/// strips floating over the gradient backdrop.
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

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
    // Members, not Chamas: you are inside one chama at a time now, and
    // switching between them belongs to the account popup, not a whole tab.
    (icon: Icons.people_outline_rounded, selected: Icons.people_rounded, label: 'Members'),
    (
      icon: Icons.notifications_outlined,
      selected: Icons.notifications_rounded,
      label: 'Alerts'
    ),
    (icon: Icons.person_outline_rounded, selected: Icons.person_rounded, label: 'Profile'),
  ];

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= Breakpoints.compact;
          return wide ? _wideShell(context) : _compactShell(context);
        },
      ),
    );
  }

  /// Phone layout: the bottom bar the rest of the app is padded for.
  Widget _compactShell(BuildContext context) {
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
                top: BorderSide(color: _hairline(context)),
              ),
            ),
            child: SafeArea(
              child: NavigationBar(
                height: 64,
                selectedIndex: currentIndex,
                onDestinationSelected: onTap,
                backgroundColor: Colors.transparent,
                destinations: [
                  for (final d in _destinations)
                    NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selected),
                      label: d.label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop layout: navigation on the left where the window is wide, and
  /// the content column held to a readable width in the middle rather than
  /// smeared across the whole screen.
  Widget _wideShell(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(),
      body: GradientBackdrop(
        child: Row(
          children: [
            _SideRail(
              currentIndex: currentIndex,
              onTap: onTap,
              destinations: _destinations,
            ),
            // No width clamp here: each screen decides what to do with the
            // space, because the right answer differs — a report wants a
            // wide table, a form does not.
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  static Color _hairline(BuildContext context) =>
      (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)
          .withValues(alpha: 0.06);
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<({IconData icon, IconData selected, String label})> destinations;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.6),
            border: Border(right: BorderSide(color: AppShell._hairline(context))),
          ),
          child: NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onTap,
            backgroundColor: Colors.transparent,
            // Labels stay visible: a rail of four bare icons makes people
            // hover to find out what they are, every time.
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

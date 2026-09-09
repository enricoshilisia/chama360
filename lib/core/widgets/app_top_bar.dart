import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../theme/app_colors.dart';
import '../utils/display_name.dart';
import 'account_popup.dart';

/// Brand on the left, you on the right — fixed above every tab, the same
/// way the nav bar is fixed below them.
///
/// It lives in the shell rather than in each screen's AppBar so it never
/// slides away mid-navigation: the two bars frame the app, and only the
/// content between them changes.
class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const AppTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = displayNameFor(user);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Image.asset('assets/icon/app_icon.png', width: 30, height: 30),
                    const SizedBox(width: 9),
                    const Text(
                      'Chama360',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    _AvatarButton(name: name),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Account and chama switcher',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => showAccountPopup(context),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.seed, AppColors.seedDark],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.seedDark.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initialsFor(name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

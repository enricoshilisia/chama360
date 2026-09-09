import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/chama/domain/models/chama.dart';
import '../../features/chama/presentation/providers/chama_providers.dart';
import '../../features/chama/presentation/providers/current_chama_provider.dart';
import '../constants/chama_roles.dart';
import '../theme/app_colors.dart';
import '../utils/display_name.dart';

/// The panel behind the avatar in the top bar: who you are, which chama
/// you're in, and — only when there's more than one — a way to switch.
///
/// It grows out of the avatar rather than sliding in from a screen edge, so
/// the connection between what was tapped and what appeared is obvious
/// without needing an arrow drawn between them.
Future<void> showAccountPopup(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Account',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (context, animation, _, _) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned(
            top: MediaQuery.of(context).padding.top + 62,
            right: 12,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
                // Anchored to the avatar it came from, so it reads as
                // unfolding from the tap rather than arriving from nowhere.
                alignment: Alignment.topRight,
                child: const _AccountPanel(),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _AccountPanel extends ConsumerWidget {
  const _AccountPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final name = displayNameFor(user);
    final chamas = ref.watch(myChamasProvider).value ?? const <Chama>[];
    final current = ref.watch(currentChamaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: 288,
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurface : Colors.white)
                  .withValues(alpha: isDark ? 0.92 : 0.97),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.seed, AppColors.seedDark],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initialsFor(name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800),
                            ),
                            if (current != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                ChamaRole.label(current.role),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (chamas.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Text(
                      chamas.length > 1 ? 'YOUR CHAMAS' : 'YOUR CHAMA',
                      style: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                  for (final chama in chamas)
                    _ChamaRow(
                      chama: chama,
                      selected: chama.id == current?.id,
                      onTap: () async {
                        if (chama.id != current?.id) {
                          await ref
                              .read(currentChamaIdProvider.notifier)
                              .select(chama.id);
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                ],
                _Action(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile & settings',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go('/profile');
                  },
                ),
                _Action(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Register another chama',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/register');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChamaRow extends StatelessWidget {
  const _ChamaRow({
    required this.chama,
    required this.selected,
    required this.onTap,
  });

  final Chama chama;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: selected ? 0.18 : 0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.groups_rounded,
                  size: 17, color: selected ? primary : Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chama.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (chama.isPending)
                    Text('Awaiting approval',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange.shade700)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: primary),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 19, color: Colors.grey.shade700),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

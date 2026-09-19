import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved to a separate "legacy" import in Riverpod 3.x.
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/breakpoints.dart';
import '../../../../core/widgets/glass_container.dart';
import '../providers/current_chama_provider.dart';
import 'chama_members_screen.dart';
import 'member_detail_screen.dart';

/// Which member the wide layout is showing beside the list. Only used
/// above the breakpoint — on a phone, tapping a member pushes a route
/// instead, and this stays null.
final _selectedMemberProvider = StateProvider<String?>((ref) => null);

/// The Members tab: the roster of whichever chama you're currently in.
///
/// It resolves the chama itself rather than taking an id, because the tab
/// bar has nowhere to carry one — switching chamas in the account popup is
/// what changes this list.
class MembersTabScreen extends ConsumerWidget {
  const MembersTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chama = ref.watch(currentChamaProvider);

    if (chama == null) {
      return _Empty(
        icon: Icons.groups_outlined,
        title: 'No chama yet',
        message: 'Join one with an invite code, or register your own from your profile.',
        actionLabel: 'Join a chama',
        onAction: () => context.push('/chamas/join'),
      );
    }

    if (chama.isPending) {
      return const _Empty(
        icon: Icons.hourglass_top_rounded,
        title: 'Awaiting approval',
        message: 'Members can be added once this chama has been approved.',
      );
    }

    // On a phone the roster fills the screen and tapping pushes a detail
    // route. With room for both, the detail opens beside the list instead —
    // a chairperson working through members stops losing their place in it.
    if (!Breakpoints.isExpanded(context)) {
      return ChamaMembersScreen(chamaId: chama.id, embedded: true);
    }

    final selected = ref.watch(_selectedMemberProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: ChamaMembersScreen(
            chamaId: chama.id,
            embedded: true,
            selectedMemberId: selected,
            onSelect: (id) => ref.read(_selectedMemberProvider.notifier).state = id,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _Empty(
                  icon: Icons.person_search_outlined,
                  title: 'Pick a member',
                  message: 'Their contributions, loans and history appear here.',
                )
              : MemberDetailScreen(
                  key: ValueKey(selected),
                  chamaId: chama.id,
                  memberId: selected,
                  embedded: true,
                ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassContainer(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 44, color: Colors.grey.shade500),
                const SizedBox(height: 14),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, height: 1.45)),
                if (actionLabel != null) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

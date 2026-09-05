import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/models/chama_member.dart';
import '../providers/chama_providers.dart';

class ChamaMembersScreen extends ConsumerWidget {
  const ChamaMembersScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(chamaMembersProvider(chamaId));
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      floatingActionButton: isAdmin
          ? Padding(
              padding: const EdgeInsets.only(bottom: kFabBottomInset),
              child: FloatingActionButton.extended(
                onPressed: () => context.push('/chamas/$chamaId/members/add'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add member'),
              ),
            )
          : null,
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
          itemCount: members.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final m = members[i];
            final isSelf = m.userId != null && m.userId == myUserId;

            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(m.displayName.substring(0, 1).toUpperCase())),
                title: Text(m.displayName),
                subtitle: Text(
                  ChamaRole.label(m.role) +
                      (isSelf ? ' (you)' : '') +
                      (m.hasAccount ? '' : ' · no app access'),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatMoney(m.balance), style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (isAdmin && !isSelf) _MemberMenu(chamaId: chamaId, member: m),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MemberMenu extends ConsumerWidget {
  const _MemberMenu({required this.chamaId, required this.member});

  final String chamaId;
  final ChamaMember member;

  Future<void> _changeRole(BuildContext context, WidgetRef ref) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change role'),
        children: [
          for (final role in [
            ChamaRole.chairperson,
            ChamaRole.treasurer,
            ChamaRole.secretary,
            ChamaRole.member,
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, role),
              child: Row(
                children: [
                  if (role == member.role)
                    const Icon(Icons.check_rounded, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(ChamaRole.label(role)),
                ],
              ),
            ),
        ],
      ),
    );
    if (newRole == null || newRole == member.role) return;
    await ref.read(chamaRepositoryProvider).updateMemberRole(member.id, newRole);
    ref.invalidate(chamaMembersProvider(chamaId));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member?'),
        content: const Text(
            'They will lose access to this chama. Their contribution and loan history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(chamaRepositoryProvider).removeMember(member.id);
    ref.invalidate(chamaMembersProvider(chamaId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (action) {
        if (action == 'role') _changeRole(context, ref);
        if (action == 'remove') _remove(context, ref);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'role', child: Text('Change role')),
        PopupMenuItem(value: 'remove', child: Text('Remove from chama')),
      ],
    );
  }
}

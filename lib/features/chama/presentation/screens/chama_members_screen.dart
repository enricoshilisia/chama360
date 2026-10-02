import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/models/chama_member.dart';
import '../../../../core/utils/error_message.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../domain/models/archived_member.dart';
import '../providers/chama_providers.dart';

class ChamaMembersScreen extends ConsumerStatefulWidget {
  const ChamaMembersScreen({
    super.key,
    required this.chamaId,
    this.embedded = false,
    this.selectedMemberId,
    this.onSelect,
  });

  final String chamaId;

  /// True when shown as the Members tab, which already sits under the
  /// shell's top bar — a second AppBar there would stack two headers.
  final bool embedded;

  /// Set only in the wide two-pane layout, where the list is a master pane
  /// and the highlighted row is the one shown beside it.
  final String? selectedMemberId;

  /// When provided, tapping selects rather than navigates — the detail is
  /// already on screen next to the list.
  final ValueChanged<String>? onSelect;

  @override
  ConsumerState<ChamaMembersScreen> createState() => _ChamaMembersScreenState();
}

class _ChamaMembersScreenState extends ConsumerState<ChamaMembersScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chamaId = widget.chamaId;
    final embedded = widget.embedded;
    final selectedMemberId = widget.selectedMemberId;
    final onSelect = widget.onSelect;

    final membersAsync = ref.watch(chamaMembersProvider(chamaId));
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);
    final myUserId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      backgroundColor: embedded ? Colors.transparent : null,
      appBar: embedded ? null : AppBar(title: const Text('Members')),
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
        data: (all) {
          // Twenty-odd names is past the point where scrolling to find
          // someone is reasonable, so the list filters as you type.
          final q = _query.trim().toLowerCase();
          final members = q.isEmpty
              ? all
              : all.where((m) => m.displayName.toLowerCase().contains(q)).toList();

          final archivedCount =
              isAdmin ? (ref.watch(archivedMembersProvider(chamaId)).value?.length ?? 0) : 0;

          // The search box sits outside the scroll view, so it stays put
          // while a long roster moves under it — scrolling to the top to
          // change what you are looking for is the thing a search box is
          // meant to save you from.
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search ${all.length} members',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
              if (members.isEmpty)
                Expanded(
                  child: Center(
                    child: Text('No member matches "${_query.trim()}"',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, kShellBottomInset),
                    itemCount: members.length +
                        (isAdmin ? 1 : 0) +
                        (isAdmin && archivedCount > 0 ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      // The archive sits at the foot of the roster: people
                      // who have left are part of the chama's history, not
                      // something to be hidden from it.
                      if (isAdmin &&
                          archivedCount > 0 &&
                          index == members.length + 1) {
                        return _ArchiveShortcut(
                            chamaId: chamaId, count: archivedCount);
                      }
                      // The spreadsheet route belongs where the roster is: a
                      // chairperson putting a chama's history in is looking at this
                      // list when they realise they are not going to type it all one
                      // modal at a time. It scrolls away; the search does not.
                      if (isAdmin && index == 0) {
                        return _SheetsShortcut(chamaId: chamaId);
                      }
                      final m = members[isAdmin ? index - 1 : index];
                      final isSelf = m.isSelf || (m.userId != null && m.userId == myUserId);

                      // A member can only open their own record; everyone else is
                      // just a name on the list to them.
                      final canOpen = isAdmin || m.isSelf;
                      final isSelected = selectedMemberId == m.id;

                      return Card(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
                            : null,
                        child: ListTile(
                          selected: isSelected,
                          onTap: !canOpen
                              ? null
                              : onSelect != null
                                  ? () => onSelect!(m.id)
                                  : () => context.push('/chamas/$chamaId/members/${m.id}'),
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
                              if (m.balance != null)
                                Text(formatMoney(m.balance!),
                                    style: const TextStyle(fontWeight: FontWeight.w600))
                              else if (canOpen)
                                const Icon(Icons.chevron_right_rounded, size: 20),
                              if (isAdmin && !isSelf) _MemberMenu(chamaId: chamaId, member: m),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
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

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(ArchiveReason, String?)>(
      context: context,
      builder: (context) => _ArchiveDialog(member: member),
    );
    if (result == null) return;
    try {
      await ref.read(chamaRepositoryProvider).archiveMember(
            memberId: member.id,
            reason: result.$1,
            note: result.$2,
          );
      ref.invalidate(chamaMembersProvider(chamaId));
      ref.invalidate(archivedMembersProvider(chamaId));
      ref.invalidate(chamaReportProvider(chamaId));
      ref.invalidate(chamaTotalsProvider(chamaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} archived.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'Could not archive that member.'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (action) {
        if (action == 'role') _changeRole(context, ref);
        if (action == 'archive') _archive(context, ref);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'role', child: Text('Change role')),
        PopupMenuItem(value: 'archive', child: Text('Archive member')),
      ],
    );
  }
}

/// Sits at the top of the roster for admins: the way into exporting a
/// workbook of the chama's members and uploading their contribution
/// history back in.
class _SheetsShortcut extends StatelessWidget {
  const _SheetsShortcut({required this.chamaId});

  final String chamaId;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/chamas/$chamaId/sheets'),
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: primary.withValues(alpha: 0.14),
              child: Icon(Icons.table_chart_outlined, size: 18, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contribution sheets',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    'Export a tab per member in Excel, fill in past contributions '
                    'and upload them back',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}


/// Why this member is leaving the roster, from a fixed list.
///
/// Archiving moves nobody's money: if they still hold shares, those stay
/// in their name until somebody transfers them, which is a separate and
/// deliberate act. The dialog says so rather than letting a chairperson
/// find out later.
class _ArchiveDialog extends StatefulWidget {
  const _ArchiveDialog({required this.member});

  final ChamaMember member;

  @override
  State<_ArchiveDialog> createState() => _ArchiveDialogState();
}

class _ArchiveDialogState extends State<_ArchiveDialog> {
  ArchiveReason? _reason;
  final _noteCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = widget.member.balance ?? 0;

    return AlertDialog(
      title: Text('Archive ${widget.member.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'They come off the active roster. Their contributions, loans and '
              'history stay exactly as they are.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ArchiveReason>(
              initialValue: _reason,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: [
                for (final r in ArchiveReason.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (v) => setState(() {
                _reason = v;
                _error = null;
              }),
            ),
            if (_reason != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                autofocus: _reason!.needsNote,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: _reason!.needsNote ? 'What is the reason?' : 'Note (optional)',
                  hintText: _reason!.needsNote
                      ? null
                      : 'Anything the chama should remember',
                ),
              ),
            ],
            if (held > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 17, color: Colors.orange.shade800),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'They still hold ${formatMoney(held)}. Archiving does not move '
                        'it, so the shares stay in their name until someone transfers '
                        'them. You can do that first if you mean to.',
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final reason = _reason;
            final note = _noteCtrl.text.trim();
            if (reason == null) {
              setState(() => _error = 'Choose a reason');
              return;
            }
            if (reason.needsNote && note.isEmpty) {
              setState(() => _error = 'Say what the reason is');
              return;
            }
            Navigator.pop(context, (reason, note.isEmpty ? null : note));
          },
          child: const Text('Archive'),
        ),
      ],
    );
  }
}


/// At the foot of the roster: the people who are no longer on it.
class _ArchiveShortcut extends StatelessWidget {
  const _ArchiveShortcut({required this.chamaId, required this.count});

  final String chamaId;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/chamas/$chamaId/archive'),
        child: GlassContainer(
          padding: const EdgeInsets.all(14),
          borderRadius: 18,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.withValues(alpha: 0.18),
                child: Icon(Icons.inventory_2_outlined,
                    size: 17, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count archived member${count == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/utils/error_message.dart';
import '../../../../core/widgets/content_width.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../domain/models/archived_member.dart';
import '../providers/chama_providers.dart';

/// Everyone who has left the roster, and why.
///
/// Archived members do not disappear — a chama's history includes the
/// people who are no longer in it, and a chairperson asked at a meeting
/// why someone is gone should be able to answer from the record rather
/// than from memory.
class ArchivedMembersScreen extends ConsumerWidget {
  const ArchivedMembersScreen({super.key, required this.chamaId});

  final String chamaId;

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    ArchivedMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Put ${member.displayName} back?'),
        content: const Text(
            'They return to the active roster and the archive reason is cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(chamaRepositoryProvider).restoreMember(member.id);
      ref.invalidate(archivedMembersProvider(chamaId));
      ref.invalidate(chamaMembersProvider(chamaId));
      ref.invalidate(chamaReportProvider(chamaId));
      ref.invalidate(chamaTotalsProvider(chamaId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${member.displayName} is back on the roster.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyError(e,
                fallback: 'Could not restore that member.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedAsync = ref.watch(archivedMembersProvider(chamaId));
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: const Text('Archived members')),
      body: ContentWidth(
        maxWidth: 820,
        child: archivedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(friendlyError(e, fallback: 'Could not load the archive.')),
            ),
          ),
          data: (members) {
            if (members.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Nobody has been archived. Members you take off the roster '
                    'appear here with the reason.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, height: 1.4),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = members[i];
                return GlassContainer(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.grey.withValues(alpha: 0.2),
                            child: Text(m.displayName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(fontSize: 13)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(m.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (m.reason == ArchiveReason.deceased
                                      ? Colors.blueGrey
                                      : Colors.orange)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(m.reasonLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: m.reason == ArchiveReason.deceased
                                      ? Colors.blueGrey.shade700
                                      : Colors.orange.shade800,
                                )),
                          ),
                        ],
                      ),
                      if (m.note != null && m.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(m.note!.trim(),
                            style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (m.archivedAt != null)
                            DateFormat('d MMM yyyy').format(m.archivedAt!),
                          'by ${m.archivedByName}',
                          if (m.archivedBalance != null)
                            'held ${formatMoney(m.archivedBalance!, currency: currency)}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      // Shares do not move when somebody is archived, so a
                      // balance still standing in an archived member's name
                      // is something the chama has to decide about.
                      if (m.stillHoldsShares) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 16, color: Colors.orange.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${formatMoney(m.balance, currency: currency)} still '
                                  'stands in their name. Restore them to transfer it, '
                                  'or leave it where it is.',
                                  style: const TextStyle(fontSize: 11.5, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _restore(context, ref, m),
                          icon: const Icon(Icons.undo_rounded, size: 17),
                          label: const Text('Restore'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

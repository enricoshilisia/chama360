import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../loans/domain/models/loan.dart';
import '../../../loans/presentation/providers/loans_providers.dart';
import '../../domain/models/chama_transaction.dart';
import '../providers/chama_providers.dart';

/// A member's full picture within a chama: who they are, their balance,
/// every contribution/loan movement against their name, and their loan
/// history. Reached from tapping a member in the roster, or a transaction
/// in an activity feed.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({super.key, required this.chamaId, required this.memberId});

  final String chamaId;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(chamaMembersProvider(chamaId));
    final txnsAsync = ref.watch(memberTransactionsProvider((chamaId, memberId)));
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (members) {
          final matches = members.where((m) => m.id == memberId);
          final member = matches.isEmpty ? null : matches.first;
          if (member == null) {
            return const Center(child: Text('Member not found'));
          }

          final memberLoans = (loansAsync.value ?? const <Loan>[])
              .where((l) => l.memberId == memberId)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(memberTransactionsProvider((chamaId, memberId)));
              ref.invalidate(chamaLoansProvider(chamaId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
              children: [
                GlassContainer(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        child: Text(member.displayName.substring(0, 1).toUpperCase()),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(member.displayName,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              ChamaRole.label(member.role) +
                                  (member.hasAccount ? '' : ' · no app access'),
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                            ),
                            if (member.phone != null && member.phone!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(member.phone!,
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(member.balance, currency: currency),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('balance', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (memberLoans.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Loans', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final loan in memberLoans)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => context.push('/chamas/$chamaId/loans/${loan.id}'),
                        title: Text(formatMoney(loan.principal, currency: currency)),
                        subtitle: Text(loan.status.toUpperCase(),
                            style: const TextStyle(fontSize: 11)),
                        trailing: loan.status == 'active'
                            ? Text('owes ${formatMoney(loan.outstanding, currency: currency)}',
                                style: const TextStyle(fontSize: 12))
                            : null,
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                const Text('History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                txnsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Could not load history: $e'),
                  data: (txns) {
                    if (txns.isEmpty) {
                      return Text('No activity yet', style: TextStyle(color: Colors.grey.shade600));
                    }
                    return Column(children: [for (final t in txns) _HistoryTile(t, currency)]);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.txn, this.currency);

  final ChamaTransaction txn;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.type == 'contribution' || txn.type == 'loan_disbursement';
    final icon = switch (txn.type) {
      'contribution' => Icons.savings_rounded,
      'loan_disbursement' => Icons.call_made_rounded,
      'loan_repayment' => Icons.call_received_rounded,
      'penalty' => Icons.warning_amber_rounded,
      _ => Icons.swap_horiz_rounded,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isCredit ? Colors.green : Colors.orange).withValues(alpha: 0.15),
          child: Icon(icon, color: isCredit ? Colors.green : Colors.orange, size: 20),
        ),
        title: Text(txn.type.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        subtitle: Text('${txn.createdAt.toLocal()}'.split(' ').first,
            style: const TextStyle(fontSize: 11.5)),
        trailing: Text(
          '${isCredit ? '+' : '-'}${formatMoney(txn.amount, currency: currency)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isCredit ? Colors.green.shade700 : Colors.orange.shade800,
          ),
        ),
      ),
    );
  }
}

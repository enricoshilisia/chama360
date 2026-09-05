import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/chama_transaction.dart';
import '../providers/chama_providers.dart';
import '../widgets/add_contribution_sheet.dart';

class ChamaDetailScreen extends ConsumerWidget {
  const ChamaDetailScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chamasAsync = ref.watch(myChamasProvider);
    final txnsAsync = ref.watch(chamaTransactionsProvider(chamaId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: 'Loans',
            onPressed: () => context.push('/chamas/$chamaId/loans'),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            tooltip: 'Members',
            onPressed: () => context.push('/chamas/$chamaId/members'),
          ),
        ],
      ),
      body: chamasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chamas) {
          final matches = chamas.where((c) => c.id == chamaId);
          final chama = matches.isEmpty ? null : matches.first;
          if (chama == null) {
            return const Center(child: Text('Chama not found'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myChamasProvider);
              ref.invalidate(chamaTransactionsProvider(chamaId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
              children: [
                Text(chama.name,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                if (chama.description != null) ...[
                  const SizedBox(height: 4),
                  Text(chama.description!,
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 16),
                GlassContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your balance',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(
                        formatMoney(chama.balance, currency: chama.currency),
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Chip(
                            label: Text(chama.role),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('Code: ${chama.inviteCode}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Recent activity',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    TextButton.icon(
                      onPressed: () => showAddContributionSheet(context, chamaId: chamaId),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add contribution'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                txnsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Could not load activity: $e'),
                  data: (txns) {
                    if (txns.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('No transactions yet',
                            style: TextStyle(color: Colors.grey.shade600)),
                      );
                    }
                    return Column(
                      children: [for (final t in txns) _TxnTile(t, chama.currency)],
                    );
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

class _TxnTile extends StatelessWidget {
  const _TxnTile(this.txn, this.currency);

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
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (isCredit ? Colors.green : Colors.orange).withValues(alpha: 0.15),
          child: Icon(icon, color: isCredit ? Colors.green : Colors.orange, size: 20),
        ),
        title: Text(txn.type.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${txn.createdAt.toLocal()}'.split('.').first,
          style: const TextStyle(fontSize: 11.5),
        ),
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

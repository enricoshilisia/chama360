import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/loan.dart';
import '../providers/loans_providers.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);

    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: chama == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: kFabBottomInset),
              child: isAdmin
                  ? FloatingActionButton.extended(
                      onPressed: () => context.push('/chamas/$chamaId/loans/record'),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Record a loan'),
                    )
                  : FloatingActionButton.extended(
                      onPressed: () => context.push(
                        '/chamas/$chamaId/loans/request',
                        extra: chama.memberId,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Request loan'),
                    ),
            ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (loans) {
          final pending = loans.where((l) => l.status == 'pending').toList();
          final rest = loans.where((l) => l.status != 'pending').toList();

          if (loans.isEmpty) {
            return Center(
              child: Text('No loan activity yet',
                  style: TextStyle(color: Colors.grey.shade600)),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(chamaLoansProvider(chamaId)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, kShellBottomInset),
              children: [
                if (pending.isNotEmpty) ...[
                  Text(isAdmin ? 'Pending requests' : 'Your pending requests',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final loan in pending)
                    _LoanCard(loan: loan, chamaId: chamaId, currency: chama?.currency ?? 'KES'),
                  const SizedBox(height: 20),
                ],
                if (rest.isNotEmpty) ...[
                  const Text('History',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final loan in rest)
                    _LoanCard(loan: loan, chamaId: chamaId, currency: chama?.currency ?? 'KES'),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({
    required this.loan,
    required this.chamaId,
    required this.currency,
  });

  final Loan loan;
  final String chamaId;
  final String currency;

  Color _statusColor() {
    switch (loan.status) {
      case 'active':
        return Colors.blue;
      case 'repaid':
        return Colors.green;
      case 'rejected':
      case 'defaulted':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/chamas/$chamaId/loans/${loan.id}'),
        child: GlassContainer(
          borderRadius: 18,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.isMine ? 'You' : (loan.borrowerName ?? 'Member'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(formatMoney(loan.principal, currency: currency),
                        style: const TextStyle(fontSize: 15)),
                    if (loan.purpose != null && loan.purpose!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(loan.purpose!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  loan.status.toUpperCase(),
                  style: TextStyle(
                      color: _statusColor(), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

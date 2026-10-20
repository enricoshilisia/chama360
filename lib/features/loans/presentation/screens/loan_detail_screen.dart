import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/loan.dart';
import '../providers/loans_providers.dart';
import '../widgets/loan_decision.dart';

class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.chamaId, required this.loanId});

  final String chamaId;
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.canViewAll(chama.role);
    // Recording a repayment moves money, so it is the treasurer's.
    final canHandleMoney = chama != null && ChamaRole.canHandleMoney(chama.role);
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: const Text('Loan')),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (loans) {
          final matches = loans.where((l) => l.id == loanId);
          final loan = matches.isEmpty ? null : matches.first;
          if (loan == null) {
            return const Center(child: Text('Loan not found'));
          }
          final repaymentsAsync = ref.watch(loanRepaymentsProvider(loanId));

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(chamaLoansProvider(chamaId));
              ref.invalidate(loanRepaymentsProvider(loanId));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
              children: [
                GlassContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(loan.isMine ? 'You' : (loan.borrowerName ?? 'Member'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          _StatusChip(status: loan.status),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Row('Principal', formatMoney(loan.principal, currency: currency)),
                      // The rate on its own is ambiguous; "5%" and "5% a
                      // month" differ by the length of the loan.
                      _Row('Interest rate', loan.rateLabel),
                      if (loan.interestAmount > 0)
                        _Row('Interest charged',
                            formatMoney(loan.interestAmount, currency: currency)),
                      _Row('Total due', formatMoney(loan.totalDue, currency: currency)),
                      _Row('Repaid', formatMoney(loan.amountRepaid, currency: currency)),
                      _Row('Outstanding', formatMoney(loan.outstanding, currency: currency)),
                      if (loan.dueDate != null)
                        _Row('Due date', '${loan.dueDate!.toLocal()}'.split(' ').first),
                      if (loan.status == 'rejected' && loan.rejectionReason != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Why it was not approved',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.red.shade700)),
                              const SizedBox(height: 4),
                              Text(loan.rejectionReason!,
                                  style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      if (loan.purpose != null && loan.purpose!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Purpose', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(loan.purpose!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isAdmin && (loan.status == 'pending' || loan.status == 'rejected'))
                  LoanDecisionButtons(loan: loan),
                if (loan.status == 'active') _SettleToday(loan: loan),
                if (canHandleMoney && loan.status == 'active') _RecordRepaymentAction(loan: loan),
                const SizedBox(height: 20),
                if (loan.status != 'pending' && loan.status != 'rejected') ...[
                  const Text('Repayments',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  repaymentsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Error: $e'),
                    data: (repayments) {
                      if (repayments.isEmpty) {
                        return Text('No repayments yet',
                            style: TextStyle(color: Colors.grey.shade600));
                      }
                      return Column(
                        children: [
                          for (final r in repayments)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.call_received_rounded, color: Colors.green),
                                title: Text(formatMoney(r.amount, currency: currency)),
                                subtitle: Text('${r.repaidAt.toLocal()}'.split('.').first),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  Color _color() {
    switch (status) {
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
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _RecordRepaymentAction extends ConsumerStatefulWidget {
  const _RecordRepaymentAction({required this.loan});
  final Loan loan;

  @override
  ConsumerState<_RecordRepaymentAction> createState() => _RecordRepaymentActionState();
}

class _RecordRepaymentActionState extends ConsumerState<_RecordRepaymentAction> {
  bool _busy = false;

  Future<void> _record() async {
    // Prefilled with what it takes to clear the loan today, because that
    // is the figure the chairperson is almost always collecting — and
    // because it is less than the scheduled total, which is the whole
    // point of letting people pay early.
    final payoff = ref
        .read(loanPayoffsProvider(widget.loan.chamaId))
        .value
        ?.where((p) => p.loanId == widget.loan.id)
        .firstOrNull;
    final suggested = payoff?.settleToday ?? widget.loan.outstanding;
    final amountCtrl =
        TextEditingController(text: suggested.toStringAsFixed(2));
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record repayment'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            helperText: payoff == null
                ? 'Outstanding: ${formatMoney(widget.loan.outstanding)}'
                : 'Clears the loan today: ${formatMoney(payoff.settleToday)}'
                    '${payoff.saving > 0 ? '  ·  saves ${formatMoney(payoff.saving)}' : ''}',
            helperMaxLines: 2,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(amountCtrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await ref.read(loansRepositoryProvider).recordRepayment(
            loanId: widget.loan.id,
            amount: amount,
          );
      ref.invalidate(chamaLoansProvider(widget.loan.chamaId));
      ref.invalidate(loanPayoffsProvider(widget.loan.chamaId));
      ref.invalidate(loanRepaymentsProvider(widget.loan.id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : _record,
      icon: _busy
          ? const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.add_card_rounded),
      label: const Text('Record repayment'),
    );
  }
}


/// What this loan costs to clear today, and what that saves.
///
/// Interest runs with time, so the figure on the loan is what it costs
/// carried to the deadline — not what it costs now. A member paying in
/// June should not be quoted December's number.
class _SettleToday extends ConsumerWidget {
  const _SettleToday({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payoffs = ref.watch(loanPayoffsProvider(loan.chamaId)).value;
    if (payoffs == null) return const SizedBox.shrink();

    final p = payoffs.where((x) => x.loanId == loan.id).firstOrNull;
    if (p == null || !p.isActive) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: primary),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('Clear it today',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
                Text(formatMoney(p.settleToday),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16, color: primary)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${p.monthsRun} of ${p.monthsScheduled} month'
              '${p.monthsScheduled == 1 ? '' : 's'} have run, so interest so far is '
              '${formatMoney(p.interestSoFar)}.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4),
            ),
            if (p.savesMoney) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Paying now instead of waiting for the deadline saves '
                  '${formatMoney(p.saving)} in interest '
                  '(${formatMoney(p.scheduledTotal)} if carried to term).',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

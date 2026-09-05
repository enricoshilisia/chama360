import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/loan.dart';
import '../providers/loans_providers.dart';

class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.chamaId, required this.loanId});

  final String chamaId;
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);
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
                      _Row('Interest rate', '${loan.interestRate.toStringAsFixed(1)}%'),
                      _Row('Total due', formatMoney(loan.totalDue, currency: currency)),
                      _Row('Repaid', formatMoney(loan.amountRepaid, currency: currency)),
                      _Row('Outstanding', formatMoney(loan.outstanding, currency: currency)),
                      if (loan.dueDate != null)
                        _Row('Due date', '${loan.dueDate!.toLocal()}'.split(' ').first),
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
                if (isAdmin && loan.status == 'pending') _AdminPendingActions(loan: loan),
                if (isAdmin && loan.status == 'active') _RecordRepaymentAction(loan: loan),
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

class _AdminPendingActions extends ConsumerStatefulWidget {
  const _AdminPendingActions({required this.loan});
  final Loan loan;

  @override
  ConsumerState<_AdminPendingActions> createState() => _AdminPendingActionsState();
}

class _AdminPendingActionsState extends ConsumerState<_AdminPendingActions> {
  bool _busy = false;

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await ref.read(loansRepositoryProvider).reject(widget.loan.id);
      ref.invalidate(chamaLoansProvider(widget.loan.chamaId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final result = await showDialog<(double, DateTime?)>(
      context: context,
      builder: (context) => _ApproveDialog(principal: widget.loan.principal),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(loansRepositoryProvider).approveAndDisburse(
            loanId: widget.loan.id,
            interestRate: result.$1,
            dueDate: result.$2,
          );
      ref.invalidate(chamaLoansProvider(widget.loan.chamaId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _reject,
            icon: const Icon(Icons.close_rounded, color: Colors.red),
            label: const Text('Reject', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _approve,
            icon: _busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded),
            label: const Text('Approve & disburse'),
          ),
        ),
      ],
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.principal});
  final double principal;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _rateCtrl = TextEditingController(text: '0');
  DateTime? _dueDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve & disburse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Principal: ${formatMoney(widget.principal)}',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          TextField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Interest rate (%)'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _dueDate == null
                      ? 'No due date set'
                      : 'Due: ${_dueDate!.toLocal()}'.split(' ').first,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: const Text('Pick date'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
            Navigator.pop(context, (rate, _dueDate));
          },
          child: const Text('Confirm'),
        ),
      ],
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
    final amountCtrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record repayment'),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            helperText: 'Outstanding: ${formatMoney(widget.loan.outstanding)}',
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

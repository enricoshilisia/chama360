import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency.dart';
import '../../../../core/utils/error_message.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/loan.dart';
import '../providers/loans_providers.dart';

/// Approve or reject a pending request, wherever it's shown — the member's
/// screen, the loan screen, or a notification that led to either.
///
/// Both decisions go through database functions rather than a plain update,
/// so the rules hold no matter which screen called them: only an admin can
/// decide, a rejection cannot be saved without a reason, and approving
/// clears any previous rejection so a stale explanation doesn't linger on a
/// loan that was subsequently granted.
class LoanDecisionButtons extends ConsumerStatefulWidget {
  const LoanDecisionButtons({super.key, required this.loan, this.onDecided});

  final Loan loan;
  final VoidCallback? onDecided;

  @override
  ConsumerState<LoanDecisionButtons> createState() => _LoanDecisionButtonsState();
}

class _LoanDecisionButtonsState extends ConsumerState<LoanDecisionButtons> {
  bool _busy = false;

  void _refresh() {
    ref.invalidate(chamaLoansProvider(widget.loan.chamaId));
    ref.invalidate(chamaTransactionsProvider(widget.loan.chamaId));
    ref.invalidate(myChamasProvider);
    widget.onDecided?.call();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, fallback: 'Could not save that.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final result = await showDialog<(double, DateTime?)>(
      context: context,
      builder: (context) => _ApproveDialog(loan: widget.loan),
    );
    if (result == null) return;
    await _run(() => ref.read(chamaRepositoryProvider).approveLoan(
          loanId: widget.loan.id,
          interestRate: result.$1,
          dueDate: result.$2,
        ));
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null) return;
    await _run(() => ref.read(chamaRepositoryProvider).rejectLoan(
          loanId: widget.loan.id,
          reason: reason,
        ));
  }

  @override
  Widget build(BuildContext context) {
    // A rejected request can still be approved later — people come back
    // with better timing or a smaller amount, and forcing them to submit
    // again would lose the history of what was asked.
    final rejected = widget.loan.status == 'rejected';

    return Row(
      children: [
        if (!rejected) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
              label: const Text('Reject', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _approve,
            icon: _busy
                ? const SizedBox(
                    height: 15,
                    width: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(rejected ? 'Approve after all' : 'Approve'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.loan});

  final Loan loan;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  final _rateCtrl = TextEditingController(text: '0');
  DateTime? _dueDate;

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Approve and disburse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.loan.borrowerName ?? 'This member'} asked for '
            '${formatMoney(widget.loan.principal)}.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
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
                      ? 'No due date'
                      : 'Due ${_dueDate!.toLocal()}'.split(' ').take(2).join(' '),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            (double.tryParse(_rateCtrl.text.trim()) ?? 0, _dueDate),
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}

/// The reason is required, and the button stays disabled until there is
/// one. The borrower is told exactly this text, so "no" always arrives
/// with an explanation attached.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reasonCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reasonCtrl.text.trim();
    return AlertDialog(
      title: const Text('Reject this request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The member will be shown this reason, so write it for them '
            'rather than for your own notes.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonCtrl,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. Previous loan not yet cleared',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: reason.length < 3 ? null : () => Navigator.pop(context, reason),
          child: const Text('Reject', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}

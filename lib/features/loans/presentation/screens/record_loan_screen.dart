import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/loan.dart';
import '../providers/loans_providers.dart';

/// Chairperson/treasurer records a loan directly as disbursed — for members
/// who have no app account and can't "request" one themselves.
class RecordLoanScreen extends ConsumerStatefulWidget {
  const RecordLoanScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  ConsumerState<RecordLoanScreen> createState() => _RecordLoanScreenState();
}

class _RecordLoanScreenState extends ConsumerState<RecordLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _rateCtrl = TextEditingController(text: '0');
  final _purposeCtrl = TextEditingController();
  String? _memberId;
  InterestPeriod _period = InterestPeriod.oneOff;
  DateTime? _dueDate;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_memberId == null) {
      setState(() => _error = 'Pick who this loan is for');
      return;
    }
    // A rate charged per month or per year needs a term to charge it
    // over. The database refuses this too; saying so here avoids a round
    // trip that comes back as an error with the form already filled in.
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0;
    if (_period != InterestPeriod.oneOff && rate > 0 && _dueDate == null) {
      setState(() => _error =
          'Set a due date — ${_period.label.toLowerCase()} interest is worked out '
          'from how long the loan runs.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(loansRepositoryProvider).recordLoanForMember(
            chamaId: widget.chamaId,
            memberId: _memberId!,
            principal: double.parse(_amountCtrl.text.trim()),
            interestRate: rate,
            interestPeriod: _period,
            purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
            dueDate: _dueDate,
          );
      ref.invalidate(chamaLoansProvider(widget.chamaId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan recorded and disbursed.')),
        );
        context.pop();
      }
    } catch (e) {
      // The database's own message is the useful one — it knows why.
      final raw = e.toString();
      final match = RegExp(r'message:\s*([^,]+)').firstMatch(raw);
      setState(() =>
          _error = match?.group(1)?.trim() ?? 'Could not record loan. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(chamaMembersProvider(widget.chamaId));

    return Scaffold(
      appBar: AppBar(title: const Text('Record a Loan')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.only(bottom: kShellBottomInset),
            children: [
              Text(
                'This records the loan as already disbursed.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              membersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load members: $e'),
                data: (members) => DropdownButtonFormField<String>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(labelText: 'Borrower'),
                  items: members
                      .map((m) => DropdownMenuItem(value: m.id, child: Text(m.displayName)))
                      .toList(),
                  onChanged: (v) => setState(() => _memberId = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Principal amount'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Interest rate (%)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<InterestPeriod>(
                      initialValue: _period,
                      decoration: const InputDecoration(labelText: 'Charged'),
                      items: [
                        for (final p in InterestPeriod.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: (v) => setState(() => _period = v ?? _period),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _InterestPreview(
                principal: double.tryParse(_amountCtrl.text.trim()) ?? 0,
                rate: double.tryParse(_rateCtrl.text.trim()) ?? 0,
                period: _period,
                dueDate: _dueDate,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _purposeCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Purpose (optional)'),
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
                      if (picked != null) {
                        setState(() {
                          _dueDate = picked;
                          _error = null;
                        });
                      }
                    },
                    child: const Text('Pick date'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Record & disburse'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows what the member will actually owe, as the form is filled in.
///
/// A rate and a period are two numbers that only mean something together,
/// and "5% a month over 90 days" is not arithmetic anyone should have to
/// do in their head while a borrower waits.
class _InterestPreview extends StatelessWidget {
  const _InterestPreview({
    required this.principal,
    required this.rate,
    required this.period,
    required this.dueDate,
  });

  final double principal;
  final double rate;
  final InterestPeriod period;
  final DateTime? dueDate;

  /// Mirrors loan_term_months() in 0012: started months, minimum one, so
  /// the figure here is the figure the database will store.
  int get _termMonths {
    if (dueDate == null) return 1;
    final days = dueDate!.difference(DateTime.now()).inDays;
    if (days <= 0) return 1;
    return (days / 30).ceil().clamp(1, 1200);
  }

  @override
  Widget build(BuildContext context) {
    if (principal <= 0) return const SizedBox.shrink();

    final multiplier = switch (period) {
      InterestPeriod.oneOff => rate / 100,
      InterestPeriod.perMonth => rate / 100 * _termMonths,
      InterestPeriod.perAnnum => rate / 100 * _termMonths / 12,
    };
    final interest = principal * multiplier;
    final total = principal + interest;

    final needsDate = period != InterestPeriod.oneOff && rate > 0 && dueDate == null;
    final style = TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4);

    if (needsDate) {
      return Text(
        'Pick a due date below — ${period.label.toLowerCase()} interest depends on '
        'how long the loan runs.',
        style: style.copyWith(color: Colors.orange.shade800),
      );
    }

    return Text(
      rate == 0
          ? 'No interest. ${formatMoney(principal)} to repay.'
          : '${formatMoney(principal)} + ${formatMoney(interest)} interest '
              '= ${formatMoney(total)} to repay'
              '${period == InterestPeriod.oneOff ? '' : ', over $_termMonths month${_termMonths == 1 ? '' : 's'}'}.',
      style: style,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
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
  DateTime? _dueDate;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_memberId == null) {
      setState(() => _error = 'Pick who this loan is for');
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
            interestRate: double.tryParse(_rateCtrl.text.trim()) ?? 0,
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
      setState(() => _error = 'Could not record loan. Try again.');
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
                decoration: const InputDecoration(labelText: 'Principal amount'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Interest rate (%)'),
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
                      if (picked != null) setState(() => _dueDate = picked);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../providers/loans_providers.dart';

class RequestLoanScreen extends ConsumerStatefulWidget {
  const RequestLoanScreen({
    super.key,
    required this.chamaId,
    required this.memberId,
  });

  final String chamaId;
  final String memberId;

  @override
  ConsumerState<RequestLoanScreen> createState() => _RequestLoanScreenState();
}

class _RequestLoanScreenState extends ConsumerState<RequestLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(loansRepositoryProvider).requestLoan(
            chamaId: widget.chamaId,
            memberId: widget.memberId,
            principal: double.parse(_amountCtrl.text.trim()),
            purpose: _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
          );
      ref.invalidate(chamaLoansProvider(widget.chamaId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loan request submitted.')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = 'Could not submit request. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request a Loan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, kShellBottomInset),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your request goes to the chairperson or treasurer for approval.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount requested'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _purposeCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Purpose (optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

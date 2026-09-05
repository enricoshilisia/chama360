import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/utils/error_message.dart';
import '../providers/chama_providers.dart';

class JoinChamaScreen extends ConsumerStatefulWidget {
  const JoinChamaScreen({super.key});

  @override
  ConsumerState<JoinChamaScreen> createState() => _JoinChamaScreenState();
}

class _JoinChamaScreenState extends ConsumerState<JoinChamaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(chamaRepositoryProvider)
          .joinChamaByCode(_codeCtrl.text.trim());
      ref.invalidate(myChamasProvider);
      if (mounted) context.go('/chamas/$id');
    } catch (e) {
      setState(() => _error = friendlyError(
            e,
            fallback: 'Invalid invite code, or you may already be a member.',
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a Chama')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, kShellBottomInset),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ask the chairperson or treasurer for the 6-character invite code.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Invite code'),
                validator: (v) =>
                    (v == null || v.trim().length < 4) ? 'Enter a valid code' : null,
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Join'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

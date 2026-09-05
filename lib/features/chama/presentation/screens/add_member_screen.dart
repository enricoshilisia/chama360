import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/theme/layout.dart';
import '../providers/chama_providers.dart';

/// Adds a member who has no app account of their own — the chairperson
/// records everything on their behalf (contributions, loans). See
/// add_managed_member() in supabase/migrations/0003_managed_members.sql.
class AddMemberScreen extends ConsumerStatefulWidget {
  const AddMemberScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  ConsumerState<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends ConsumerState<AddMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _role = ChamaRole.member;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(chamaRepositoryProvider).addManagedMember(
            chamaId: widget.chamaId,
            fullName: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
            role: _role,
          );
      ref.invalidate(chamaMembersProvider(widget.chamaId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_nameCtrl.text.trim()} added.')),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _error = 'Could not add member. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Member')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, kShellBottomInset),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This person won\'t sign in — you\'ll record their contributions and loans for them.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  ChamaRole.member,
                  ChamaRole.secretary,
                  ChamaRole.treasurer,
                  ChamaRole.chairperson,
                ]
                    .map((r) => DropdownMenuItem(value: r, child: Text(ChamaRole.label(r))))
                    .toList(),
                onChanged: (v) => setState(() => _role = v ?? ChamaRole.member),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add member'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

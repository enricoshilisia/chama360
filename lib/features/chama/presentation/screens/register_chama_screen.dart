import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/error_message.dart';
import '../../../../core/utils/phone_identity.dart';
import '../../../../core/widgets/glass_container.dart';
import '../providers/chama_providers.dart';

/// Registering a chama is deliberately not a one-field form. It collects
/// who is behind it — name, phone, email — because a person reviews every
/// registration before it can operate, and they need something to check.
class RegisterChamaScreen extends ConsumerStatefulWidget {
  const RegisterChamaScreen({super.key});

  @override
  ConsumerState<RegisterChamaScreen> createState() => _RegisterChamaScreenState();
}

class _RegisterChamaScreenState extends ConsumerState<RegisterChamaScreen> {
  static const _totalSteps = 3;

  final _detailsKey = GlobalKey<FormState>();
  final _ownerKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _ownerPhoneCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();

  int _step = 0;
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _ownerNameCtrl.dispose();
    _ownerPhoneCtrl.dispose();
    _ownerEmailCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !_detailsKey.currentState!.validate()) return;
    if (_step == 1 && !_ownerKey.currentState!.validate()) return;
    setState(() {
      _error = null;
      _step++;
    });
  }

  void _back() => setState(() {
        _error = null;
        _step--;
      });

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(chamaRepositoryProvider).submitChamaRegistration(
            chamaName: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            contactName: _ownerNameCtrl.text.trim(),
            contactPhone: PhoneIdentity.normalize(_ownerPhoneCtrl.text),
            contactEmail: _ownerEmailCtrl.text.trim(),
          );
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      setState(() =>
          _error = friendlyError(e, fallback: 'Could not submit the registration. Try again.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _SubmittedScreen(email: _ownerEmailCtrl.text.trim());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register a Chama'),
        leading: _step == 0
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
              )
            : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
      ),
      body: Column(
        children: [
          _StepIndicator(step: _step, total: _totalSteps),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: switch (_step) {
                0 => _detailsStep(),
                1 => _ownerStep(),
                _ => _reviewStep(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsStep() {
    return Form(
      key: _detailsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeading(
            title: 'About the chama',
            subtitle: 'What is the group called, and what is it for?',
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Chama name',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Enter the full name of the chama'
                : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'What the chama does (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _next, child: const Text('Continue')),
        ],
      ),
    );
  }

  Widget _ownerStep() {
    return Form(
      key: _ownerKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeading(
            title: 'Who runs it',
            subtitle: 'The chairperson\'s details. We use these to verify the '
                'registration before the chama goes live.',
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _ownerNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 3) ? 'Enter the chairperson\'s full name' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ownerPhoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '07XX XXX XXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (v) => PhoneIdentity.looksLikePhone(v ?? '')
                ? null
                : 'Enter a valid phone number',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ownerEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) =>
                (v == null || !v.contains('@') || !v.contains('.')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _next, child: const Text('Continue')),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading(
          title: 'Review and submit',
          subtitle: 'Check this over before sending it for approval.',
        ),
        const SizedBox(height: 20),
        GlassContainer(
          child: Column(
            children: [
              _ReviewRow('Chama', _nameCtrl.text.trim()),
              if (_descCtrl.text.trim().isNotEmpty)
                _ReviewRow('About', _descCtrl.text.trim()),
              const Divider(height: 24),
              _ReviewRow('Chairperson', _ownerNameCtrl.text.trim()),
              _ReviewRow('Phone', _ownerPhoneCtrl.text.trim()),
              _ReviewRow('Email', _ownerEmailCtrl.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Registrations are reviewed before a chama goes live. You won\'t be '
                  'able to add members or record contributions until it\'s approved.',
                  style: TextStyle(fontSize: 12.5, color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit for approval'),
        ),
      ],
    );
  }
}

/// After submission there is deliberately nothing to log into yet — the
/// account doesn't exist until the registration is approved. Saying so
/// plainly avoids someone hunting for a password they were never given.
class _SubmittedScreen extends StatelessWidget {
  const _SubmittedScreen({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassContainer(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                      ),
                      child: Icon(Icons.mark_email_read_outlined,
                          size: 32, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 20),
                    const Text('Registration received',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'We\'ll review it shortly. Once it\'s approved, an invitation to set '
                      'your password will be sent to $email — that\'s when your chama '
                      'becomes available.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, height: 1.5),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Back to sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= step ? primary : primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text('Step ${step + 1} of $total',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4, fontSize: 13.5)),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

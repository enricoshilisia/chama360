import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/chama_providers.dart';

/// Opens the "Add Contribution" form as a modal bottom sheet instead of a
/// full route — it's a quick, single-purpose action, so a sheet keeps the
/// chama detail screen underneath visible and feels lighter than a push.
Future<void> showAddContributionSheet(BuildContext context, {required String chamaId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AddContributionSheet(chamaId: chamaId),
  );
}

class AddContributionSheet extends ConsumerStatefulWidget {
  const AddContributionSheet({super.key, required this.chamaId});

  final String chamaId;

  @override
  ConsumerState<AddContributionSheet> createState() => _AddContributionSheetState();
}

class _AddContributionSheetState extends ConsumerState<AddContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedMemberId;
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMemberId == null) {
      setState(() => _error = 'Pick who this contribution is for');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final online = ref.read(isOnlineProvider);
    try {
      await ref.read(chamaRepositoryProvider).addContribution(
            chamaId: widget.chamaId,
            memberId: _selectedMemberId!,
            amount: double.parse(_amountCtrl.text.trim()),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            contributionDate: _date,
            online: online,
          );
      ref.invalidate(myChamasProvider);
      ref.invalidate(chamaTransactionsProvider(widget.chamaId));
      ref.invalidate(recentActivityProvider);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(online
                ? 'Contribution recorded.'
                : 'Saved offline — will sync once you\'re back online.'),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not save contribution. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final chama = ref.watch(chamaByIdProvider(widget.chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);
    final membersAsync = ref.watch(chamaMembersProvider(widget.chamaId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!isAdmin && chama != null) {
      _selectedMemberId ??= chama.memberId;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurface : AppColors.lightSurface)
                  .withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text('Add Contribution',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 18),
                      if (!online)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'You\'re offline. This will be queued and synced automatically.',
                            style: TextStyle(color: Colors.orange, fontSize: 12.5),
                          ),
                        ),
                      if (isAdmin)
                        membersAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: LinearProgressIndicator(),
                          ),
                          error: (e, _) => Text('Could not load members: $e'),
                          data: (members) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedMemberId,
                              decoration: const InputDecoration(labelText: 'Contribution from'),
                              items: members
                                  .map((m) =>
                                      DropdownMenuItem(value: m.id, child: Text(m.displayName)))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedMemberId = v),
                            ),
                          ),
                        ),
                      TextFormField(
                        controller: _amountCtrl,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Amount'),
                        validator: (v) {
                          final n = double.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Enter a valid amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          ),
                          child: Text('${_date.toLocal()}'.split(' ').first),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _notesCtrl,
                        decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

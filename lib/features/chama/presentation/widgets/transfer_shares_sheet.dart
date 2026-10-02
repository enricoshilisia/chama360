import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../domain/models/chama_member.dart';
import '../providers/chama_providers.dart';

/// Moves a member's shares into another member's name.
///
/// The chama's total does not change — this only moves who holds what —
/// so the sheet says so plainly. A reason is required, because the row
/// this writes is the audit record for somebody's money moving, and
/// "because the chairperson said so" is not a record.
Future<void> showTransferSharesSheet(
  BuildContext context, {
  required String chamaId,
  required ChamaMember from,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TransferSharesSheet(chamaId: chamaId, from: from),
  );
}

class _TransferSharesSheet extends ConsumerStatefulWidget {
  const _TransferSharesSheet({required this.chamaId, required this.from});

  final String chamaId;
  final ChamaMember from;

  @override
  ConsumerState<_TransferSharesSheet> createState() => _TransferSharesSheetState();
}

class _TransferSharesSheetState extends ConsumerState<_TransferSharesSheet> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  String? _toMemberId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  double get _held => widget.from.balance ?? 0;

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final reason = _reasonCtrl.text.trim();

    if (_toMemberId == null) {
      setState(() => _error = 'Pick who the shares are going to');
      return;
    }
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount to transfer');
      return;
    }
    if (amount > _held) {
      setState(() => _error =
          '${widget.from.displayName} only holds ${formatMoney(_held)}');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Say why the shares are moving');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(chamaRepositoryProvider).transferShares(
            chamaId: widget.chamaId,
            fromMemberId: widget.from.id,
            toMemberId: _toMemberId!,
            amount: amount,
            reason: reason,
          );

      ref.invalidate(chamaMembersProvider(widget.chamaId));
      ref.invalidate(shareTransfersProvider(widget.chamaId));
      ref.invalidate(chamaReportProvider(widget.chamaId));
      ref.invalidate(chamaTotalsProvider(widget.chamaId));
      ref.invalidate(chamaTransactionsProvider(widget.chamaId));
      ref.invalidate(memberTransactionsProvider((widget.chamaId, widget.from.id)));
      ref.invalidate(memberTransactionsProvider((widget.chamaId, _toMemberId!)));
      ref.invalidate(myChamasProvider);
      ref.invalidate(recentActivityProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${formatMoney(amount)} transferred.')),
      );
    } catch (e) {
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _readable(Object e) {
    final raw = e.toString();
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(raw);
    final message = match?.group(1)?.trim() ?? raw;
    return message.isEmpty ? 'Could not transfer those shares.' : message;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final membersAsync = ref.watch(chamaMembersProvider(widget.chamaId));
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

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
                    Text('Transfer shares',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.from.displayName} holds ${formatMoney(_held)}. '
                      'Moving shares does not change what the chama holds — only '
                      'who it belongs to.',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    membersAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) => Text('Could not load members: $e'),
                      data: (members) {
                        final others = members
                            .where((m) => m.id != widget.from.id)
                            .toList();
                        if (others.isEmpty) {
                          return Text('There is nobody else in this chama yet.',
                              style: TextStyle(color: Colors.grey.shade600));
                        }
                        return DropdownMenu<String>(
                          initialSelection: _toMemberId,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          menuHeight: 280,
                          expandedInsets: EdgeInsets.zero,
                          label: const Text('Transfer to'),
                          hintText: 'Type a name to search',
                          leadingIcon:
                              const Icon(Icons.person_search_outlined, size: 20),
                          inputDecorationTheme:
                              const InputDecorationTheme(filled: true),
                          dropdownMenuEntries: [
                            for (final m in others)
                              DropdownMenuEntry(value: m.id, label: m.displayName),
                          ],
                          onSelected: (v) => setState(() {
                            _toMemberId = v;
                            _error = null;
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() => _error = null),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        helperText: amount > 0 && amount <= _held
                            ? '${widget.from.displayName} would be left with '
                                '${formatMoney(_held - amount)}'
                            : null,
                        suffixIcon: TextButton(
                          onPressed: () => setState(() {
                            _amountCtrl.text = _held.toStringAsFixed(2);
                            _error = null;
                          }),
                          child: const Text('All'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _reasonCtrl,
                      minLines: 2,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() => _error = null),
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        hintText: 'e.g. Exiting the chama, shares bought by...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.history_edu_outlined,
                              size: 17,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Both members see this on their record, naming the '
                              'other side and the reason. Your name is kept against '
                              'it as the person who made the transfer.',
                              style: TextStyle(
                                  fontSize: 12, height: 1.4, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Transfer'),
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

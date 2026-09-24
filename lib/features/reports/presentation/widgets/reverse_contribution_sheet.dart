import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/chama_report.dart';
import '../providers/reports_providers.dart';

/// Opens a contribution for inspection, and — for a chairperson or
/// treasurer — offers to reverse it.
///
/// There is no delete here on purpose. Removing the row would leave the
/// member's balance overstated (it is maintained by a database trigger on
/// insert) and would erase the evidence that anything was ever recorded.
/// A reversal posts the opposite entry instead: the balance comes back to
/// where it was, and both the original and the correction stay on the
/// record with a reason attached.
Future<void> showContributionSheet(
  BuildContext context, {
  required String chamaId,
  required ContributionEntry entry,
  required String currency,
  required bool canReverse,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ContributionSheet(
      chamaId: chamaId,
      entry: entry,
      currency: currency,
      canReverse: canReverse,
    ),
  );
}

class _ContributionSheet extends ConsumerStatefulWidget {
  const _ContributionSheet({
    required this.chamaId,
    required this.entry,
    required this.currency,
    required this.canReverse,
  });

  final String chamaId;
  final ContributionEntry entry;
  final String currency;
  final bool canReverse;

  @override
  ConsumerState<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends ConsumerState<_ContributionSheet> {
  final _reasonCtrl = TextEditingController();
  bool _confirming = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _reverse() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Say why this is being reversed');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(chamaRepositoryProvider).reverseContribution(
            contributionId: widget.entry.id,
            reason: reason,
          );

      // Every figure derived from this contribution has just changed.
      ref.invalidate(chamaReportProvider(widget.chamaId));
      ref.invalidate(chamaTotalsProvider(widget.chamaId));
      ref.invalidate(chamaTransactionsProvider(widget.chamaId));
      ref.invalidate(chamaMembersProvider(widget.chamaId));
      ref.invalidate(memberTransactionsProvider((widget.chamaId, widget.entry.memberId)));
      ref.invalidate(myChamasProvider);
      ref.invalidate(recentActivityProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reversed. ${widget.entry.memberName}\'s balance has been corrected.',
          ),
        ),
      );
    } catch (e) {
      // The database is the one enforcing who may reverse what, so its
      // message is the useful one to show.
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static String _readable(Object e) {
    final raw = e.toString();
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(raw);
    final message = match?.group(1)?.trim() ?? raw;
    return message.isEmpty ? 'Could not reverse this contribution.' : message;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final e = widget.entry;

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
                    Text(
                      formatMoney(e.amount, currency: widget.currency),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        decoration: e.isReversed ? TextDecoration.lineThrough : null,
                        color: e.isReversed ? Colors.grey : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${e.memberName} · ${DateFormat('EEE, d MMM yyyy').format(e.date)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    if (e.notes != null && e.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(e.notes!.trim(),
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ],
                    if (e.isReversed) ...[
                      const SizedBox(height: 18),
                      _Banner(
                        icon: Icons.undo_rounded,
                        color: Colors.orange.shade800,
                        title: 'Reversed',
                        body: e.reversalReason ?? 'No reason was recorded.',
                      ),
                    ] else if (widget.canReverse) ...[
                      const SizedBox(height: 22),
                      if (!_confirming)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _confirming = true),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                          label: const Text('Reverse this contribution'),
                        )
                      else ...[
                        _Banner(
                          icon: Icons.info_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          title: 'This posts the opposite entry',
                          body:
                              '${e.memberName}\'s balance drops by '
                              '${formatMoney(e.amount, currency: widget.currency)} and both '
                              'entries stay on the record. Nothing is deleted.',
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _reasonCtrl,
                          autofocus: true,
                          minLines: 2,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            hintText: 'e.g. Recorded twice by mistake',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: _working
                                    ? null
                                    : () => setState(() {
                                          _confirming = false;
                                          _error = null;
                                        }),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _working ? null : _reverse,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                child: _working
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : const Text('Reverse'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 4),
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

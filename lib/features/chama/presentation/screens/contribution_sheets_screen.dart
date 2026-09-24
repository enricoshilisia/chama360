import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/file_share.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/content_width.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../reports/presentation/providers/reports_providers.dart';
import '../../data/contribution_workbook.dart';
import '../providers/chama_providers.dart';

/// Getting a chama's paper history into the app.
///
/// A chama that has been running for years arrives with a book, not with
/// an empty app. Typing three years of contributions through a modal is
/// not a real option, so this exports a workbook with a tab per member —
/// every date already filled in, so nobody has to type one — and takes it
/// back filled in, showing exactly what is about to be added before
/// anything is written.
class ContributionSheetsScreen extends ConsumerStatefulWidget {
  const ContributionSheetsScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  ConsumerState<ContributionSheetsScreen> createState() =>
      _ContributionSheetsScreenState();
}

class _ContributionSheetsScreenState
    extends ConsumerState<ContributionSheetsScreen> {
  late DateTime _from;
  late DateTime _to;
  PrefillSchedule _schedule = PrefillSchedule.monthly;
  bool _exporting = false;
  String? _exportError;

  bool _reading = false;
  bool _importing = false;
  String? _importError;
  ParsedWorkbook? _parsed;
  String? _parsedFileName;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // A year back is the common case. The picker reaches 2015 for a chama
    // with more history than that.
    _from = DateTime(now.year - 1, 1, 1);
    _to = DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _from : _to,
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime.now(),
      helpText: isStart ? 'Start of the period' : 'End of the period',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    try {
      final chama = ref.read(chamaByIdProvider(widget.chamaId));
      final members = await ref.read(chamaMembersProvider(widget.chamaId).future);
      final report = await ref.read(chamaReportProvider(widget.chamaId).future);

      final bytes = ContributionWorkbook.build(
        chamaId: widget.chamaId,
        chamaName: chama?.name ?? 'Chama',
        currency: chama?.currency ?? 'KES',
        members: members,
        existing: report.entries,
        from: _from,
        to: _to,
        schedule: _schedule,
      );

      final safeName = (chama?.name ?? 'chama')
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '')
          .toLowerCase();
      final fileName =
          '$safeName-contributions-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';

      await shareBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: '${chama?.name ?? 'Chama'} contribution sheets',
      );
    } catch (e) {
      setState(() => _exportError = 'Could not build the workbook: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _reading = true;
      _importError = null;
      _parsed = null;
      _parsedFileName = null;
    });
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose the filled-in workbook',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (file == null) return;

      // readAsBytes() rather than a path: on the web there is no file on
      // disk to reopen, and this is the one call that works everywhere.
      final bytes = await file.readAsBytes();

      final members = await ref.read(chamaMembersProvider(widget.chamaId).future);
      final parsed = ContributionWorkbook.parse(bytes, members: members);

      if (parsed.chamaId != null && parsed.chamaId != widget.chamaId) {
        setState(() => _importError =
            'That workbook was exported for a different chama. Export a fresh '
            'one from here and fill that in instead.');
        return;
      }

      setState(() {
        _parsed = parsed;
        _parsedFileName = file.name;
      });
    } catch (e) {
      setState(() => _importError = 'Could not read that file: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null || parsed.rows.isEmpty) return;

    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final result = await ref.read(chamaRepositoryProvider).importContributions(
            chamaId: widget.chamaId,
            rows: [
              for (final r in parsed.rows)
                {
                  'member_id': r.memberId,
                  'amount': r.amount,
                  'date': DateFormat('yyyy-MM-dd').format(r.date),
                  'notes': r.notes,
                },
            ],
          );

      ref.invalidate(chamaReportProvider(widget.chamaId));
      ref.invalidate(chamaTotalsProvider(widget.chamaId));
      ref.invalidate(chamaTransactionsProvider(widget.chamaId));
      ref.invalidate(chamaMembersProvider(widget.chamaId));
      ref.invalidate(myChamasProvider);
      ref.invalidate(recentActivityProvider);

      if (!mounted) return;
      setState(() {
        _parsed = null;
        _parsedFileName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.inserted} contribution${result.inserted == 1 ? '' : 's'} added'
            '${result.duplicates == 0 ? '' : ' · ${result.duplicates} were already recorded'}.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _importError = _readable(e));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  static String _readable(Object e) {
    final raw = e.toString();
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(raw);
    final message = match?.group(1)?.trim() ?? raw;
    return message.isEmpty ? 'Could not import that file.' : message;
  }

  @override
  Widget build(BuildContext context) {
    final chama = ref.watch(chamaByIdProvider(widget.chamaId));
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(title: const Text('Contribution sheets')),
      body: ContentWidth(
        maxWidth: 820,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
          children: [
            _ExportCard(
              from: _from,
              to: _to,
              schedule: _schedule,
              busy: _exporting,
              error: _exportError,
              onPickDate: _pickDate,
              onSchedule: (s) => setState(() => _schedule = s),
              onExport: _export,
            ),
            const SizedBox(height: 18),
            _ImportCard(
              fileName: _parsedFileName,
              parsed: _parsed,
              currency: currency,
              reading: _reading,
              importing: _importing,
              error: _importError,
              onPick: _pickFile,
              onImport: _import,
              onDiscard: () => setState(() {
                _parsed = null;
                _parsedFileName = null;
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ export

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.from,
    required this.to,
    required this.schedule,
    required this.busy,
    required this.error,
    required this.onPickDate,
    required this.onSchedule,
    required this.onExport,
  });

  final DateTime from;
  final DateTime to;
  final PrefillSchedule schedule;
  final bool busy;
  final String? error;
  final Future<void> Function({required bool isStart}) onPickDate;
  final ValueChanged<PrefillSchedule> onSchedule;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.download_rounded,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text('Export a template',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'One tab per member, with every date already filled in and anything '
            'already recorded shown in place. Fill in the amounts and upload it '
            'back below.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'From',
                  value: from,
                  onTap: () => onPickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateField(
                  label: 'To',
                  value: to,
                  onTap: () => onPickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Rows to lay out',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          for (final option in PrefillSchedule.values)
            RadioListTile<PrefillSchedule>(
              value: option,
              // ignore: deprecated_member_use
              groupValue: schedule,
              // ignore: deprecated_member_use
              onChanged: (v) => v == null ? null : onSchedule(v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(option.label, style: const TextStyle(fontSize: 13.5)),
            ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: busy ? null : onExport,
            icon: busy
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.table_chart_outlined, size: 18),
            label: Text(busy ? 'Building…' : 'Export Excel workbook'),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(DateFormat('d MMM yyyy').format(value)),
      ),
    );
  }
}

// ------------------------------------------------------------------ import

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.fileName,
    required this.parsed,
    required this.currency,
    required this.reading,
    required this.importing,
    required this.error,
    required this.onPick,
    required this.onImport,
    required this.onDiscard,
  });

  final String? fileName;
  final ParsedWorkbook? parsed;
  final String currency;
  final bool reading;
  final bool importing;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onImport;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final p = parsed;

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.upload_file_rounded,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text('Upload a filled sheet',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Every tab is read at once. Nothing is written until you have seen '
            'what is about to be added.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: reading || importing ? null : onPick,
            icon: reading
                ? const SizedBox(
                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_open_rounded, size: 18),
            label: Text(reading
                ? 'Reading…'
                : fileName == null
                    ? 'Choose an .xlsx file'
                    : 'Choose a different file'),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
          ],
          if (p != null) ...[
            const SizedBox(height: 18),
            Text(fileName ?? 'Workbook',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 10),
            _PreviewSummary(parsed: p, currency: currency),
            if (p.problems.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Problems(problems: p.problems),
            ],
            if (p.rows.isNotEmpty) ...[
              const SizedBox(height: 14),
              _PerMemberPreview(parsed: p, currency: currency),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: importing ? null : onDiscard,
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: importing ? null : onImport,
                      child: importing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('Add ${p.rows.length} contribution'
                              '${p.rows.length == 1 ? '' : 's'}'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 14),
              Text(
                p.alreadyRecorded > 0
                    ? 'Nothing new in this file — every row in it is already recorded.'
                    : 'No amounts were filled in anywhere in this file.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.parsed, required this.currency});

  final ParsedWorkbook parsed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rows = parsed.rows;
    final range = rows.isEmpty
        ? '—'
        : '${DateFormat('MMM yyyy').format(rows.first.date)} → '
            '${DateFormat('MMM yyyy').format(rows.last.date)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _Line(label: 'New contributions', value: '${rows.length}'),
          _Line(
              label: 'Total',
              value: formatMoney(parsed.total, currency: currency)),
          _Line(label: 'Members', value: '${parsed.memberIds.length}'),
          _Line(label: 'Period', value: range),
          if (parsed.alreadyRecorded > 0)
            _Line(
              label: 'Already recorded',
              value: '${parsed.alreadyRecorded} (left alone)',
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ),
          Text(value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PerMemberPreview extends StatelessWidget {
  const _PerMemberPreview({required this.parsed, required this.currency});

  final ParsedWorkbook parsed;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final totals = <String, ({String name, double total, int count})>{};
    for (final r in parsed.rows) {
      final seen = totals[r.memberId];
      totals[r.memberId] = (
        name: r.memberName,
        total: (seen?.total ?? 0) + r.amount,
        count: (seen?.count ?? 0) + 1,
      );
    }
    final sorted = totals.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per member',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        for (final m in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                ),
                Text('${m.count} × ',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                Text(formatMoney(m.total, currency: currency),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Problems extends StatelessWidget {
  const _Problems({required this.problems});

  final List<WorkbookProblem> problems;

  @override
  Widget build(BuildContext context) {
    final shown = problems.take(12).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${problems.length} row${problems.length == 1 ? '' : 's'} will be '
                  'skipped',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${p.where} — ${p.message}',
                  style: const TextStyle(fontSize: 12, height: 1.4)),
            ),
          if (problems.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('…and ${problems.length - shown.length} more',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }
}

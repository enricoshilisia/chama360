import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../domain/models/chama_member.dart';
import '../../reports/domain/models/chama_report.dart';

/// How often the template pre-fills a date to write an amount against.
///
/// Pre-filling is the whole point: Excel has no calendar popup for a cell,
/// so the reliable way to get dates right is for nobody to type one. The
/// date picker lives in the app, on the export screen, and the spreadsheet
/// arrives with every period already laid out.
enum PrefillSchedule {
  monthly('One row per month'),
  weekly('One row per week'),
  none('No pre-filled dates');

  const PrefillSchedule(this.label);
  final String label;
}

/// A contribution read back out of an uploaded workbook, with where it came
/// from so a problem can be pointed at rather than described.
class ParsedContribution {
  const ParsedContribution({
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.date,
    required this.sheet,
    required this.row,
    this.notes,
  });

  final String memberId;
  final String memberName;
  final double amount;
  final DateTime date;
  final String sheet;
  final int row; // 1-based, as Excel shows it
  final String? notes;
}

class WorkbookProblem {
  const WorkbookProblem({required this.sheet, required this.row, required this.message});

  final String sheet;
  final int row;
  final String message;

  String get where => row > 0 ? '$sheet, row $row' : sheet;
}

class ParsedWorkbook {
  const ParsedWorkbook({
    required this.chamaId,
    required this.rows,
    required this.problems,
    required this.alreadyRecorded,
  });

  /// Whatever chama the workbook says it belongs to — checked against the
  /// one being imported into, so a sheet for the wrong chama is caught
  /// before anything is written.
  final String? chamaId;
  final List<ParsedContribution> rows;
  final List<WorkbookProblem> problems;

  /// Rows carrying a Record ID: already on the system, deliberately
  /// skipped rather than reported as a problem.
  final int alreadyRecorded;

  double get total => rows.fold<double>(0, (sum, r) => sum + r.amount);

  Set<String> get memberIds => {for (final r in rows) r.memberId};
}

/// Builds and reads the contribution workbook: one sheet per member, plus a
/// summary sheet that explains itself.
class ContributionWorkbook {
  static const _summarySheet = 'Summary';
  static const _dateHeader = 'Date';

  static final _dateFormat = DateFormat('dd/MM/yyyy');

  // ------------------------------------------------------------- writing

  static Uint8List build({
    required String chamaId,
    required String chamaName,
    required String currency,
    required List<ChamaMember> members,
    required List<ContributionEntry> existing,
    required DateTime from,
    required DateTime to,
    required PrefillSchedule schedule,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    final byMember = <String, List<ContributionEntry>>{};
    for (final e in existing) {
      if (e.isReversed) continue; // a reversed entry is not money in the pot
      byMember.putIfAbsent(e.memberId, () => []).add(e);
    }

    final sheetNames = <String, String>{};
    // The summary, and the blank sheet createExcel() seeds and we delete at
    // the end: a member whose name sanitised to either would have their tab
    // written into the wrong sheet, or deleted with it.
    final used = <String>{
      _summarySheet.toLowerCase(),
      if (defaultSheet != null) defaultSheet.toLowerCase(),
    };
    for (final m in members) {
      sheetNames[m.id] = _uniqueSheetName(m.displayName, used);
    }

    _writeSummary(
      excel,
      chamaId: chamaId,
      chamaName: chamaName,
      currency: currency,
      members: members,
      byMember: byMember,
      sheetNames: sheetNames,
      from: from,
      to: to,
      schedule: schedule,
    );

    for (final m in members) {
      _writeMemberSheet(
        excel,
        sheetName: sheetNames[m.id]!,
        chamaId: chamaId,
        chamaName: chamaName,
        currency: currency,
        member: m,
        existing: byMember[m.id] ?? const [],
        from: from,
        to: to,
        schedule: schedule,
      );
    }

    // Excel.createExcel() seeds a blank sheet; leaving it in the file makes
    // the workbook look unfinished and gives the importer a sheet it has to
    // recognise and ignore.
    if (defaultSheet != null && excel.sheets.length > 1) {
      excel.setDefaultSheet(_summarySheet);
      excel.delete(defaultSheet);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('Could not build the workbook');
    }
    return Uint8List.fromList(bytes);
  }

  static void _writeSummary(
    Excel excel, {
    required String chamaId,
    required String chamaName,
    required String currency,
    required List<ChamaMember> members,
    required Map<String, List<ContributionEntry>> byMember,
    required Map<String, String> sheetNames,
    required DateTime from,
    required DateTime to,
    required PrefillSchedule schedule,
  }) {
    final sheet = excel[_summarySheet];
    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 26);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 16);

    var row = 0;
    void put(int col, CellValue? value, {CellStyle? style}) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        value,
        cellStyle: style,
      );
    }

    put(0, TextCellValue('$chamaName — contribution history'), style: _title);
    row += 1;
    put(0, TextCellValue('Exported ${_dateFormat.format(DateTime.now())}'), style: _muted);
    row += 2;

    put(0, TextCellValue('How to fill this in'), style: _heading);
    row += 1;
    for (final line in [
      'There is one tab per member, listed below. Open a member\'s tab and '
          'type what they paid next to each date.',
      'The dates are already filled in (${schedule.label.toLowerCase()}), so you '
          'never have to type one. Leave a row blank if there was no contribution.',
      'Rows that already show a Record ID are on the system. Leave those alone — '
          'they are there so you can see what is already recorded.',
      'Use the blank rows at the bottom of a tab for anything that does not fall '
          'on one of the dates listed.',
      'Do not change the Member ID or Chama ID at the top of a tab, or rename '
          'the Date / Amount / Notes columns. That is how the app knows where a '
          'row belongs.',
      'Save the file and upload it back into Chama360. You will see exactly what '
          'is about to be added before anything is written.',
    ]) {
      put(0, TextCellValue('•  $line'), style: _wrapped);
      row += 1;
    }
    row += 1;

    put(0, TextCellValue('Period covered'), style: _heading);
    put(1, TextCellValue('${_dateFormat.format(from)} to ${_dateFormat.format(to)}'));
    row += 1;
    put(0, TextCellValue('Chama ID'), style: _label);
    put(1, TextCellValue(chamaId));
    row += 2;

    put(0, TextCellValue('Member'), style: _tableHeader);
    put(1, TextCellValue('Tab'), style: _tableHeader);
    put(2, TextCellValue('Role'), style: _tableHeader);
    put(3, TextCellValue('Recorded so far ($currency)'), style: _tableHeader);
    row += 1;

    for (final m in members) {
      final total = (byMember[m.id] ?? const <ContributionEntry>[])
          .fold<double>(0, (sum, e) => sum + e.amount);
      put(0, TextCellValue(m.displayName));
      put(1, TextCellValue(sheetNames[m.id]!));
      put(2, TextCellValue(m.role));
      put(3, DoubleCellValue(total), style: _money);
      row += 1;
    }
  }

  static void _writeMemberSheet(
    Excel excel, {
    required String sheetName,
    required String chamaId,
    required String chamaName,
    required String currency,
    required ChamaMember member,
    required List<ContributionEntry> existing,
    required DateTime from,
    required DateTime to,
    required PrefillSchedule schedule,
  }) {
    final sheet = excel[sheetName];
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 18);
    sheet.setColumnWidth(2, 34);
    sheet.setColumnWidth(3, 38);

    var row = 0;
    void put(int col, CellValue? value, {CellStyle? style}) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        value,
        cellStyle: style,
      );
    }

    put(0, TextCellValue(member.displayName), style: _title);
    row += 1;
    put(0, TextCellValue('Chama'), style: _label);
    put(1, TextCellValue(chamaName));
    row += 1;
    put(0, TextCellValue('Member ID'), style: _label);
    put(1, TextCellValue(member.id), style: _muted);
    row += 1;
    put(0, TextCellValue('Chama ID'), style: _label);
    put(1, TextCellValue(chamaId), style: _muted);
    row += 1;
    put(
      0,
      TextCellValue('Type the amount next to a date. Leave it blank if there was '
          'nothing that period. Rows with a Record ID are already recorded — '
          'leave those alone.'),
      style: _muted,
    );
    row += 2;

    put(0, TextCellValue(_dateHeader), style: _tableHeader);
    put(1, TextCellValue('Amount ($currency)'), style: _tableHeader);
    put(2, TextCellValue('Notes'), style: _tableHeader);
    put(3, TextCellValue('Record ID (do not edit)'), style: _tableHeader);
    row += 1;

    // One chronological list: every period in the range, with whatever is
    // already recorded shown in place, plus anything recorded on a date the
    // schedule doesn't land on.
    final existingByDate = <DateTime, List<ContributionEntry>>{};
    for (final e in existing) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      existingByDate.putIfAbsent(key, () => []).add(e);
    }

    final dates = <DateTime>{
      ..._scheduleDates(from, to, schedule),
      ...existingByDate.keys,
    }.toList()
      ..sort();

    for (final date in dates) {
      final onThisDate = existingByDate[date];
      if (onThisDate == null || onThisDate.isEmpty) {
        put(0, DateCellValue.fromDateTime(date), style: _dateStyle);
        put(1, null, style: _money);
        row += 1;
        continue;
      }
      for (final e in onThisDate) {
        put(0, DateCellValue.fromDateTime(date), style: _dateStyle);
        put(1, DoubleCellValue(e.amount), style: _recordedMoney);
        put(2, e.notes == null ? null : TextCellValue(e.notes!), style: _recorded);
        put(3, TextCellValue(e.id), style: _recorded);
        row += 1;
      }
    }

    // Room for anything irregular. The date column is still formatted as a
    // date, so a typed one is read as a date rather than as text.
    for (var i = 0; i < 20; i++) {
      put(0, null, style: _dateStyle);
      put(1, null, style: _money);
      row += 1;
    }
  }

  static List<DateTime> _scheduleDates(DateTime from, DateTime to, PrefillSchedule schedule) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return const [];

    switch (schedule) {
      case PrefillSchedule.none:
        return const [];
      case PrefillSchedule.weekly:
        final out = <DateTime>[];
        var cursor = start;
        while (!cursor.isAfter(end) && out.length < 600) {
          out.add(cursor);
          cursor = cursor.add(const Duration(days: 7));
        }
        return out;
      case PrefillSchedule.monthly:
        final out = <DateTime>[];
        var cursor = DateTime(start.year, start.month, 1);
        while (!cursor.isAfter(end) && out.length < 240) {
          // Last day of the month, or today if that month is still running —
          // a contribution can't be dated in the future.
          final lastOfMonth = DateTime(cursor.year, cursor.month + 1, 0);
          out.add(lastOfMonth.isAfter(end) ? end : lastOfMonth);
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
        }
        return out;
    }
  }

  /// Excel refuses `: \ / ? * [ ]`, anything over 31 characters, and two
  /// sheets with the same name.
  static String _uniqueSheetName(String raw, Set<String> used) {
    var name = raw.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (name.isEmpty) name = 'Member';
    if (name.length > 28) name = name.substring(0, 28).trim();

    var candidate = name;
    var n = 2;
    while (used.contains(candidate.toLowerCase())) {
      final suffix = ' $n';
      final head = name.length + suffix.length > 31
          ? name.substring(0, 31 - suffix.length)
          : name;
      candidate = '$head$suffix';
      n++;
    }
    used.add(candidate.toLowerCase());
    return candidate;
  }

  // ------------------------------------------------------------- reading

  static ParsedWorkbook parse(Uint8List bytes, {required List<ChamaMember> members}) {
    final excel = Excel.decodeBytes(bytes);
    final knownMembers = {for (final m in members) m.id: m};

    final rows = <ParsedContribution>[];
    final problems = <WorkbookProblem>[];
    var alreadyRecorded = 0;
    String? chamaId;

    for (final entry in excel.tables.entries) {
      final sheetName = entry.key;
      if (sheetName.toLowerCase() == _summarySheet.toLowerCase()) continue;

      final table = entry.value;
      final grid = table.rows;
      if (grid.isEmpty) continue;

      final memberId = _labelledValue(grid, 'Member ID');
      chamaId ??= _labelledValue(grid, 'Chama ID');

      if (memberId == null || memberId.isEmpty) {
        problems.add(WorkbookProblem(
          sheet: sheetName,
          row: 0,
          message: 'No Member ID at the top of this tab, so there is no way to '
              'tell whose contributions these are. Export a fresh template and '
              'fill that in instead.',
        ));
        continue;
      }

      final member = knownMembers[memberId];
      if (member == null) {
        problems.add(WorkbookProblem(
          sheet: sheetName,
          row: 0,
          message: 'This tab belongs to someone who is no longer an active '
              'member of this chama.',
        ));
        continue;
      }

      final headerRow = _headerRowIndex(grid);
      if (headerRow == null) {
        problems.add(WorkbookProblem(
          sheet: sheetName,
          row: 0,
          message: 'Could not find the Date / Amount columns on this tab.',
        ));
        continue;
      }

      for (var r = headerRow + 1; r < grid.length; r++) {
        final cells = grid[r];
        final rowNumber = r + 1; // Excel counts from 1

        final recordId = _text(_cellAt(cells, 3));
        final rawAmount = _cellAt(cells, 1);
        final amount = _number(rawAmount);
        final rawDate = _cellAt(cells, 0);

        if (recordId != null && recordId.isNotEmpty) {
          alreadyRecorded++;
          continue;
        }

        // A pre-filled date with nothing written against it is the normal
        // case for a period with no contribution, not a mistake.
        if (amount == null) {
          final leftover = _text(_cellAt(cells, 1));
          if (leftover != null && leftover.trim().isNotEmpty) {
            problems.add(WorkbookProblem(
              sheet: sheetName,
              row: rowNumber,
              message: '"$leftover" is not an amount.',
            ));
          }
          continue;
        }

        if (amount <= 0) {
          problems.add(WorkbookProblem(
            sheet: sheetName,
            row: rowNumber,
            message: 'An amount has to be more than zero.',
          ));
          continue;
        }

        final date = _date(rawDate);
        if (date == null) {
          problems.add(WorkbookProblem(
            sheet: sheetName,
            row: rowNumber,
            message: 'There is an amount here but no date to put it against.',
          ));
          continue;
        }

        final today = DateTime.now();
        if (date.isAfter(DateTime(today.year, today.month, today.day))) {
          problems.add(WorkbookProblem(
            sheet: sheetName,
            row: rowNumber,
            message: '${_dateFormat.format(date)} is in the future.',
          ));
          continue;
        }

        rows.add(ParsedContribution(
          memberId: memberId,
          memberName: member.displayName,
          amount: amount,
          date: date,
          notes: _text(_cellAt(cells, 2)),
          sheet: sheetName,
          row: rowNumber,
        ));
      }
    }

    rows.sort((a, b) => a.date.compareTo(b.date));
    return ParsedWorkbook(
      chamaId: chamaId,
      rows: rows,
      problems: problems,
      alreadyRecorded: alreadyRecorded,
    );
  }

  static Data? _cellAt(List<Data?> cells, int index) =>
      index < cells.length ? cells[index] : null;

  /// Finds the value written beside a label in the first column, which is
  /// how the header block at the top of each tab is laid out.
  static String? _labelledValue(List<List<Data?>> grid, String label) {
    final wanted = label.toLowerCase();
    for (var r = 0; r < grid.length && r < 15; r++) {
      final first = _text(_cellAt(grid[r], 0))?.trim().toLowerCase();
      if (first == wanted) return _text(_cellAt(grid[r], 1))?.trim();
    }
    return null;
  }

  static int? _headerRowIndex(List<List<Data?>> grid) {
    for (var r = 0; r < grid.length && r < 30; r++) {
      final first = _text(_cellAt(grid[r], 0))?.trim().toLowerCase();
      if (first == _dateHeader.toLowerCase()) return r;
    }
    return null;
  }

  static String? _text(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    return switch (value) {
      TextCellValue() => value.value.toString(),
      _ => value.toString(),
    };
  }

  static double? _number(Data? cell) {
    final value = cell?.value;
    return switch (value) {
      IntCellValue() => value.value.toDouble(),
      DoubleCellValue() => value.value,
      // Someone retyping a column can leave it as text; "1,200" and
      // "KES 1,200.00" are both what a person would consider an amount.
      TextCellValue() => double.tryParse(
          value.value.toString().replaceAll(RegExp(r'[^0-9.\-]'), ''),
        ),
      _ => null,
    };
  }

  static DateTime? _date(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;

    if (value is DateCellValue) return value.asDateTimeLocal();
    if (value is DateTimeCellValue) {
      final dt = value.asDateTimeLocal();
      return DateTime(dt.year, dt.month, dt.day);
    }

    // A cell formatted as a number still holds Excel's day serial.
    if (value is IntCellValue) return _fromExcelSerial(value.value.toDouble());
    if (value is DoubleCellValue) return _fromExcelSerial(value.value);

    if (value is TextCellValue) {
      final text = value.value.toString().trim();
      if (text.isEmpty) return null;
      for (final format in [
        'dd/MM/yyyy',
        'd/M/yyyy',
        'yyyy-MM-dd',
        'dd-MM-yyyy',
        'd MMM yyyy',
        'd MMMM yyyy',
      ]) {
        try {
          return DateFormat(format).parseStrict(text);
        } catch (_) {
          // Try the next shape.
        }
      }
      return DateTime.tryParse(text);
    }
    return null;
  }

  /// Excel counts days from 1899-12-30 (the offset absorbs its deliberate
  /// 1900 leap-year bug).
  static DateTime? _fromExcelSerial(double serial) {
    if (serial < 1 || serial > 80000) return null;
    final date = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    return DateTime(date.year, date.month, date.day);
  }

  // -------------------------------------------------------------- styles

  static final _title = CellStyle(bold: true, fontSize: 14);
  static final _heading = CellStyle(bold: true, fontSize: 12);
  static final _label = CellStyle(bold: true);
  static final _muted = CellStyle(fontColorHex: ExcelColor.grey600);
  static final _wrapped = CellStyle(textWrapping: TextWrapping.WrapText);
  static final _tableHeader = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.white,
    backgroundColorHex: ExcelColor.green700,
  );
  static final _dateStyle = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd/mm/yyyy'));
  static final _money = CellStyle(numberFormat: NumFormat.custom(formatCode: '#,##0.00'));
  static final _recorded = CellStyle(fontColorHex: ExcelColor.grey600);
  static final _recordedMoney = CellStyle(
    fontColorHex: ExcelColor.grey600,
    numberFormat: NumFormat.custom(formatCode: '#,##0.00'),
  );
}

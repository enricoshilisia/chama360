import 'dart:typed_data';

import 'package:chama360/features/chama/data/contribution_workbook.dart';
import 'package:chama360/features/chama/domain/models/chama_member.dart';
import 'package:chama360/features/reports/domain/models/chama_report.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The workbook is the only place in the app where data leaves and comes
/// back through a file someone has edited by hand, so the round trip is
/// worth pinning down: what is written has to be what is read.
void main() {
  const chamaId = '11111111-1111-1111-1111-111111111111';

  final members = [
    const ChamaMember(
      id: 'aaaaaaaa-0000-0000-0000-000000000001',
      userId: null,
      role: 'chairperson',
      displayName: 'Lawrence Mwiti',
    ),
    const ChamaMember(
      id: 'aaaaaaaa-0000-0000-0000-000000000002',
      userId: null,
      role: 'member',
      displayName: 'Kenneth Kithinji',
    ),
    // Excel forbids these characters in a sheet name and caps it at 31
    // characters; a real roster will eventually contain one.
    const ChamaMember(
      id: 'aaaaaaaa-0000-0000-0000-000000000003',
      userId: null,
      role: 'member',
      displayName: 'Mary / Jane Wangui-Mwangi of Meru',
    ),
  ];

  ContributionEntry recorded(String id, String memberId, double amount, DateTime date) {
    return ContributionEntry(
      id: id,
      memberId: memberId,
      memberName: 'x',
      amount: amount,
      date: date,
    );
  }

  test('a freshly exported workbook has nothing new to import', () {
    final bytes = ContributionWorkbook.build(
      chamaId: chamaId,
      chamaName: 'Kamundi Family',
      currency: 'KES',
      members: members,
      existing: [
        recorded('c1', members[1].id, 1200, DateTime(2023, 9, 26)),
        recorded('c2', members[1].id, 1200, DateTime(2024, 12, 26)),
      ],
      from: DateTime(2023, 1, 1),
      to: DateTime(2024, 12, 31),
      schedule: PrefillSchedule.monthly,
    );

    final parsed = ContributionWorkbook.parse(bytes, members: members);

    expect(parsed.chamaId, chamaId);
    expect(parsed.rows, isEmpty, reason: 'no amounts have been filled in yet');
    expect(parsed.problems, isEmpty);
    // The two already-recorded rows carry a Record ID and are left alone.
    expect(parsed.alreadyRecorded, 2);
  });

  test('amounts typed against the pre-filled dates come back out', () {
    final bytes = ContributionWorkbook.build(
      chamaId: chamaId,
      chamaName: 'Kamundi Family',
      currency: 'KES',
      members: members,
      existing: const [],
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 3, 31),
      schedule: PrefillSchedule.monthly,
    );

    // Stand in for someone typing into the sheet.
    final filled = _fillAmounts(bytes, sheet: 'Kenneth Kithinji', amounts: [500, null, 750]);
    final parsed = ContributionWorkbook.parse(filled, members: members);

    expect(parsed.problems, isEmpty);
    expect(parsed.rows.length, 2);
    expect(parsed.rows.map((r) => r.amount), [500, 750]);
    expect(parsed.rows.every((r) => r.memberId == members[1].id), isTrue);

    // Monthly rows land on the last day of each month, and the dates
    // survive the trip through the file intact.
    expect(parsed.rows.first.date, DateTime(2025, 1, 31));
    expect(parsed.rows.last.date, DateTime(2025, 3, 31));
    expect(parsed.total, 1250);
  });

  test('a sheet name that Excel would reject is made safe and still resolves', () {
    final bytes = ContributionWorkbook.build(
      chamaId: chamaId,
      chamaName: 'Kamundi Family',
      currency: 'KES',
      members: members,
      existing: const [],
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 1, 31),
      schedule: PrefillSchedule.monthly,
    );

    final parsed = ContributionWorkbook.parse(bytes, members: members);
    expect(parsed.problems, isEmpty);
  });

  test('a monthly period that is still running stops at the end date', () {
    final bytes = ContributionWorkbook.build(
      chamaId: chamaId,
      chamaName: 'Kamundi Family',
      currency: 'KES',
      members: [members.first],
      existing: const [],
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 24),
      schedule: PrefillSchedule.monthly,
    );

    final filled = _fillAmounts(bytes, sheet: 'Lawrence Mwiti', amounts: [2000]);
    final parsed = ContributionWorkbook.parse(filled, members: members);

    expect(parsed.rows.single.date, DateTime(2026, 9, 24),
        reason: 'a contribution cannot be dated past the end of the period');
  });
}

/// Writes amounts down the Amount column of one tab, the way a person
/// would, and hands the file back as bytes.
Uint8List _fillAmounts(
  Uint8List bytes, {
  required String sheet,
  required List<double?> amounts,
}) {
  final excel = Excel.decodeBytes(bytes);
  final table = excel.tables[sheet];
  expect(table, isNotNull, reason: 'no tab called "$sheet" in ${excel.tables.keys}');

  final headerRow = table!.rows.indexWhere((row) =>
      row.isNotEmpty && row.first?.value is TextCellValue &&
      row.first!.value.toString() == 'Date');
  expect(headerRow, isNot(-1));

  for (var i = 0; i < amounts.length; i++) {
    final amount = amounts[i];
    if (amount == null) continue;
    excel.updateCell(
      sheet,
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: headerRow + 1 + i),
      DoubleCellValue(amount),
    );
  }

  return Uint8List.fromList(excel.encode()!);
}

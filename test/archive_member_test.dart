import 'package:chama360/features/chama/domain/models/archived_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every reason the database accepts has a label here', () {
    // These must match the archive_reason check constraint in 0014.
    const allowed = {'deceased', 'left', 'relocated', 'inactive', 'removed', 'other'};
    expect(ArchiveReason.values.map((r) => r.value).toSet(), allowed);
    for (final r in ArchiveReason.values) {
      expect(r.label, isNotEmpty);
    }
  });

  test('only "other" demands an explanation', () {
    expect(ArchiveReason.other.needsNote, isTrue);
    for (final r in ArchiveReason.values.where((r) => r != ArchiveReason.other)) {
      expect(r.needsNote, isFalse, reason: '${r.value} should not require a note');
    }
  });

  test('a reason the app does not know about does not crash it', () {
    expect(ArchiveReason.fromValue('emigrated'), isNull);
    expect(ArchiveReason.fromValue(null), isNull);
    expect(ArchiveReason.fromValue('deceased'), ArchiveReason.deceased);
  });

  test('rows archived before reasons existed say so plainly', () {
    final legacy = ArchivedMember.fromJson({
      'id': 'm1',
      'display_name': 'Old Member',
      'role': 'member',
      'status': 'removed',
      'archived_at': null,
      'archive_reason': null,
      'archive_note': null,
      'archived_balance': null,
      'balance': 0,
      'archived_by_name': 'An administrator',
    });
    expect(legacy.reason, isNull);
    expect(legacy.reasonLabel, 'No reason recorded');
    expect(legacy.stillHoldsShares, isFalse);
  });

  test('a balance left standing in an archived name is flagged', () {
    final holding = ArchivedMember.fromJson({
      'id': 'm2',
      'display_name': 'Charity Kimathi',
      'role': 'member',
      'status': 'archived',
      'archived_at': '2026-10-02T00:00:00Z',
      'archive_reason': 'left',
      'archive_note': 'Moved to Mombasa',
      'archived_balance': 7200,
      'balance': 7200,
      'archived_by_name': 'Lawrence Mwiti',
    });
    expect(holding.reason, ArchiveReason.left);
    expect(holding.reasonLabel, 'Left the chama');
    expect(holding.stillHoldsShares, isTrue);
    // What they held when they left survives a later transfer.
    expect(holding.archivedBalance, 7200);
  });
}

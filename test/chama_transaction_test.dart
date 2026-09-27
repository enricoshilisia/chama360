import 'package:chama360/features/chama/domain/models/chama_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ledger carries two dates and they mean different things. Getting
/// this wrong is what made every imported 2017 contribution display as the
/// day it was uploaded.
void main() {
  Map<String, dynamic> row({String? occurredAt}) => {
        'id': 't1',
        'chama_id': 'c1',
        'member_id': 'm1',
        'type': 'contribution',
        'amount': 1200,
        'balance_after': 1200,
        'created_at': '2026-09-27T05:43:00Z',
        if (occurredAt != null) 'occurred_at': occurredAt,
      };

  test('occurredAt is the value date, not the write date', () {
    final t = ChamaTransaction.fromJson(row(occurredAt: '2017-12-26T00:00:00Z'));
    expect(t.occurredAt, DateTime.parse('2017-12-26T00:00:00Z'));
    expect(t.createdAt, DateTime.parse('2026-09-27T05:43:00Z'));
  });

  test('a row with no occurred_at falls back to the write date', () {
    // Rows written before 0010, and anything read from an older cache.
    final t = ChamaTransaction.fromJson(row());
    expect(t.occurredAt, t.createdAt);
  });

  test('both dates survive a round trip through the offline cache', () {
    final t = ChamaTransaction.fromJson(row(occurredAt: '2017-12-26T00:00:00Z'));
    final back = ChamaTransaction.fromCacheRow(t.toCacheRow());
    expect(back.occurredAt, t.occurredAt);
    expect(back.createdAt, t.createdAt);
  });

  test('an older cached row without the column still reads', () {
    final cached = Map<String, Object?>.from(
      ChamaTransaction.fromJson(row(occurredAt: '2017-12-26T00:00:00Z')).toCacheRow(),
    )..remove('occurred_at');
    final back = ChamaTransaction.fromCacheRow(cached);
    expect(back.occurredAt, back.createdAt);
  });
}

import 'package:chama360/features/chama/domain/models/share_transfer.dart';
import 'package:chama360/features/reports/domain/models/chama_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final transfer = ShareTransfer(
    id: 't1',
    amount: 2400,
    reason: 'Charity exiting, shares bought by Stella',
    createdAt: DateTime(2026, 10, 2),
    fromMemberId: 'charity',
    fromName: 'Charity Kimathi',
    toMemberId: 'stella',
    toName: 'Stella Murithi',
    performedByName: 'Lawrence Mwiti',
  );

  test('a transfer reads differently from each side', () {
    expect(transfer.isOutgoingFor('charity'), isTrue);
    expect(transfer.isOutgoingFor('stella'), isFalse);
    expect(transfer.signedFor('charity'), -2400);
    expect(transfer.signedFor('stella'), 2400);
  });

  test('it leaves everyone else untouched', () {
    expect(transfer.involves('victor'), isFalse);
    expect(transfer.signedFor('victor'), 0);
  });

  test('holding is what was paid in, adjusted by shares moved', () {
    const gaveAway = MemberContribution(
      memberId: 'charity',
      name: 'Charity Kimathi',
      total: 7200,
      count: 6,
      transfersOut: 2400,
    );
    const received = MemberContribution(
      memberId: 'stella',
      name: 'Stella Murithi',
      total: 0,
      count: 0,
      transfersIn: 2400,
    );

    // What they paid in never changes — that is history.
    expect(gaveAway.total, 7200);
    expect(received.total, 0);
    // What they hold does.
    expect(gaveAway.holding, 4800);
    expect(received.holding, 2400);
    expect(gaveAway.hasTransfers, isTrue);
    expect(received.hasTransfers, isTrue);
  });

  test('the chama is no richer or poorer for a transfer', () {
    const before = [7200.0, 0.0];
    const gaveAway = MemberContribution(
        memberId: 'a', name: 'a', total: 7200, count: 6, transfersOut: 2400);
    const received = MemberContribution(
        memberId: 'b', name: 'b', total: 0, count: 0, transfersIn: 2400);

    expect(gaveAway.holding + received.holding, before[0] + before[1]);
  });

  test('a member with no transfers is unaffected by the new fields', () {
    const plain =
        MemberContribution(memberId: 'm', name: 'm', total: 1200, count: 1);
    expect(plain.holding, 1200);
    expect(plain.hasTransfers, isFalse);
  });
}

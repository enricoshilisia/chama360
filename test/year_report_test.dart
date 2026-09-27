import 'package:chama360/features/reports/domain/models/chama_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// Built around Kamundi Family's real shape: a flat annual subscription,
/// six paid years with gaps, a roster that grew, and two members who have
/// never paid.
void main() {
  ContributionEntry c(String memberId, int year, {bool reversed = false}) =>
      ContributionEntry(
        id: '$memberId-$year',
        memberId: memberId,
        memberName: memberId,
        amount: 1200,
        date: DateTime(year, 12, 26),
        isReversed: reversed,
      );

  MemberContribution m(String id) =>
      MemberContribution(memberId: id, name: id, total: 0, count: 0);

  final report = ChamaReport(
    totalContributions: 0,
    memberCount: 4,
    totalLoansDisbursed: 0,
    totalOutstanding: 0,
    activeLoanCount: 0,
    overdueLoanCount: 0,
    monthly: const [],
    topContributors: const [],
    memberBreakdown: [m('perfect'), m('gap'), m('late'), m('never')],
    entries: [
      // Paid every year.
      c('perfect', 2017), c('perfect', 2018), c('perfect', 2022),
      // Paid, then a long gap, then came back.
      c('gap', 2017), c('gap', 2022),
      // Joined late.
      c('late', 2022),
      // 'never' has nothing at all.
    ],
  );

  test('only years with contributions are columns, oldest first', () {
    expect(report.contributionYears, [2017, 2018, 2022]);
  });

  test('a member who has never paid is still in the grid, with an empty row', () {
    final grid = report.yearTotalsByMember;
    expect(grid.containsKey('never'), isTrue,
        reason: 'dropping them would hide exactly who the report is for');
    expect(grid['never'], isEmpty);
  });

  test('a gap year is absent from that member, not zero-filled', () {
    final grid = report.yearTotalsByMember;
    expect(grid['gap']!.keys.toList()..sort(), [2017, 2022]);
    expect(grid['gap']!.containsKey(2018), isFalse);
  });

  test('turnout counts distinct people, not entries', () {
    expect(report.yearSummary(2017).contributors, 2);
    expect(report.yearSummary(2017).total, 2400);
    expect(report.yearSummary(2018).contributors, 1);
    expect(report.yearSummary(2022).contributors, 3);
  });

  test('a year nobody paid in reports zero rather than throwing', () {
    expect(report.yearSummary(2019).contributors, 0);
    expect(report.yearSummary(2019).total, 0);
  });

  test('reversed contributions count towards nothing', () {
    final withReversal = ChamaReport(
      totalContributions: 0,
      memberCount: 1,
      totalLoansDisbursed: 0,
      totalOutstanding: 0,
      activeLoanCount: 0,
      overdueLoanCount: 0,
      monthly: const [],
      topContributors: const [],
      memberBreakdown: [m('a')],
      entries: [c('a', 2019, reversed: true)],
    );
    expect(withReversal.contributionYears, isEmpty);
    expect(withReversal.yearSummary(2019).contributors, 0);
    expect(withReversal.yearTotalsByMember['a'], isEmpty);
  });
}

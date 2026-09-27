import 'package:chama360/features/reports/data/report_pdf.dart';
import 'package:chama360/features/reports/domain/models/chama_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ContributionEntry c(String memberId, int year) => ContributionEntry(
        id: '$memberId-$year',
        memberId: memberId,
        memberName: memberId,
        amount: 1200,
        date: DateTime(year, 12, 26),
      );

  MemberContribution m(String id, double total, int count) =>
      MemberContribution(memberId: id, name: id, total: total, count: count);

  ChamaReport reportWith({
    required List<MemberContribution> members,
    required List<ContributionEntry> entries,
  }) =>
      ChamaReport(
        totalContributions: entries.fold<double>(0, (s, e) => s + e.amount),
        memberCount: members.length,
        totalLoansDisbursed: 0,
        totalOutstanding: 0,
        activeLoanCount: 0,
        overdueLoanCount: 0,
        monthly: const [],
        topContributors: const [],
        memberBreakdown: members,
        entries: entries,
      );

  test('renders a real PDF for a Kamundi-shaped report', () async {
    final bytes = await ReportPdf.build(
      report: reportWith(
        members: [m('Charity Kimathi', 7200, 6), m('Eric mugambi', 2400, 2), m('Stella Murithi', 0, 0)],
        entries: [
          for (final y in [2017, 2018, 2019, 2022, 2023, 2024]) c('Charity Kimathi', y),
          c('Eric mugambi', 2019),
          c('Eric mugambi', 2024),
        ],
      ),
      chamaName: 'Kamundi Family',
      currency: 'KES',
    );

    // %PDF- is the file signature; a truncated or failed render would not
    // carry it, and an empty document would be a few hundred bytes.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));
  });

  test('a chama with no contributions at all still produces a document', () async {
    final bytes = await ReportPdf.build(
      report: reportWith(members: [m('Nobody', 0, 0)], entries: const []),
      chamaName: 'Empty Chama',
      currency: 'KES',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('a chama with no members at all does not throw', () async {
    final bytes = await ReportPdf.build(
      report: reportWith(members: const [], entries: const []),
      chamaName: 'Brand New',
      currency: 'KES',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('more than twelve years of history still lays out', () async {
    final years = [for (var y = 2005; y <= 2026; y++) y];
    final bytes = await ReportPdf.build(
      report: reportWith(
        members: [m('Long Serving', 1200.0 * years.length, years.length)],
        entries: [for (final y in years) c('Long Serving', y)],
      ),
      chamaName: 'Old Chama',
      currency: 'KES',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}

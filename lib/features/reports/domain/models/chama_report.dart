/// One bucket of the trend chart. Buckets are months for a chama whose
/// history fits in a year or so, and years for one that has been entering
/// several years of back records — a fixed six-month window showed an
/// empty chart to exactly the chamas with the most history.
class MonthlyTotal {
  const MonthlyTotal({
    required this.month,
    required this.total,
    required this.label,
    required this.fullLabel,
  });

  final DateTime month; // normalized to the 1st of the month
  final double total;

  /// Short axis label — 'Jan' for a month, '2023' for a year.
  final String label;

  /// What the tooltip says — 'Jan 2026', or just '2023'.
  final String fullLabel;
}

/// The stretches of time a chairperson actually asks about. Every one of
/// these is computed from the same contribution list, so a chama that has
/// just imported three years of history can see what any of those years
/// came to without a second query.
enum ReportPeriod {
  thisMonth('This month'),
  thisYear('This year'),
  lastYear('Last year'),
  allTime('All time');

  const ReportPeriod(this.label);
  final String label;

  bool contains(DateTime date, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return switch (this) {
      ReportPeriod.thisMonth => date.year == today.year && date.month == today.month,
      ReportPeriod.thisYear => date.year == today.year,
      ReportPeriod.lastYear => date.year == today.year - 1,
      ReportPeriod.allTime => true,
    };
  }
}

/// A member ranked by how much they've contributed in total.
class ContributorTotal {
  const ContributorTotal({required this.name, required this.total});

  final String name;
  final double total;
}

/// A single contribution as it happened: who, how much, when. The full
/// report lists these; the home summary never does.
class ContributionEntry {
  const ContributionEntry({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.date,
    this.notes,
    this.isReversed = false,
    this.reversalReason,
  });

  final String id;
  final String memberId;
  final String memberName;
  final double amount;
  final DateTime date;
  final String? notes;

  /// A reversed contribution still appears in the list — struck through,
  /// with the reason — because hiding a corrected mistake is how a ledger
  /// stops being trustworthy. It counts towards no total.
  final bool isReversed;
  final String? reversalReason;
}

/// A repayment as it happened: who paid back, how much, when. Kept
/// separate from the loan it belongs to, because a loan repaid in six
/// instalments is six events a chairperson may need to account for.
class RepaymentEntry {
  const RepaymentEntry({
    required this.loanId,
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.date,
  });

  final String loanId;
  final String memberId;
  final String memberName;
  final double amount;
  final DateTime date;
}

/// One member's contribution record, for the per-member breakdown.
class MemberContribution {
  const MemberContribution({
    required this.memberId,
    required this.name,
    required this.total,
    required this.count,
    this.lastDate,
  });

  final String memberId;
  final String name;
  final double total;
  final int count;

  /// Null when they've never contributed — which is the point of showing
  /// it. A member with no date is the one to follow up.
  final DateTime? lastDate;
}

/// Everything the dashboard's report section needs, computed once from the
/// chama's full contribution and loan history. See ReportsRepository for
/// how it's assembled.
class ChamaReport {
  const ChamaReport({
    required this.totalContributions,
    required this.memberCount,
    required this.totalLoansDisbursed,
    required this.totalOutstanding,
    required this.activeLoanCount,
    required this.overdueLoanCount,
    required this.monthly,
    required this.topContributors,
    this.trendTitle = 'Contributions by month',
    this.entries = const [],
    this.memberBreakdown = const [],
    this.repayments = const [],
  });

  final double totalContributions;
  final int memberCount;
  final double totalLoansDisbursed;
  final double totalOutstanding;
  final int activeLoanCount;
  final int overdueLoanCount;
  final List<MonthlyTotal> monthly;
  final List<ContributorTotal> topContributors;

  /// Names the period the chart actually covers, since that now depends on
  /// how far back the chama's records go.
  final String trendTitle;

  /// Every contribution, newest first. Only the full report screen reads
  /// these; the home summary works off the aggregates above.
  final List<ContributionEntry> entries;

  /// Every active member, including those who have contributed nothing —
  /// omitting them would hide exactly the people a chairperson is looking
  /// for.
  final List<MemberContribution> memberBreakdown;

  /// Every loan repayment, newest first.
  final List<RepaymentEntry> repayments;

  /// What came in over [period], across the whole chama.
  double totalFor(ReportPeriod period) {
    if (period == ReportPeriod.allTime) return totalContributions;
    final now = DateTime.now();
    return entries
        .where((e) => !e.isReversed && period.contains(e.date, now: now))
        .fold<double>(0, (sum, e) => sum + e.amount);
  }

  /// The same breakdown as [memberBreakdown], narrowed to [period] and
  /// re-ranked. Every active member is still in the list, including those
  /// who put nothing in during that stretch — which for a period view is
  /// the whole question.
  List<MemberContribution> breakdownFor(ReportPeriod period) {
    if (period == ReportPeriod.allTime) return memberBreakdown;

    final now = DateTime.now();
    final totals = <String, double>{};
    final counts = <String, int>{};
    final last = <String, DateTime>{};

    for (final e in entries) {
      if (e.isReversed || !period.contains(e.date, now: now)) continue;
      totals[e.memberId] = (totals[e.memberId] ?? 0) + e.amount;
      counts[e.memberId] = (counts[e.memberId] ?? 0) + 1;
      final seen = last[e.memberId];
      if (seen == null || e.date.isAfter(seen)) last[e.memberId] = e.date;
    }

    final out = [
      for (final m in memberBreakdown)
        MemberContribution(
          memberId: m.memberId,
          name: m.name,
          total: totals[m.memberId] ?? 0,
          count: counts[m.memberId] ?? 0,
          lastDate: last[m.memberId],
        ),
    ]..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
      });
    return out;
  }

  static const empty = ChamaReport(
    totalContributions: 0,
    memberCount: 0,
    totalLoansDisbursed: 0,
    totalOutstanding: 0,
    activeLoanCount: 0,
    overdueLoanCount: 0,
    monthly: [],
    topContributors: [],
  );
}

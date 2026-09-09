/// One month's total contributions — powers the trend chart.
class MonthlyTotal {
  const MonthlyTotal({required this.month, required this.total});

  final DateTime month; // normalized to the 1st of the month
  final double total;
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
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.date,
  });

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
    this.entries = const [],
    this.memberBreakdown = const [],
  });

  final double totalContributions;
  final int memberCount;
  final double totalLoansDisbursed;
  final double totalOutstanding;
  final int activeLoanCount;
  final int overdueLoanCount;
  final List<MonthlyTotal> monthly;
  final List<ContributorTotal> topContributors;

  /// Every contribution, newest first. Only the full report screen reads
  /// these; the home summary works off the aggregates above.
  final List<ContributionEntry> entries;

  /// Every active member, including those who have contributed nothing —
  /// omitting them would hide exactly the people a chairperson is looking
  /// for.
  final List<MemberContribution> memberBreakdown;

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

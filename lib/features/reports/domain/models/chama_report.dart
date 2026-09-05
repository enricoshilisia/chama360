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
  });

  final double totalContributions;
  final int memberCount;
  final double totalLoansDisbursed;
  final double totalOutstanding;
  final int activeLoanCount;
  final int overdueLoanCount;
  final List<MonthlyTotal> monthly;
  final List<ContributorTotal> topContributors;

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

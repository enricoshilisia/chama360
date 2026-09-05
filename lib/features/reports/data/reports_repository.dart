import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/chama_report.dart';

/// Builds the dashboard's report from the chama's full contribution and
/// loan history. Aggregation happens client-side — fine at the scale a
/// single chama operates at, and avoids a database view for something this
/// simple. If a chama's history grows large enough for this to matter,
/// move these sums into a Postgres view/RPC instead of changing the shape
/// callers see here.
class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  Future<ChamaReport> buildReport(String chamaId) async {
    final results = await Future.wait([
      _client
          .from('contributions')
          .select('amount, contribution_date, member_id, chama_members(user_id, managed_full_name:full_name, profiles(full_name, email))')
          .eq('chama_id', chamaId)
          .eq('status', 'completed'),
      _client.from('loans').select('principal, total_due, amount_repaid, status, due_date').eq('chama_id', chamaId),
      _client.from('chama_members').select('id').eq('chama_id', chamaId).eq('status', 'active'),
    ]);

    final contributions = (results[0] as List).cast<Map<String, dynamic>>();
    final loans = (results[1] as List).cast<Map<String, dynamic>>();
    final members = (results[2] as List).cast<Map<String, dynamic>>();

    final totalContributions = contributions.fold<double>(
      0,
      (sum, c) => sum + (c['amount'] as num).toDouble(),
    );

    // Monthly totals for the last 6 months, oldest first.
    final now = DateTime.now();
    final monthKeys = List.generate(6, (i) {
      final m = DateTime(now.year, now.month - (5 - i), 1);
      return m;
    });
    final monthlySums = {for (final m in monthKeys) m: 0.0};
    for (final c in contributions) {
      final date = DateTime.parse(c['contribution_date'] as String);
      final key = DateTime(date.year, date.month, 1);
      if (monthlySums.containsKey(key)) {
        monthlySums[key] = monthlySums[key]! + (c['amount'] as num).toDouble();
      }
    }
    final monthly = monthKeys.map((m) => MonthlyTotal(month: m, total: monthlySums[m]!)).toList();

    // Per-member totals, ranked.
    final perMember = <String, double>{};
    final nameByMember = <String, String>{};
    for (final c in contributions) {
      final memberId = c['member_id'] as String;
      final memberJoin = c['chama_members'] as Map<String, dynamic>?;
      final profile = memberJoin?['profiles'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.trim();
      final resolvedName = (name != null && name.isNotEmpty)
          ? name
          : (memberJoin?['managed_full_name'] as String? ??
              profile?['email'] as String? ??
              'Member');
      nameByMember[memberId] = resolvedName;
      perMember[memberId] = (perMember[memberId] ?? 0) + (c['amount'] as num).toDouble();
    }
    final topContributors = perMember.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Loan book.
    double totalLoansDisbursed = 0;
    double totalOutstanding = 0;
    int activeLoanCount = 0;
    int overdueLoanCount = 0;
    for (final l in loans) {
      final status = l['status'] as String;
      if (status == 'active' || status == 'repaid' || status == 'defaulted') {
        totalLoansDisbursed += (l['principal'] as num).toDouble();
      }
      if (status == 'active') {
        activeLoanCount++;
        final totalDue = (l['total_due'] as num?)?.toDouble() ?? 0;
        final repaid = (l['amount_repaid'] as num?)?.toDouble() ?? 0;
        totalOutstanding += (totalDue - repaid).clamp(0, double.infinity);

        final dueDate = l['due_date'] as String?;
        if (dueDate != null && DateTime.parse(dueDate).isBefore(DateTime.now())) {
          overdueLoanCount++;
        }
      }
    }

    return ChamaReport(
      totalContributions: totalContributions,
      memberCount: members.length,
      totalLoansDisbursed: totalLoansDisbursed,
      totalOutstanding: totalOutstanding,
      activeLoanCount: activeLoanCount,
      overdueLoanCount: overdueLoanCount,
      monthly: monthly,
      topContributors: [
        for (final e in topContributors.take(5))
          ContributorTotal(name: nameByMember[e.key] ?? 'Member', total: e.value),
      ],
    );
  }
}

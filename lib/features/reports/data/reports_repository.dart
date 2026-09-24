import 'package:intl/intl.dart';
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
    final results = await Future.wait<dynamic>([
      // Both of these go through SECURITY DEFINER functions rather than
      // reading the tables directly: they resolve display names the same
      // way everywhere, they return the contribution's own id (needed to
      // reverse one), and they apply the own-or-admin rule in one place
      // instead of relying on an embedded resource picking up the right
      // RLS policy.
      _client.rpc('chama_contributions', params: {'p_chama_id': chamaId}),
      _client.from('loans').select('principal, total_due, amount_repaid, status, due_date').eq('chama_id', chamaId),
      _client.rpc('chama_roster', params: {'p_chama_id': chamaId}),
      // Repayments hang off loans, so the chama filter has to be applied
      // through the join — !inner keeps rows whose loan is in this chama
      // and drops the rest, rather than returning every repayment ever.
      _client
          .from('loan_repayments')
          .select('amount, repaid_at, loan_id, '
              'loans!inner(chama_id, member_id, '
              'chama_members(managed_full_name:full_name, profiles(full_name, email)))')
          .eq('loans.chama_id', chamaId)
          .order('repaid_at', ascending: false),
    ]);

    final contributionRows = (results[0] as List).cast<Map<String, dynamic>>();
    final loans = (results[1] as List).cast<Map<String, dynamic>>();
    final members = (results[2] as List).cast<Map<String, dynamic>>();
    final repaymentRows = (results[3] as List).cast<Map<String, dynamic>>();

    // Every contribution as a row, newest first — reversed ones included,
    // flagged, so the list shows the correction rather than quietly
    // dropping the entry. Only the live ones are summed.
    final entries = <ContributionEntry>[];
    final nameByMember = <String, String>{};
    for (final c in contributionRows) {
      final memberId = c['member_id'] as String;
      nameByMember[memberId] = c['member_name'] as String? ?? 'Member';
      entries.add(ContributionEntry(
        id: c['id'] as String,
        memberId: memberId,
        memberName: nameByMember[memberId]!,
        amount: (c['amount'] as num).toDouble(),
        date: DateTime.parse(c['contribution_date'] as String),
        notes: c['notes'] as String?,
        isReversed: c['status'] == 'reversed',
        reversalReason: c['reversal_reason'] as String?,
      ));
    }
    entries.sort((a, b) => b.date.compareTo(a.date));

    final live = entries.where((e) => !e.isReversed).toList();

    final totalContributions = live.fold<double>(0, (sum, e) => sum + e.amount);

    final trend = _buildTrend(live);
    final monthly = trend.buckets;
    final trendTitle =
        trend.yearly ? 'Contributions by year' : 'Contributions by month';

    // Per-member totals, ranked.
    final perMember = <String, double>{};
    for (final e in live) {
      perMember[e.memberId] = (perMember[e.memberId] ?? 0) + e.amount;
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

    // Per-member totals across *all* active members, so someone who has
    // never contributed still appears — with zero, which is the useful part.
    final lastByMember = <String, DateTime>{};
    final countByMember = <String, int>{};
    for (final e in live) {
      countByMember[e.memberId] = (countByMember[e.memberId] ?? 0) + 1;
      final seen = lastByMember[e.memberId];
      if (seen == null || e.date.isAfter(seen)) lastByMember[e.memberId] = e.date;
    }

    final breakdown = <MemberContribution>[];
    for (final m in members) {
      final id = m['id'] as String;
      breakdown.add(MemberContribution(
        memberId: id,
        name: m['display_name'] as String? ?? nameByMember[id] ?? 'Member',
        total: perMember[id] ?? 0,
        count: countByMember[id] ?? 0,
        lastDate: lastByMember[id],
      ));
    }
    breakdown.sort((a, b) {
      final byTotal = b.total.compareTo(a.total);
      // Everyone on zero would otherwise come back in whatever order the
      // roster happened to arrive in; alphabetical makes the tail of the
      // list something a chairperson can actually scan for a name.
      return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
    });

    final repayments = <RepaymentEntry>[];
    for (final r in repaymentRows) {
      final loan = r['loans'] as Map<String, dynamic>?;
      final memberJoin = loan?['chama_members'] as Map<String, dynamic>?;
      final profile = memberJoin?['profiles'] as Map<String, dynamic>?;
      final fromProfile = (profile?['full_name'] as String?)?.trim();
      final memberId = loan?['member_id'] as String? ?? '';
      repayments.add(RepaymentEntry(
        loanId: r['loan_id'] as String,
        memberId: memberId,
        memberName: (fromProfile != null && fromProfile.isNotEmpty)
            ? fromProfile
            : (memberJoin?['managed_full_name'] as String? ??
                profile?['email'] as String? ??
                nameByMember[memberId] ??
                'Member'),
        amount: (r['amount'] as num).toDouble(),
        date: DateTime.parse(r['repaid_at'] as String),
      ));
    }

    return ChamaReport(
      entries: entries,
      memberBreakdown: breakdown,
      repayments: repayments,
      totalContributions: totalContributions,
      memberCount: members.length,
      totalLoansDisbursed: totalLoansDisbursed,
      totalOutstanding: totalOutstanding,
      activeLoanCount: activeLoanCount,
      overdueLoanCount: overdueLoanCount,
      monthly: monthly,
      trendTitle: trendTitle,
      topContributors: [
        for (final e in topContributors.take(5))
          ContributorTotal(name: nameByMember[e.key] ?? 'Member', total: e.value),
      ],
    );
  }

  /// Chooses a window that actually contains the chama's contributions.
  ///
  /// This used to be a hard-coded "last 6 months", which meant a chama
  /// entering years of paper records saw an empty chart and concluded the
  /// report was broken. The window now starts at the earliest contribution
  /// and runs to today, in monthly buckets while that fits comfortably on
  /// an axis and yearly ones once it doesn't.
  static ({List<MonthlyTotal> buckets, bool yearly}) _buildTrend(
      List<ContributionEntry> live) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);

    if (live.isEmpty) {
      return (
        buckets: [
          for (var i = 5; i >= 0; i--)
            _bucket(DateTime(now.year, now.month - i, 1), 0, yearly: false),
        ],
        yearly: false,
      );
    }

    var earliest = live.first.date;
    var latest = live.first.date;
    for (final e in live) {
      if (e.date.isBefore(earliest)) earliest = e.date;
      if (e.date.isAfter(latest)) latest = e.date;
    }

    final start = DateTime(earliest.year, earliest.month, 1);
    final end = DateTime(latest.year, latest.month, 1).isAfter(thisMonth)
        ? DateTime(latest.year, latest.month, 1)
        : thisMonth;

    final months = (end.year - start.year) * 12 + (end.month - start.month) + 1;

    if (months <= 12) {
      final sums = <DateTime, double>{
        for (var i = 0; i < months; i++) DateTime(start.year, start.month + i, 1): 0.0,
      };
      for (final e in live) {
        final key = DateTime(e.date.year, e.date.month, 1);
        if (sums.containsKey(key)) sums[key] = sums[key]! + e.amount;
      }
      return (
        buckets: [
          for (final entry in sums.entries)
            _bucket(entry.key, entry.value, yearly: false),
        ],
        yearly: false,
      );
    }

    // Long history: one bar a year, most recent 12 at most.
    final firstYear = months > 12 * 12 ? end.year - 11 : start.year;
    final sums = <int, double>{
      for (var y = firstYear; y <= end.year; y++) y: 0.0,
    };
    for (final e in live) {
      if (sums.containsKey(e.date.year)) {
        sums[e.date.year] = sums[e.date.year]! + e.amount;
      }
    }
    return (
      buckets: [
        for (final entry in sums.entries)
          _bucket(DateTime(entry.key, 1, 1), entry.value, yearly: true),
      ],
      yearly: true,
    );
  }

  static MonthlyTotal _bucket(DateTime month, double total, {required bool yearly}) {
    return MonthlyTotal(
      month: month,
      total: total,
      label: yearly ? '${month.year}' : DateFormat('MMM').format(month),
      fullLabel:
          yearly ? '${month.year}' : DateFormat('MMM yyyy').format(month),
    );
  }
}

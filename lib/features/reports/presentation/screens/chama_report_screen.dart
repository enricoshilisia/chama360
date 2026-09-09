import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/constants/chama_roles.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../../loans/domain/models/loan.dart';
import '../../../loans/presentation/providers/loans_providers.dart';
import '../../domain/models/chama_report.dart';
import '../providers/reports_providers.dart';

/// The chama's full record, as opposed to the home screen's overview:
/// every contribution, who made it and when, each member's standing, and
/// the loan book. Home answers "how are we doing"; this answers "show me
/// the numbers".
class ChamaReportScreen extends ConsumerStatefulWidget {
  const ChamaReportScreen({super.key, required this.chamaId});

  final String chamaId;

  @override
  ConsumerState<ChamaReportScreen> createState() => _ChamaReportScreenState();
}

class _ChamaReportScreenState extends ConsumerState<ChamaReportScreen>
    with TickerProviderStateMixin {
  TabController? _tabs;
  int _tabCount = 0;

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  /// Rebuilt when the viewer's role resolves, since a member gets one tab
  /// and an admin gets four.
  TabController _controllerFor(int count) {
    if (_tabs == null || _tabCount != count) {
      _tabs?.dispose();
      _tabs = TabController(length: count, vsync: this);
      _tabCount = count;
    }
    return _tabs!;
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(chamaReportProvider(widget.chamaId));
    final chama = ref.watch(chamaByIdProvider(widget.chamaId));
    final currency = chama?.currency ?? 'KES';
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);
    final controller = _controllerFor(isAdmin ? 4 : 1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: isAdmin
            ? TabBar(
                controller: controller,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Members'),
                  Tab(text: 'Contributions'),
                  Tab(text: 'Borrowing'),
                ],
              )
            : null,
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
        ),
        data: (report) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(chamaReportProvider(widget.chamaId)),
          child: TabBarView(
            controller: controller,
            children: [
              _OverviewTab(
                report: report,
                currency: currency,
                isAdmin: isAdmin,
                chamaId: widget.chamaId,
              ),
              if (isAdmin) ...[
                _MembersTab(
                  report: report,
                  currency: currency,
                  chamaId: widget.chamaId,
                ),
                _ContributionsTab(report: report, currency: currency),
                _BorrowingTab(
                  chamaId: widget.chamaId,
                  currency: currency,
                  report: report,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Overview

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({
    required this.report,
    required this.currency,
    required this.chamaId,
    this.isAdmin = true,
  });

  final ChamaReport report;
  final String currency;
  final String chamaId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // For a member these figures come from the database, since their own
    // report rows only cover themselves.
    final totals = isAdmin ? null : ref.watch(chamaTotalsProvider(chamaId)).value;
    final pooled = totals?.totalContributions ?? report.totalContributions;
    final memberCount = totals?.memberCount ?? report.memberCount;
    final outstanding = totals?.totalOutstanding ?? report.totalOutstanding;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: isAdmin ? 'Total contributed' : 'Pooled contributions',
                value: formatMoney(pooled, currency: currency),
                icon: Icons.savings_rounded,
                color: AppColors.seedDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                label: 'Members',
                value: '$memberCount',
                icon: Icons.groups_rounded,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Loans disbursed',
                value: formatMoney(report.totalLoansDisbursed, currency: currency),
                icon: Icons.call_made_rounded,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                label: 'Still owed',
                value: formatMoney(outstanding, currency: currency),
                icon: Icons.request_quote_outlined,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ),
        if (report.overdueLoanCount > 0) ...[
          const SizedBox(height: 10),
          GlassContainer(
            padding: const EdgeInsets.all(14),
            borderRadius: 16,
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${report.overdueLoanCount} loan${report.overdueLoanCount == 1 ? '' : 's'} '
                    'past the due date',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text('Contributions by month',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        GlassContainer(
          padding: const EdgeInsets.fromLTRB(10, 20, 14, 8),
          child: SizedBox(
            height: 190,
            child: report.monthly.any((m) => m.total > 0)
                ? _MonthlyChart(monthly: report.monthly, currency: currency)
                : Center(
                    child: Text('Nothing recorded yet',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ),
          ),
        ),
        if (!isAdmin) ...[
          const SizedBox(height: 22),
          GlassContainer(
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These are the chama\'s totals. Individual members\' '
                    'contributions are only visible to the chairperson.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (isAdmin) ...[
        const SizedBox(height: 22),
        Text('Top contributors',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (report.topContributors.isEmpty)
          GlassContainer(
            child: Text('No contributions recorded yet',
                style: TextStyle(color: Colors.grey.shade600)),
          )
        else
          GlassContainer(
            child: Column(
              children: [
                for (var i = 0; i < report.topContributors.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(report.topContributors[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        formatMoney(report.topContributors[i].total, currency: currency),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ----------------------------------------------------------------- Members

class _MembersTab extends StatelessWidget {
  const _MembersTab({
    required this.report,
    required this.currency,
    required this.chamaId,
  });

  final ChamaReport report;
  final String currency;
  final String chamaId;

  @override
  Widget build(BuildContext context) {
    if (report.memberBreakdown.isEmpty) {
      return Center(
        child: Text('No members yet', style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    // Bars are drawn relative to the highest contributor, so the column
    // reads as a ranking at a glance rather than as absolute amounts.
    final highest = report.memberBreakdown
        .map((m) => m.total)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
      itemCount: report.memberBreakdown.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final m = report.memberBreakdown[i];
        final fraction = highest <= 0 ? 0.0 : (m.total / highest).clamp(0.0, 1.0);
        final primary = Theme.of(context).colorScheme.primary;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/chamas/$chamaId/members/${m.memberId}'),
          child: GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(formatMoney(m.total, currency: currency),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: primary.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation(primary),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  m.count == 0
                      ? 'No contributions yet'
                      : '${m.count} contribution${m.count == 1 ? '' : 's'}'
                          '${m.lastDate == null ? '' : ' · last on ${DateFormat('d MMM yyyy').format(m.lastDate!)}'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: m.count == 0 ? Colors.orange.shade800 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------- Contributions

class _ContributionsTab extends StatelessWidget {
  const _ContributionsTab({required this.report, required this.currency});

  final ChamaReport report;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (report.entries.isEmpty) {
      return Center(
        child: Text('No contributions recorded yet',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    // Grouped by month so a long history stays navigable, with each month's
    // total in its header — the figure a chairperson is usually after.
    final groups = <String, List<ContributionEntry>>{};
    for (final e in report.entries) {
      final key = DateFormat('MMMM yyyy').format(e.date);
      groups.putIfAbsent(key, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Text(entry.key,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  formatMoney(
                    entry.value.fold<double>(0, (sum, e) => sum + e.amount),
                    currency: currency,
                  ),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          for (final e in entry.value)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.green.withValues(alpha: 0.15),
                  child: const Icon(Icons.savings_rounded, size: 16, color: Colors.green),
                ),
                title: Text(e.memberName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('EEE, d MMM yyyy').format(e.date),
                    style: const TextStyle(fontSize: 11.5)),
                trailing: Text(
                  formatMoney(e.amount, currency: currency),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({required this.monthly, required this.currency});

  final List<MonthlyTotal> monthly;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final maxVal = monthly.map((m) => m.total).fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal * 1.25;
    final primary = Theme.of(context).colorScheme.primary;

    return BarChart(
      BarChartData(
        maxY: safeMax,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${DateFormat('MMM yyyy').format(monthly[group.x].month)}\n'
              '${formatMoney(rod.toY, currency: currency)}',
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= monthly.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM').format(monthly[i].month),
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < monthly.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: monthly[i].total,
                  color: primary,
                  width: 20,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
        ],
      ),
    );
  }
}


// --------------------------------------------------------------- Borrowing

/// Every loan the chama has issued, newest first, with the outstanding
/// balance made obvious. Overdue ones are pulled to the top because they're
/// the ones needing a conversation.
class _BorrowingTab extends ConsumerWidget {
  const _BorrowingTab({
    required this.chamaId,
    required this.currency,
    required this.report,
  });

  final String chamaId;
  final String currency;
  final ChamaReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(chamaLoansProvider(chamaId));

    return loansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
      ),
      data: (loans) {
        if (loans.isEmpty) {
          return Center(
            child: Text('No loans issued yet',
                style: TextStyle(color: Colors.grey.shade600)),
          );
        }

        final now = DateTime.now();
        bool overdue(Loan l) =>
            l.status == 'active' && l.dueDate != null && l.dueDate!.isBefore(now);

        final sorted = [...loans]..sort((a, b) {
            if (overdue(a) != overdue(b)) return overdue(a) ? -1 : 1;
            if ((a.status == 'active') != (b.status == 'active')) {
              return a.status == 'active' ? -1 : 1;
            }
            return b.createdAt.compareTo(a.createdAt);
          });

        final disbursed = loans
            .where((l) => l.status != 'pending' && l.status != 'rejected')
            .fold<double>(0, (sum, l) => sum + l.principal);
        final outstanding = loans
            .where((l) => l.status == 'active')
            .fold<double>(0, (sum, l) => sum + l.outstanding);
        final repaid = loans.fold<double>(0, (sum, l) => sum + l.amountRepaid);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Disbursed',
                    value: formatMoney(disbursed, currency: currency),
                    icon: Icons.call_made_rounded,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                    label: 'Repaid',
                    value: formatMoney(repaid, currency: currency),
                    icon: Icons.call_received_rounded,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Stat(
              label: 'Still owed to the chama',
              value: formatMoney(outstanding, currency: currency),
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.orange.shade700,
            ),
            const SizedBox(height: 18),
            Text('Loans',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final loan in sorted) ...[
              _LoanRow(
                loan: loan,
                currency: currency,
                isOverdue: overdue(loan),
                onTap: () => context.push('/chamas/$chamaId/loans/${loan.id}'),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
            Text('Repayments',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (report.repayments.isEmpty)
              GlassContainer(
                child: Text('Nothing repaid yet',
                    style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              for (final r in report.repayments)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    onTap: () => context.push('/chamas/$chamaId/loans/${r.loanId}'),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.green.withValues(alpha: 0.15),
                      child: const Icon(Icons.call_received_rounded,
                          size: 16, color: Colors.green),
                    ),
                    title: Text(r.memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(DateFormat('EEE, d MMM yyyy').format(r.date),
                        style: const TextStyle(fontSize: 11.5)),
                    trailing: Text(formatMoney(r.amount, currency: currency),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({
    required this.loan,
    required this.currency,
    required this.isOverdue,
    required this.onTap,
  });

  final Loan loan;
  final String currency;
  final bool isOverdue;
  final VoidCallback onTap;

  Color _statusColor() {
    if (isOverdue) return Colors.red;
    switch (loan.status) {
      case 'active':
        return Colors.blue;
      case 'repaid':
        return Colors.green;
      case 'rejected':
      case 'defaulted':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    final progress = loan.totalDue <= 0
        ? 0.0
        : (loan.amountRepaid / loan.totalDue).clamp(0.0, 1.0);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(loan.borrowerName ?? (loan.isMine ? 'You' : 'Member'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    isOverdue ? 'OVERDUE' : loan.status.toUpperCase(),
                    style: TextStyle(
                        color: color, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Figure(label: 'Borrowed', value: formatMoney(loan.principal, currency: currency)),
                const SizedBox(width: 18),
                _Figure(label: 'Repaid', value: formatMoney(loan.amountRepaid, currency: currency)),
                const SizedBox(width: 18),
                _Figure(
                  label: 'Owing',
                  value: formatMoney(loan.outstanding, currency: currency),
                  emphasis: loan.outstanding > 0,
                ),
              ],
            ),
            if (loan.status == 'active') ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
            if (loan.dueDate != null) ...[
              const SizedBox(height: 8),
              Text(
                '${isOverdue ? 'Was due' : 'Due'} ${DateFormat('d MMM yyyy').format(loan.dueDate!)}',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isOverdue ? Colors.red : Colors.grey.shade600,
                  fontWeight: isOverdue ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
              color: emphasis ? Colors.orange.shade800 : null,
            )),
      ],
    );
  }
}

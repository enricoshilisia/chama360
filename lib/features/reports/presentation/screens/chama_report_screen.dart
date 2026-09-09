import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
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
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(chamaReportProvider(widget.chamaId));
    final chama = ref.watch(chamaByIdProvider(widget.chamaId));
    final currency = chama?.currency ?? 'KES';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Members'),
            Tab(text: 'Contributions'),
          ],
        ),
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $e')),
        ),
        data: (report) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(chamaReportProvider(widget.chamaId)),
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(report: report, currency: currency),
              _MembersTab(
                report: report,
                currency: currency,
                chamaId: widget.chamaId,
              ),
              _ContributionsTab(report: report, currency: currency),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Overview

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.report, required this.currency});

  final ChamaReport report;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Total contributed',
                value: formatMoney(report.totalContributions, currency: currency),
                icon: Icons.savings_rounded,
                color: AppColors.seedDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Stat(
                label: 'Members',
                value: '${report.memberCount}',
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
                value: formatMoney(report.totalOutstanding, currency: currency),
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

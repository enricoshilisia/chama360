import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/chama_roles.dart';
import '../../../../core/services/privacy_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../chama/presentation/providers/chama_providers.dart';
import '../../domain/models/chama_report.dart';
import '../providers/reports_providers.dart';

/// The dashboard's "Reports" block — fund overview, the contribution trend
/// over whatever period the chama's records actually cover, top
/// contributors, and loan book health. Everything a chairperson
/// would want to glance at without leaving the home screen. [visible]
/// mirrors the hero balance card's peek toggle so every money figure here
/// hides consistently, not just the top-line total.
class ChamaReportSection extends ConsumerWidget {
  const ChamaReportSection({super.key, required this.chamaId, required this.visible});

  final String chamaId;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chama = ref.watch(chamaByIdProvider(chamaId));
    final isAdmin = chama != null && ChamaRole.isAdmin(chama.role);

    // A member's own report query only returns their own contributions,
    // so summing it here would label their personal total as the chama's.
    // The pooled figures come from the database instead.
    if (!isAdmin) return _MemberSummary(chamaId: chamaId, visible: visible);

    final reportAsync = ref.watch(chamaReportProvider(chamaId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Chama report',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () => context.push('/chamas/$chamaId/reports'),
              child: const Text('Full report'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        reportAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load report: $e'),
          data: (report) => _ReportBody(report: report, visible: visible),
        ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.visible});

  final ChamaReport report;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (report.totalContributions == 0 && report.totalLoansDisbursed == 0) {
      return GlassContainer(
        child: Text(
          'Reports fill in once contributions start coming in.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    // The hero card above already carries the chama's position — what it
    // holds, what is out on loan, how many members. Repeating that here
    // wasted the one block with room to answer the question that follows
    // it: how much has been coming in, and when.
    final periods = ReportPeriod.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var col = 0; col < 2; col++) ...[
                if (col > 0) const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: periods[row * 2 + col].label,
                    value: maskable(
                        formatMoney(report.totalFor(periods[row * 2 + col])), visible),
                    icon: switch (periods[row * 2 + col]) {
                      ReportPeriod.thisMonth => Icons.today_rounded,
                      ReportPeriod.thisYear => Icons.calendar_month_rounded,
                      ReportPeriod.lastYear => Icons.history_rounded,
                      ReportPeriod.allTime => Icons.savings_rounded,
                    },
                    color: periods[row * 2 + col] == ReportPeriod.allTime
                        ? AppColors.seedDark
                        : AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ],
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
                    '${report.overdueLoanCount} loan'
                    '${report.overdueLoanCount == 1 ? '' : 's'} past the due date',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (report.monthly.any((m) => m.total > 0)) ...[
          const SizedBox(height: 18),
          Text(report.trendTitle,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          GlassContainer(
            padding: const EdgeInsets.fromLTRB(12, 20, 16, 8),
            child: SizedBox(
              height: 160,
              child: visible
                  ? _MonthlyBarChart(monthly: report.monthly)
                  : Center(
                      child: Text('Hidden — tap the eye icon above to reveal',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                    ),
            ),
          ),
        ],
        if (report.topContributors.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Top contributors',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          GlassContainer(
            child: Column(
              children: [
                for (var i = 0; i < report.topContributors.length; i++) ...[
                  if (i > 0) const Divider(height: 20),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(report.topContributors[i].name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(maskable(formatMoney(report.topContributors[i].total), visible),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
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

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.monthly});

  final List<MonthlyTotal> monthly;

  @override
  Widget build(BuildContext context) {
    final maxVal = monthly.map((m) => m.total).fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal * 1.2;
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
              '${monthly[group.x].fullLabel}\n${formatMoney(rod.toY)}',
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
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= monthly.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    monthly[i].label,
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
                  width: 18,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ),
        ],
      ),
    );
  }
}


/// A member's own record, over the stretches they are likely to ask
/// about. The chama's pooled position is on the hero card above, which
/// gets it from chama_totals(); this block is the one place a member sees
/// their own figures, and it never shows anyone else's.
class _MemberSummary extends ConsumerWidget {
  const _MemberSummary({required this.chamaId, required this.visible});

  final String chamaId;
  final bool visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A member's report query only returns their own contributions, so
    // these totals are theirs — which is exactly what is wanted here.
    final reportAsync = ref.watch(chamaReportProvider(chamaId));
    final periods = ReportPeriod.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What you have put in',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        reportAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load your contributions: $e'),
          data: (report) => Column(
            children: [
              for (var row = 0; row < 2; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          label: periods[row * 2 + col].label,
                          value: maskable(
                              formatMoney(report.totalFor(periods[row * 2 + col])),
                              visible),
                          icon: switch (periods[row * 2 + col]) {
                            ReportPeriod.thisMonth => Icons.today_rounded,
                            ReportPeriod.thisYear => Icons.calendar_month_rounded,
                            ReportPeriod.lastYear => Icons.history_rounded,
                            ReportPeriod.allTime => Icons.savings_rounded,
                          },
                          color: periods[row * 2 + col] == ReportPeriod.allTime
                              ? AppColors.seedDark
                              : AppColors.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if (report.monthly.any((m) => m.total > 0)) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(report.trendTitle,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.grey.shade700)),
                ),
                const SizedBox(height: 10),
                GlassContainer(
                  padding: const EdgeInsets.fromLTRB(12, 20, 16, 8),
                  child: SizedBox(
                    height: 160,
                    child: visible
                        ? _MonthlyBarChart(monthly: report.monthly)
                        : Center(
                            child: Text('Hidden — tap the eye icon above to reveal',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 12)),
                          ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              GlassContainer(
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'The chama\'s totals are on the card above. What each '
                        'member individually put in is only visible to the '
                        'chairperson.',
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

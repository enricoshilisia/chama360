import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/chama_report.dart';
import '../providers/reports_providers.dart';

/// The dashboard's "Reports" block — fund overview, a 6-month contribution
/// trend, top contributors, and loan book health. Everything a chairperson
/// would want to glance at without leaving the home screen.
class ChamaReportSection extends ConsumerWidget {
  const ChamaReportSection({super.key, required this.chamaId});

  final String chamaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(chamaReportProvider(chamaId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chama report',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        reportAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load report: $e'),
          data: (report) => _ReportBody(report: report),
        ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final ChamaReport report;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Total contributed',
                value: formatMoney(report.totalContributions),
                icon: Icons.savings_rounded,
                color: AppColors.seedDark,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
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
              child: _StatTile(
                label: 'Loans outstanding',
                value: formatMoney(report.totalOutstanding),
                icon: Icons.request_quote_outlined,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: report.overdueLoanCount > 0 ? 'Overdue loans' : 'Active loans',
                value: '${report.overdueLoanCount > 0 ? report.overdueLoanCount : report.activeLoanCount}',
                icon: report.overdueLoanCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.call_made_rounded,
                color: report.overdueLoanCount > 0 ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
        if (report.monthly.any((m) => m.total > 0)) ...[
          const SizedBox(height: 18),
          Text('Contributions, last 6 months',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 10),
          GlassContainer(
            padding: const EdgeInsets.fromLTRB(12, 20, 16, 8),
            child: SizedBox(height: 160, child: _MonthlyBarChart(monthly: report.monthly)),
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
                      Text(formatMoney(report.topContributors[i].total),
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
              formatMoney(rod.toY),
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

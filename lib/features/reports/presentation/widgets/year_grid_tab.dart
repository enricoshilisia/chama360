import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/layout.dart';
import '../../../../core/utils/currency.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/models/chama_report.dart';

/// Who paid, and in which year.
///
/// A chama that collects once a year is asking a different question from
/// one that collects monthly. "How much came in" rises just because the
/// roster grew; what a chairperson actually needs at the AGM is the
/// register — every member, every year, paid or not. Amount rankings are
/// close to meaningless where everybody pays the same subscription, so
/// this leads with counts and participation instead.
///
/// Members who have never contributed are in the list with an empty row.
/// That is the point of the report, not an omission.
class YearGridTab extends StatelessWidget {
  const YearGridTab({
    super.key,
    required this.report,
    required this.currency,
    required this.chamaId,
  });

  final ChamaReport report;
  final String currency;
  final String chamaId;

  @override
  Widget build(BuildContext context) {
    final years = report.contributionYears;

    if (years.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nothing recorded yet. Once contributions come in, this shows who '
            'paid in which year.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
        ),
      );
    }

    final byMember = report.yearTotalsByMember;
    final memberCount = report.memberBreakdown.length;

    // Most complete records first, then alphabetical — the same order the
    // Members tab uses, so the two read consistently.
    final members = [...report.memberBreakdown]..sort((a, b) {
        final aYears = byMember[a.memberId]?.length ?? 0;
        final bYears = byMember[b.memberId]?.length ?? 0;
        return aYears != bYears ? bYears.compareTo(aYears) : a.name.compareTo(b.name);
      });

    final neverPaid = members
        .where((m) => (byMember[m.memberId]?.isEmpty ?? true))
        .length;

    // Years the chama skipped entirely sit between the ones it didn't.
    // Saying so beats letting a reader assume the data is missing.
    final gaps = <int>[
      for (var y = years.first; y <= years.last; y++)
        if (!years.contains(y)) y,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kShellBottomInset),
      children: [
        Text('Turnout by year',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'How many of the chama\'s $memberCount members paid, each year.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        GlassContainer(
          child: Column(
            children: [
              for (var i = years.length - 1; i >= 0; i--) ...[
                if (i < years.length - 1) const Divider(height: 20),
                _YearRow(
                  year: years[i],
                  summary: report.yearSummary(years[i]),
                  memberCount: memberCount,
                  currency: currency,
                ),
              ],
            ],
          ),
        ),
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Note(
            icon: Icons.event_busy_outlined,
            text: 'Nothing is recorded for '
                '${gaps.length == 1 ? gaps.first.toString() : gaps.join(', ')}. '
                'Either the chama collected nothing those years, or they have '
                'not been entered yet.',
          ),
        ],
        const SizedBox(height: 26),
        Text('The register',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          neverPaid == 0
              ? 'Every member has contributed at least once.'
              : '$neverPaid member${neverPaid == 1 ? ' has' : 's have'} never contributed.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        for (final m in members) ...[
          _MemberYears(
            name: m.name,
            years: years,
            paid: byMember[m.memberId] ?? const {},
            currency: currency,
            onTap: () => context.push('/chamas/$chamaId/members/${m.memberId}'),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.year,
    required this.summary,
    required this.memberCount,
    required this.currency,
  });

  final int year;
  final ({int contributors, double total}) summary;
  final int memberCount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final fraction = memberCount == 0 ? 0.0 : summary.contributors / memberCount;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 46,
              child: Text('$year',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            Expanded(
              child: Text(
                '${summary.contributors} of $memberCount'
                '${memberCount == 0 ? '' : '  ·  ${(fraction * 100).round()}%'}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
              ),
            ),
            Text(formatMoney(summary.total, currency: currency),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: primary.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation(primary),
          ),
        ),
      ],
    );
  }
}

/// One member's years as a row of chips — filled where they paid, hollow
/// where they didn't. A wrapping row rather than a wide table, so it reads
/// the same on a phone as on a desktop without horizontal scrolling.
class _MemberYears extends StatelessWidget {
  const _MemberYears({
    required this.name,
    required this.years,
    required this.paid,
    required this.currency,
    required this.onTap,
  });

  final String name;
  final List<int> years;
  final Map<int, double> paid;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final total = paid.values.fold<double>(0, (sum, v) => sum + v);
    final complete = paid.length == years.length;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (complete)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.verified_rounded, size: 16, color: primary),
                  ),
                Text(formatMoney(total, currency: currency),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              paid.isEmpty
                  ? 'No contributions on record'
                  : '${paid.length} of ${years.length} year'
                      '${years.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11.5,
                color: paid.isEmpty ? Colors.orange.shade800 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final year in years)
                  _YearChip(
                    year: year,
                    amount: paid[year],
                    currency: currency,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  const _YearChip({required this.year, required this.amount, required this.currency});

  final int year;
  final double? amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isPaid = amount != null;

    return Tooltip(
      message: isPaid
          ? '$year · ${formatMoney(amount!, currency: currency)}'
          : '$year · nothing recorded',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isPaid ? primary.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPaid ? Colors.transparent : Colors.grey.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          '$year',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isPaid ? FontWeight.w800 : FontWeight.w500,
            color: isPaid ? primary : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.orange.shade800),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

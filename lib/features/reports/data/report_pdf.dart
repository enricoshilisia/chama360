import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/chama_report.dart';

/// The chama's report as a document you can print, email or take to a
/// meeting.
///
/// This is the AGM pack, not a screenshot of the app: the register is a
/// proper table here, because a page is the one place a member-by-year
/// grid actually fits. Everything comes from the same [ChamaReport] the
/// screen is showing, so the paper and the screen can never disagree.
class ReportPdf {
  ReportPdf._();

  static final _long = DateFormat('d MMMM yyyy');

  static const _green = PdfColor.fromInt(0xFF2E7D32);
  static const _ink = PdfColor.fromInt(0xFF1B1B1B);
  static const _muted = PdfColor.fromInt(0xFF6B6B6B);
  static const _rule = PdfColor.fromInt(0xFFE0E0E0);
  static const _band = PdfColor.fromInt(0xFFF1F7F1);

  static Future<Uint8List> build({
    required ChamaReport report,
    required String chamaName,
    required String currency,
  }) async {
    final doc = pw.Document(title: '$chamaName — contribution report');

    pw.MemoryImage? logo;
    try {
      final bytes = await rootBundle.load('assets/icon/app_icon.png');
      logo = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      // A missing logo is not a reason to fail the export.
    }

    final years = report.contributionYears;
    // A page only has so much width. Beyond a dozen years the register
    // keeps the most recent ones and says so rather than shrinking to
    // illegibility.
    final shown = years.length > 12 ? years.sublist(years.length - 12) : years;
    final byMember = report.yearTotalsByMember;

    final members = [...report.memberBreakdown]..sort((a, b) {
        final aYears = byMember[a.memberId]?.length ?? 0;
        final bYears = byMember[b.memberId]?.length ?? 0;
        return aYears != bYears ? bYears.compareTo(aYears) : a.name.compareTo(b.name);
      });

    String money(double v) => formatForPdf(v);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(chamaName,
                    style: pw.TextStyle(
                        fontSize: 9, color: _muted, fontWeight: pw.FontWeight.bold)),
              ),
        footer: (context) => pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _rule)),
          ),
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated ${_long.format(DateTime.now())} · Chama360',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: _muted)),
            ],
          ),
        ),
        build: (context) => [
          _title(chamaName, currency, logo),
          pw.SizedBox(height: 18),
          _figures(report, money),
          pw.SizedBox(height: 18),
          _periods(report, money),
          if (years.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _turnout(report, years, money),
          ],
          if (shown.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _register(report, shown, years, byMember, members, money),
          ],
          if (report.memberBreakdown.isNotEmpty && shown.isEmpty) ...[
            pw.SizedBox(height: 20),
            _plainMemberTotals(members, money),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Cells carry bare numbers: a table where every row repeats "KES" is
  /// harder to scan than one that says so once, under the title. Whole
  /// shillings, because no chama contributes cents.
  static String formatForPdf(double value) =>
      NumberFormat('#,##0', 'en_KE').format(value);

  static pw.Widget _title(String chamaName, String currency, pw.MemoryImage? logo) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.SizedBox(width: 34, height: 34, child: pw.Image(logo)),
          pw.SizedBox(width: 12),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(chamaName,
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
              pw.SizedBox(height: 2),
              pw.Text('Contribution report · ${_long.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10, color: _muted)),
              pw.SizedBox(height: 1),
              pw.Text('All figures in $currency',
                  style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _figures(ChamaReport report, String Function(double) money) {
    final cells = <(String, String)>[
      ('Total contributed', money(report.totalContributions)),
      ('Members', '${report.memberCount}'),
      ('Out on loan', money(report.totalOutstanding)),
      ('Active loans', '${report.activeLoanCount}'),
    ];

    return pw.Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: _band,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(cells[i].$2,
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold, color: _green)),
                  pw.SizedBox(height: 2),
                  pw.Text(cells[i].$1,
                      style: const pw.TextStyle(fontSize: 8, color: _muted)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _periods(ChamaReport report, String Function(double) money) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('What came in, and when'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.symmetric(inside: const pw.BorderSide(color: _rule)),
          children: [
            for (final p in ReportPeriod.values)
              pw.TableRow(children: [
                _cell(p.label),
                _cell(money(report.totalFor(p)), align: pw.TextAlign.right, bold: true),
              ]),
          ],
        ),
      ],
    );
  }

  static pw.Widget _turnout(
    ChamaReport report,
    List<int> years,
    String Function(double) money,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('Turnout by year'),
        pw.SizedBox(height: 2),
        pw.Text(
          'How many of the chama\'s ${report.memberCount} members contributed, each year.',
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _rule, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1.4),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _band),
              children: [
                _cell('Year', bold: true),
                _cell('Contributed', bold: true),
                _cell('Turnout', bold: true, align: pw.TextAlign.right),
                _cell('Total', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final year in years.reversed)
              () {
                final s = report.yearSummary(year);
                final pct = report.memberCount == 0
                    ? 0
                    : (s.contributors / report.memberCount * 100).round();
                return pw.TableRow(children: [
                  _cell('$year', bold: true),
                  _cell('${s.contributors} of ${report.memberCount}'),
                  _cell('$pct%', align: pw.TextAlign.right),
                  _cell(money(s.total), align: pw.TextAlign.right, bold: true),
                ]);
              }(),
          ],
        ),
      ],
    );
  }

  static pw.Widget _register(
    ChamaReport report,
    List<int> shown,
    List<int> allYears,
    Map<String, Map<int, double>> byMember,
    List<MemberContribution> members,
    String Function(double) money,
  ) {
    final neverPaid = members.where((m) => (byMember[m.memberId]?.isEmpty ?? true)).length;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('The register'),
        pw.SizedBox(height: 2),
        pw.Text(
          [
            'A filled dot against a year means that member contributed in it.',
            if (neverPaid > 0)
              '$neverPaid member${neverPaid == 1 ? ' has' : 's have'} never contributed.',
            if (shown.length < allYears.length)
              'Showing the most recent ${shown.length} of ${allYears.length} years.',
          ].join(' '),
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _rule, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3.4),
            for (var i = 0; i < shown.length; i++)
              i + 1: const pw.FlexColumnWidth(0.85),
            shown.length + 1: const pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _band),
              children: [
                _cell('Member', bold: true),
                for (final y in shown)
                  _cell('$y'.substring(2), bold: true, align: pw.TextAlign.center),
                _cell('Total', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final m in members)
              () {
                final paid = byMember[m.memberId] ?? const <int, double>{};
                final total = paid.values.fold<double>(0, (sum, v) => sum + v);
                return pw.TableRow(children: [
                  _cell(m.name),
                  for (final y in shown) _markCell(paid.containsKey(y)),
                  _cell(total == 0 ? '-' : money(total),
                      align: pw.TextAlign.right, bold: total > 0),
                ]);
              }(),
          ],
        ),
      ],
    );
  }

  static pw.Widget _plainMemberTotals(
    List<MemberContribution> members,
    String Function(double) money,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('Members'),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _rule, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _band),
              children: [
                _cell('Member', bold: true),
                _cell('Total', bold: true, align: pw.TextAlign.right),
              ],
            ),
            for (final m in members)
              pw.TableRow(children: [
                _cell(m.name),
                _cell(m.total == 0 ? '-' : money(m.total),
                    align: pw.TextAlign.right, bold: m.total > 0),
              ]),
          ],
        ),
      ],
    );
  }

  /// Drawn rather than written. The tick character is not in the fonts a
  /// PDF ships with by default, so writing one produced a silently empty
  /// cell — in a register, where the marks are the entire content.
  static pw.Widget _markCell(bool paid) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Container(
        width: 7,
        height: 7,
        decoration: pw.BoxDecoration(
          color: paid ? _green : null,
          shape: pw.BoxShape.circle,
          border: paid ? null : pw.Border.all(color: _rule, width: 0.8),
        ),
      ),
    );
  }

  static pw.Widget _heading(String text) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink),
      );

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    PdfColor color = _ink,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}

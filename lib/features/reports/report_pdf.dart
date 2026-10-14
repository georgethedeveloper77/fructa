import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/statement_analysis.dart';
import '../../engine/statement/statement_model.dart';
import '../statements/statement_controller.dart';
import '../wrap/wrap_engine.dart';

/// Reports as PDF, made on the phone from the same numbers the app shows.
///
/// Colours come from the light theme tokens (a PDF is printed on white), and
/// the type is the app's own Inter and Space Grotesk, bundled in assets.
abstract final class ReportPdf {
  static final _t = fructaColors.light(fructaAccent.gold);
  static PdfColor _c(int argb) => PdfColor.fromInt(argb);
  static PdfColor get _ink => _c(_t.text.toARGB32());
  static PdfColor get _muted => _c(_t.muted.toARGB32());
  static PdfColor get _line => _c(_t.line.toARGB32());
  static PdfColor get _up => _c(_t.up.toARGB32());
  static PdfColor get _down => _c(_t.down.toARGB32());
  static PdfColor get _gold => _c(_t.accentInk.toARGB32());

  static Future<pw.ThemeData> _theme() async {
    final base = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    return pw.ThemeData.withFont(base: base, bold: bold);
  }

  static Future<pw.Font> _num() async => pw.Font.ttf(
    await rootBundle.load('assets/fonts/SpaceGrotesk-Medium.ttf'),
  );

  static String _kes(double v) {
    final s = v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    final b = StringBuffer();
    final w = parts[0];
    for (var i = 0; i < w.length; i++) {
      if (i > 0 && (w.length - i) % 3 == 0) b.write(',');
      b.write(w[i]);
    }
    return 'KES $b.${parts[1]}';
  }

  static pw.Widget _header(String kicker, String title, String sub) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            kicker,
            style: pw.TextStyle(
              color: _gold,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            title,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(sub, style: pw.TextStyle(color: _muted, fontSize: 10)),
          pw.SizedBox(height: 14),
          pw.Divider(color: _line, thickness: 0.8),
        ],
      );

  static pw.Widget _section(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  static pw.Widget _table(
    List<String> headers,
    List<List<String>> rows, {
    Set<int> right = const {},
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: null,
    headerStyle: pw.TextStyle(
      color: _muted,
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: pw.TextStyle(color: _ink, fontSize: 10),
    headerDecoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line)),
    ),
    rowDecoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)),
    ),
    cellAlignment: pw.Alignment.centerLeft,
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignments: {for (final i in right) i: pw.Alignment.centerRight},
    headerAlignments: {for (final i in right) i: pw.Alignment.centerRight},
    cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
  );

  static pw.Widget _footer(pw.Context ctx) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Fructa \u00b7 fructa.africa \u00b7 made on your phone',
        style: pw.TextStyle(color: _muted, fontSize: 8),
      ),
      pw.Text(
        '${ctx.pageNumber} / ${ctx.pagesCount}',
        style: pw.TextStyle(color: _muted, fontSize: 8),
      ),
    ],
  );

  /// The monthly report: earnings per holding, statement findings, market.
  static Future<Uint8List> month(
    MonthWrap m, {
    required List<StatementAnalysis> statements,
  }) async {
    final doc = pw.Document(theme: await _theme());
    final num = await _num();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
        footer: _footer,
        build: (_) => [
          _header(
            'FRUCTA \u00b7 MONTHLY REPORT',
            monthName(m.from),
            '${dayLabel(m.from)} to ${dayLabel(m.to)}',
          ),
          if (m.holdings.isNotEmpty) ...[
            _section('What your money earned'),
            pw.Text(
              '+${_kes(m.earnedKes)}',
              style: pw.TextStyle(font: num, fontSize: 26, color: _up),
            ),
            if (m.pct != null)
              pw.Text(
                '+${(m.pct! * 100).toStringAsFixed(0)} bps on your portfolio',
                style: pw.TextStyle(color: _muted, fontSize: 10),
              ),
            pw.SizedBox(height: 10),
            _table(
              ['Holding', 'Currency', 'Earned', 'Source'],
              [
                for (final h in m.holdings)
                  [
                    h.name,
                    h.currency,
                    '+${_kes(h.earnedKes)}',
                    h.verified ? 'Statement' : 'Estimate',
                  ],
              ],
              right: {2},
            ),
          ],
          if (statements.isNotEmpty) ...[
            _section('From your statements'),
            for (final a in statements) ..._statementSummary(a),
          ],
          _section('The market at month end'),
          _table(
            ['KES money market fund', 'Gross rate'],
            [
              for (final f in m.topFunds) [f.$1, '${f.$2.toStringAsFixed(2)}%'],
            ],
            right: {1},
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '91-day Treasury bill: ${m.tbill91.toStringAsFixed(2)}%',
            style: pw.TextStyle(color: _muted, fontSize: 10),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Earnings are interest accrued at current rates after withholding tax, '
            'except holdings confirmed by a statement, which use the statement balance. '
            'Not financial advice.',
            style: pw.TextStyle(color: _muted, fontSize: 8.5),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static List<pw.Widget> _statementSummary(StatementAnalysis a) {
    final d = a.statement;
    final gap = a.gapPts;
    return [
      pw.Text(
        '${d.managerName} \u00b7 ${d.currency} \u00b7 ${dayLabel(d.from)} to ${dayLabel(d.to)}',
        style: pw.TextStyle(
          color: _ink,
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      if (gap != null)
        pw.Text(
          'Credited ${a.recentCreditedPct!.toStringAsFixed(2)}% against a published '
          '${a.recentPublishedPct!.toStringAsFixed(2)}%: ${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)} pts a year.',
          style: pw.TextStyle(color: gap <= -0.25 ? _down : _ink, fontSize: 10),
        ),
      pw.SizedBox(height: 8),
    ];
  }

  /// One statement's full check.
  static Future<Uint8List> statement(
    SavedStatement s,
    StatementAnalysis a,
  ) async {
    final doc = pw.Document(theme: await _theme());
    final num = await _num();
    final d = s.data;
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
        footer: _footer,
        build: (_) => [
          _header(
            'FRUCTA \u00b7 STATEMENT CHECK',
            '${d.managerName} \u00b7 ${d.currency}',
            'Account ending ${d.accountTail} \u00b7 ${dayLabel(d.from)} to ${dayLabel(d.to)}',
          ),
          if (a.gapPts != null) ...[
            _section('Credited against published'),
            pw.Text(
              '${a.gapPts! >= 0 ? '+' : ''}${a.gapPts!.toStringAsFixed(2)} pts a year',
              style: pw.TextStyle(
                font: num,
                fontSize: 24,
                color: a.gapPts! <= -0.25 ? _down : _up,
              ),
            ),
            pw.Text(
              'Credited ${a.recentCreditedPct!.toStringAsFixed(2)}%, published ${a.recentPublishedPct!.toStringAsFixed(2)}%, '
              'over ${dayLabel(a.recentFrom!)} to ${dayLabel(a.recentTo!)}.',
              style: pw.TextStyle(color: _muted, fontSize: 10),
            ),
          ],
          _section('Each month'),
          _table(
            ['Credited on', 'Days', 'Interest', 'Tax', 'Yield, a year'],
            [
              for (final p in a.periods)
                [
                  dayLabel(p.end),
                  '${p.days}',
                  p.interest.toStringAsFixed(2),
                  p.tax.toStringAsFixed(2),
                  p.isFull && p.annualPct != null
                      ? '${p.annualPct!.toStringAsFixed(2)}%'
                      : 'part month',
                ],
            ],
            right: {1, 2, 3, 4},
          ),
          _section('Totals'),
          _table(
            ['Paid in', 'Taken out', 'Interest', 'Tax', 'Closing balance'],
            [
              [
                _kes(d.deposits),
                _kes(d.withdrawals),
                _kes(d.interest),
                _kes(d.tax),
                _kes(d.closingBalance),
              ],
            ],
            right: {0, 1, 2, 3, 4},
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Yield is worked out from each day\'s balance, the way funds credit interest. '
            'The published rate is Fructa\'s record of what the manager advertised over the same days.',
            style: pw.TextStyle(color: _muted, fontSize: 8.5),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Withholding tax for one year, per account, for the KRA return.
  static Future<Uint8List> tax(int year, List<TaxRow> rows) async {
    final doc = pw.Document(theme: await _theme());
    final num = await _num();
    final totalTax = rows.fold(0.0, (s, r) => s + r.tax);
    final totalInterest = rows.fold(0.0, (s, r) => s + r.interest);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
        footer: _footer,
        build: (_) => [
          _header(
            'FRUCTA \u00b7 TAX PACK',
            'Withholding tax, $year',
            'From the fund statements you checked in Fructa',
          ),
          _section('Total withheld'),
          pw.Text(
            _kes(totalTax),
            style: pw.TextStyle(font: num, fontSize: 26, color: _ink),
          ),
          pw.Text(
            'on ${_kes(totalInterest)} of interest',
            style: pw.TextStyle(color: _muted, fontSize: 10),
          ),
          _section('By account'),
          _table(
            ['Manager', 'Account', 'Currency', 'Interest', 'Tax withheld'],
            [
              for (final r in rows)
                [
                  r.manager,
                  r.accountTail,
                  r.currency,
                  r.interest.toStringAsFixed(2),
                  r.tax.toStringAsFixed(2),
                ],
            ],
            right: {3, 4},
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Covers only the months on statements you checked. Confirm against the '
            'withholding certificate your manager issues before filing.',
            style: pw.TextStyle(color: _muted, fontSize: 8.5),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Writes [bytes] to a temporary file and opens the share sheet.
  static Future<void> share(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }
}

/// One account's interest and tax in a year.
class TaxRow {
  const TaxRow(
    this.manager,
    this.accountTail,
    this.currency,
    this.interest,
    this.tax,
  );

  final String manager;
  final String accountTail;
  final String currency;
  final double interest;
  final double tax;
}

/// Interest and tax per year and account, from every checked statement.
/// Overlapping statements repeat lines; each manager line is counted once,
/// by its transaction number.
Map<int, List<TaxRow>> taxByYear(List<SavedStatement> statements) {
  final seen = <String>{};
  final acc = <int, Map<String, (String, String, String, double, double)>>{};
  for (final s in statements) {
    final d = s.data;
    final key = '${d.managerKey}|${d.accountNo}';
    for (final e in d.entries.where(
      (e) => e.kind == StatementEntryKind.interest,
    )) {
      if (!seen.add('$key|${e.ref}')) continue;
      final y = acc.putIfAbsent(e.date.year, () => {});
      final prev =
          y[key] ?? (d.managerName, d.accountTail, d.currency, 0.0, 0.0);
      y[key] = (prev.$1, prev.$2, prev.$3, prev.$4 + e.amount, prev.$5 + e.tax);
    }
  }
  return {
    for (final entry in acc.entries)
      entry.key: [
        for (final r in entry.value.values)
          TaxRow(r.$1, r.$2, r.$3, r.$4, r.$5),
      ],
  };
}

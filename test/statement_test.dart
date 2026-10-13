import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/statement/statement_analysis.dart';
import 'package:fructa/engine/statement/statement_model.dart';
import 'package:fructa/engine/statement/statement_parser.dart';

/// The fixture is a real Lofty-Corban statement's extracted text with the
/// client's name and member number replaced.
void main() {
  final text = File(
    'test/fixtures/lofty_corban_statement.txt',
  ).readAsStringSync();
  final s = StatementParser.parse(text);

  test('reads every line and reconciles the running balance', () {
    expect(s.managerKey, 'lofty_corban');
    expect(s.currency, 'KES');
    expect(s.entries.length, 23);
    expect(s.warnings, isEmpty);
    expect(s.closingBalance, closeTo(1452.40, 0.001));
    expect(s.deposits, closeTo(10000, 0.001));
    expect(s.withdrawals, closeTo(10000, 0.001));
    expect(
      s.entries
          .where((e) => e.kind == StatementEntryKind.withdrawal)
          .single
          .date,
      DateTime(2026, 9, 9),
    );
  });

  test('credited yields follow the fund day convention', () {
    final a = StatementAnalyzer.analyze(s, whtPct: 15);
    final full = a.fullPeriods;
    expect(full.first.annualPct, closeTo(12.49, 0.01)); // Apr 2025
    expect(
      full.last.annualPct,
      closeTo(10.16, 0.01),
    ); // Sep 2026, after the withdrawal
  });

  test('findings', () {
    final a = StatementAnalyzer.analyze(
      s,
      whtPct: 15,
      published: (_, _) => 10.71,
    );
    final keys = a.findings.map((f) => f.key).toSet();
    expect(keys, contains('statement.find.underpaid'));
    expect(keys, contains('statement.find.taxOk'));
    expect(keys, contains('statement.find.everyMonth'));
    expect(keys, contains('statement.find.withdrawalPaid'));
    expect(keys, contains('statement.find.creditOnArrival'));
    // The printed totals row is KES 0.10 above the sum of the interest lines.
    expect(keys, contains('statement.find.totalsOff'));
    expect(a.gapPts, lessThan(-0.5));
  });
}

import 'statement_model.dart';

/// Interest credited for one stretch of days, with the yield it implies.
class CreditedPeriod {
  const CreditedPeriod({
    required this.start,
    required this.end,
    required this.days,
    required this.interest,
    required this.tax,
    required this.balanceDays,
  });

  /// First day that earned (the day after the previous credit).
  final DateTime start;

  /// Day the interest was credited.
  final DateTime end;
  final int days;

  /// Gross interest credited.
  final double interest;
  final double tax;

  /// Sum over the period of each day's earning balance.
  final double balanceDays;

  /// Average earning balance across the period.
  double get averageBalance => days == 0 ? 0 : balanceDays / days;

  /// Gross annual rate the credit works out to, in percent.
  double? get annualPct =>
      balanceDays <= 0 ? null : interest * 365 / balanceDays * 100;

  /// A credit covering most of a month. Shorter stretches (an opening credit,
  /// a part month) give noisy yields and are reported, not charted.
  bool get isFull => days >= 20;

  /// Withholding as a share of this credit, in percent.
  double? get taxPct => interest <= 0 ? null : tax / interest * 100;
}

/// One thing the check found, worded by the UI from [key] and [vars].
class StatementFinding {
  const StatementFinding(this.key, this.severity, [this.vars = const {}]);

  /// i18n key, e.g. `statement.find.taxOk`.
  final String key;
  final FindingSeverity severity;
  final Map<String, String> vars;
}

enum FindingSeverity { ok, info, warn, bad }

/// The full check of one statement.
class StatementAnalysis {
  const StatementAnalysis({
    required this.statement,
    required this.periods,
    required this.findings,
    required this.recentCreditedPct,
    required this.recentPublishedPct,
    required this.recentFrom,
    required this.recentTo,
  });

  final StatementData statement;
  final List<CreditedPeriod> periods;
  final List<StatementFinding> findings;

  /// Average credited gross yield over the most recent full periods (up to 6).
  final double? recentCreditedPct;

  /// Average published gross rate over the same days, when history is known.
  final double? recentPublishedPct;
  final DateTime? recentFrom;
  final DateTime? recentTo;

  /// Credited minus published, in points. Negative means paid less.
  double? get gapPts =>
      (recentCreditedPct == null || recentPublishedPct == null)
      ? null
      : recentCreditedPct! - recentPublishedPct!;

  /// Periods worth charting, oldest first.
  List<CreditedPeriod> get fullPeriods =>
      periods.where((p) => p.isFull).toList();
}

/// Average published gross rate between two dates, inclusive, or null when
/// Fructa has no history covering them.
typedef PublishedAverage = double? Function(DateTime from, DateTime to);

/// Works out what a statement actually paid and what to flag.
///
/// Day convention, matching how Kenyan money market funds credit: interest
/// credited on day E covers the days after the previous credit up to and
/// including E. Each day earns on the balance after every line dated on or
/// before it, except the credit being measured. So a deposit earns from its
/// own date and a withdrawal stops earning on its date.
abstract final class StatementAnalyzer {
  static StatementAnalysis analyze(
    StatementData s, {
    required double whtPct,
    bool taxFree = false,
    PublishedAverage? published,
  }) {
    final periods = _periods(s);
    final findings = <StatementFinding>[];

    // ── Tax ────────────────────────────────────────────────────────────────
    final taxed = periods.where((p) => p.interest > 0.5).toList();
    if (taxFree) {
      if (taxed.any((p) => p.tax > 0.005)) {
        findings.add(
          const StatementFinding(
            'statement.find.taxOnTaxFree',
            FindingSeverity.bad,
          ),
        );
      }
    } else if (taxed.isNotEmpty) {
      final off = taxed
          .where((p) => ((p.taxPct ?? whtPct) - whtPct).abs() > 0.15)
          .toList();
      if (off.isEmpty) {
        final total = s.interest == 0 ? 0 : s.tax / s.interest * 100;
        findings.add(
          StatementFinding('statement.find.taxOk', FindingSeverity.ok, {
            'pct': total.toStringAsFixed(2),
          }),
        );
      } else {
        findings.add(
          StatementFinding('statement.find.taxOff', FindingSeverity.warn, {
            'n': '${off.length}',
            'pct': whtPct.toStringAsFixed(0),
          }),
        );
      }
    }

    // ── Every calendar month credited ──────────────────────────────────────
    final missing = _missingMonths(s);
    final months = _monthsSpanned(s);
    if (missing.isEmpty) {
      findings.add(
        StatementFinding('statement.find.everyMonth', FindingSeverity.ok, {
          'n': '$months',
        }),
      );
    } else {
      findings.add(
        StatementFinding('statement.find.missingMonths', FindingSeverity.bad, {
          'months': missing.map(_monthLabel).join(', '),
        }),
      );
    }

    // ── Withdrawals: was the money paid interest up to the day it left? ────
    for (final w in s.entries.where(
      (e) => e.kind == StatementEntryKind.withdrawal,
    )) {
      final after = periods.where((p) => !p.end.isBefore(w.date)).toList();
      if (after.isEmpty) continue;
      final p = after.first;
      final paidUpTo = w.date.subtract(const Duration(days: 1));
      if (p.start.isBefore(w.date) && p.annualPct != null) {
        findings.add(
          StatementFinding(
            'statement.find.withdrawalPaid',
            FindingSeverity.ok,
            {
              'amount': w.amount.abs().toStringAsFixed(2),
              'date': _dayLabel(w.date),
              'from': _dayLabel(p.start),
              'to': _dayLabel(paidUpTo),
            },
          ),
        );
      }
    }

    // ── Credits that do not fit a monthly pattern ──────────────────────────
    for (final p in periods.where((p) => !p.isFull && p.interest > 0)) {
      final opening =
          periods.isNotEmpty && identical(p, periods.first) && p.days <= 1;
      findings.add(
        StatementFinding(
          opening
              ? 'statement.find.creditOnArrival'
              : 'statement.find.partCredit',
          // Interest on the day money arrives is worth asking about; a short
          // opening or closing month is normal and only noted.
          opening ? FindingSeverity.warn : FindingSeverity.info,
          {
            'amount': p.interest.toStringAsFixed(2),
            'date': _dayLabel(p.end),
            'days': '${p.days}',
          },
        ),
      );
    }

    // ── Printed totals against the lines ───────────────────────────────────
    final printed = s.printedTotals;
    if (printed != null && printed.length >= 4) {
      final dInt = (printed[1] - s.interest).abs();
      final dTax = (printed[3] - s.tax).abs();
      if (dInt > 0.009 || dTax > 0.009) {
        findings.add(
          StatementFinding('statement.find.totalsOff', FindingSeverity.info, {
            'interest': dInt.toStringAsFixed(2),
            'tax': dTax.toStringAsFixed(2),
          }),
        );
      }
    }

    // ── Credited against published, recent full months ─────────────────────
    final full = periods.where((p) => p.isFull && p.annualPct != null).toList();
    final recent = full.length > 6 ? full.sublist(full.length - 6) : full;
    double? credited;
    double? pub;
    DateTime? from;
    DateTime? to;
    if (recent.isNotEmpty) {
      final interest = recent.fold(0.0, (a, p) => a + p.interest);
      final bd = recent.fold(0.0, (a, p) => a + p.balanceDays);
      credited = bd <= 0 ? null : interest * 365 / bd * 100;
      from = recent.first.start;
      to = recent.last.end;
      pub = published?.call(from, to);
    }
    if (credited != null && pub != null) {
      final gap = credited - pub;
      findings.insert(
        0,
        StatementFinding(
          gap <= -0.25
              ? 'statement.find.underpaid'
              : (gap >= 0.25
                    ? 'statement.find.overpaid'
                    : 'statement.find.matches'),
          gap <= -0.25 ? FindingSeverity.bad : FindingSeverity.ok,
          {
            'credited': credited.toStringAsFixed(2),
            'published': pub.toStringAsFixed(2),
            'gap': gap.abs().toStringAsFixed(2),
          },
        ),
      );
    }

    return StatementAnalysis(
      statement: s,
      periods: periods,
      findings: findings,
      recentCreditedPct: credited,
      recentPublishedPct: pub,
      recentFrom: from,
      recentTo: to,
    );
  }

  /// One [CreditedPeriod] per interest line.
  static List<CreditedPeriod> _periods(StatementData s) {
    final out = <CreditedPeriod>[];
    DateTime? prevEnd;
    final e = s.entries;
    for (var i = 0; i < e.length; i++) {
      final line = e[i];
      if (line.kind != StatementEntryKind.interest) continue;
      final end = _day(line.date);
      final start = prevEnd == null
          ? _day(e.first.date)
          : prevEnd.add(const Duration(days: 1));
      var balanceDays = 0.0;
      var days = 0;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        var bal = 0.0;
        for (var k = 0; k < i; k++) {
          if (!_day(e[k].date).isAfter(d)) bal = e[k].balance;
        }
        balanceDays += bal;
        days++;
      }
      out.add(
        CreditedPeriod(
          start: start,
          end: end,
          days: days,
          interest: line.amount,
          tax: line.tax,
          balanceDays: balanceDays,
        ),
      );
      prevEnd = end;
    }
    return out;
  }

  /// Calendar months with an earning balance but no interest credited, from
  /// the first full month to the statement's last month.
  static List<DateTime> _missingMonths(StatementData s) {
    final credited = {
      for (final x in s.entries.where(
        (x) => x.kind == StatementEntryKind.interest,
      ))
        DateTime(x.date.year, x.date.month),
    };
    final first = s.entries.first.date;
    var m = DateTime(first.year, first.month + 1);
    final last = DateTime(s.to.year, s.to.month);
    final out = <DateTime>[];
    while (!m.isAfter(last)) {
      if (!credited.contains(m)) out.add(m);
      m = DateTime(m.year, m.month + 1);
    }
    return out;
  }

  static int _monthsSpanned(StatementData s) {
    final a = s.entries.first.date;
    final b = s.to;
    return (b.year - a.year) * 12 + b.month - a.month;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static const _mon = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static String _monthLabel(DateTime d) => '${_mon[d.month - 1]} ${d.year}';
  static String _dayLabel(DateTime d) =>
      '${d.day} ${_mon[d.month - 1]} ${d.year}';
}

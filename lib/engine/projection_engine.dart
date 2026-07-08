import 'dart:math' as math;

import 'tax.dart';

/// Monthly-compounded projections for the portfolio slider and growth chart.
class ProjectionEngine {
  /// Effective monthly rate from an effective annual rate (%).
  static double monthlyRate(double annualRatePercent) {
    final r = annualRatePercent / 100.0;
    return math.pow(1 + r, 1 / 12).toDouble() - 1;
  }

  static double _effMonthly(double annualRatePercent, bool net) {
    final m = monthlyRate(annualRatePercent);
    return net ? m * (1 - Tax.wht) : m;
  }

  /// Projected value after [months], monthly-compounded, with an optional
  /// end-of-month [monthlyTopUp].
  static double project(
    double principal,
    double annualRatePercent,
    int months, {
    double monthlyTopUp = 0,
    bool net = false,
  }) {
    final m = _effMonthly(annualRatePercent, net);
    final growth = math.pow(1 + m, months).toDouble();
    final fvPrincipal = principal * growth;
    final fvContrib = m == 0
        ? monthlyTopUp * months
        : monthlyTopUp * (growth - 1) / m;
    return fvPrincipal + fvContrib;
  }

  /// Value at each month, index 0..months (index 0 == principal). For the chart.
  static List<double> series(
    double principal,
    double annualRatePercent,
    int months, {
    double monthlyTopUp = 0,
    bool net = false,
  }) {
    final m = _effMonthly(annualRatePercent, net);
    final out = <double>[principal];
    var v = principal;
    for (var i = 1; i <= months; i++) {
      v = v * (1 + m) + monthlyTopUp;
      out.add(v);
    }
    return out;
  }

  /// Months to reach [target]. Returns 0 if already there, null if unreachable
  /// (no growth and no contributions).
  static int? monthsToGoal(
    double principal,
    double annualRatePercent,
    double target, {
    double monthlyTopUp = 0,
    bool net = false,
  }) {
    if (target <= principal) return 0;
    final m = _effMonthly(annualRatePercent, net);
    if (m <= 0 && monthlyTopUp <= 0) return null;
    var v = principal;
    var months = 0;
    const cap = 1200; // 100 years  safety valve
    while (v < target && months < cap) {
      v = v * (1 + m) + monthlyTopUp;
      months++;
    }
    return v >= target ? months : null;
  }
}

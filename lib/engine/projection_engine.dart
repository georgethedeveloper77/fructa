import 'dart:math' as math;

import '../data/models/period_return.dart';
import 'tax.dart';

/// Monthly-compounded projections for the portfolio slider and growth chart.
///
/// COMPOUNDING IS A CLAIM ABOUT THE FUTURE, and this engine may only be pointed
/// at a number entitled to make one. An annual yield qualifies: it is what the
/// fund is paying now, forward-looking, and compounding it says the fund keeps
/// paying it. A realized quarterly return does not: it is a fact about a window
/// that has closed, and compounding it says next quarter will look like the last
/// one, which nobody knows and the fund itself does not claim.
///
/// The gate is [canProject]. Calling it is not optional politeness; skipping it
/// is how a fund with two published quarters and a six month lock-in came to
/// show a two year projected value on its detail page.
class ProjectionEngine {
  /// Whether a fund's headline may be compounded at all.
  ///
  /// Only `yield`. A NAV fund has a price, not a rate. A return fund has
  /// history, not a run rate. Both get the growth card instead, which looks
  /// backwards and therefore promises nothing.
  static bool canProject(String? basis) => (basis ?? 'yield') == 'yield';
  /// Effective monthly rate from an effective annual rate (%).
  static double monthlyRate(double annualRatePercent) {
    final r = annualRatePercent / 100.0;
    return math.pow(1 + r, 1 / 12).toDouble() - 1;
  }

  /// Effective monthly rate, after withholding tax when tax is actually owed.
  ///
  /// [whtPct] comes from remote config at the call site. It used to be the
  /// hardcoded `Tax.wht`, so a config change moved every LABEL in the app and
  /// none of the arithmetic.
  ///
  /// [netOf] says what the quoted rate already has taken out of it. Null reads
  /// as net of fees and gross of tax, the money market convention, which is what
  /// this engine has always assumed and is correct for every fund that may reach
  /// it at all.
  static double _effMonthly(
    double annualRatePercent,
    bool net, {
    double whtPct = Tax.defaultWhtPct,
    NetOf? netOf,
    bool taxFree = false,
  }) {
    final m = monthlyRate(annualRatePercent);
    if (!net) return m;
    return m * Tax.surviving(netOf: netOf, taxFree: taxFree, whtPct: whtPct);
  }

  /// Projected value after [months], monthly-compounded, with an optional
  /// end-of-month [monthlyTopUp].
  static double project(
    double principal,
    double annualRatePercent,
    int months, {
    double monthlyTopUp = 0,
    bool net = false,
    double whtPct = Tax.defaultWhtPct,
    NetOf? netOf,
    bool taxFree = false,
  }) {
    final m = _effMonthly(annualRatePercent, net,
        whtPct: whtPct, netOf: netOf, taxFree: taxFree);
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
    double whtPct = Tax.defaultWhtPct,
    NetOf? netOf,
    bool taxFree = false,
  }) {
    final m = _effMonthly(annualRatePercent, net,
        whtPct: whtPct, netOf: netOf, taxFree: taxFree);
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
    double whtPct = Tax.defaultWhtPct,
    NetOf? netOf,
    bool taxFree = false,
  }) {
    if (target <= principal) return 0;
    final m = _effMonthly(annualRatePercent, net,
        whtPct: whtPct, netOf: netOf, taxFree: taxFree);
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

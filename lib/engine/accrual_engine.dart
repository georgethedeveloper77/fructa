import 'dart:math' as math;

import '../data/models/period_return.dart';
import 'tax.dart';

/// Daily accrual for money market funds. Rates are quoted as the *effective
/// annual yield*, so the daily rate is derived to compound back to it exactly.
class AccrualEngine {
  static const int daysPerYear = 365;

  /// Effective daily rate from an effective annual rate (%).
  /// (1 + daily)^365 == 1 + annual, by construction.
  static double dailyRate(double annualRatePercent) {
    final r = annualRatePercent / 100.0;
    return math.pow(1 + r, 1 / daysPerYear).toDouble() - 1;
  }

  /// Gross interest earned in one day on [balance].
  static double dailyInterest(double balance, double annualRatePercent) =>
      balance * dailyRate(annualRatePercent);

  /// Net daily interest, after withholding tax WHEN ANY IS OWED.
  ///
  /// This engine values what a holding has actually earned, so a wrong answer
  /// here is wrong in someone's portfolio total rather than on a marketing
  /// screen. It previously deducted 15% from every fund unconditionally, which
  /// is right for a money market fund and wrong for one quoting a rate already
  /// net of tax: that holding accrued 15% less than it really did, every day.
  ///
  /// [netOf] and [taxFree] come from the fund. [whtPct] comes from remote
  /// config. All three default to the money market case, so an existing caller
  /// that passes none behaves exactly as before.
  static double dailyInterestNet(
    double balance,
    double annualRatePercent, {
    NetOf? netOf,
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) =>
      Tax.apply(
        dailyInterest(balance, annualRatePercent),
        netOf: netOf,
        taxFree: taxFree,
        whtPct: whtPct,
      );

  /// Value of [balance] after [days], daily-compounded.
  /// When [net], WHT is taken from each day's interest before it reinvests.
  static double accrue(
    double balance,
    double annualRatePercent,
    int days, {
    bool net = false,
    NetOf? netOf,
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) {
    final g = dailyRate(annualRatePercent);
    // [net] asks for the after-tax path; Tax.surviving decides whether there is
    // any tax left to take. A fund quoting net of tax returns a multiplier of 1
    // and compounds at its full rate, which is what it actually does.
    final effective = net
        ? g * Tax.surviving(netOf: netOf, taxFree: taxFree, whtPct: whtPct)
        : g;
    return balance * math.pow(1 + effective, days).toDouble();
  }

  /// Interest earned over [days] (accrued value minus principal).
  static double interestOver(
    double balance,
    double annualRatePercent,
    int days, {
    bool net = false,
    NetOf? netOf,
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) =>
      accrue(balance, annualRatePercent, days,
          net: net, netOf: netOf, taxFree: taxFree, whtPct: whtPct) -
      balance;
}

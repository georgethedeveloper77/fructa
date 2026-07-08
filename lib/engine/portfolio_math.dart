import '../data/models/holding.dart';
import 'accrual_engine.dart';

/// Valuation of a single holding as of a point in time: cost basis vs the
/// accrued (grown) value, in the holding's own currency and consolidated in KES.
///
/// Each deposit/withdrawal accrues from its OWN date at the fund's net-of-fee
/// effective annual rate  WHT applied unless the fund is tax-free  matching
/// the returns calculator's WHT-only model (current_rate is already net-of-fee,
/// so the management fee is never subtracted again).
///
/// USD holdings convert to KES at the supplied [usdKes]. When that's unknown
/// (no FX in the snapshot yet), [valueKes] is null  never fabricated, never
/// ×0  and the caller shows the native value only.
class HoldingValue {
  final String currency;
  final double principalNative; // cost basis: deposits − withdrawals
  final double valueNative; // accrued to the as-of date
  final double? valueKes; // null when USD and FX unknown
  final double? principalKes;
  final DateTime firstLot; // earliest deposit date, for "added on …"

  const HoldingValue({
    required this.currency,
    required this.principalNative,
    required this.valueNative,
    required this.valueKes,
    required this.principalKes,
    required this.firstLot,
  });

  double get gainNative => valueNative - principalNative;
  double? get gainKes => (valueKes != null && principalKes != null)
      ? valueKes! - principalKes!
      : null;
  bool get fxKnown => valueKes != null;
  bool get isUsd => currency == 'USD';

  int daysHeld(DateTime asOf) {
    final d = asOf.difference(firstLot).inDays;
    return d < 0 ? 0 : d;
  }
}

class PortfolioMath {
  /// Value a single [holding] as of [asOf] (defaults to now).
  ///
  /// [ratePercent] is the fund's `current_rate` (net-of-fee EAR). When it's
  /// null or non-positive the holding is treated as flat  value equals
  /// principal, no invented growth.
  static HoldingValue value(
    Holding holding, {
    required double? ratePercent,
    required bool taxFree,
    required double? usdKes,
    DateTime? asOf,
  }) {
    final now = asOf ?? DateTime.now();

    // Prefer the transaction ledger; fall back to the whole balance opened at
    // openedAt for holdings written before the ledger existed.
    final lots = holding.transactions.isNotEmpty
        ? holding.transactions
        : [
            Txn(
              amount: holding.balance,
              type: 'deposit',
              date: holding.openedAt,
            ),
          ];

    var principal = 0.0;
    var value = 0.0;
    var earliest = now;

    for (final t in lots) {
      principal += t.amount;
      if (t.date.isBefore(earliest)) earliest = t.date;

      final raw = now.difference(t.date).inDays;
      final days = raw < 0 ? 0 : raw;

      if (ratePercent == null || ratePercent <= 0) {
        value += t.amount; // flat  no rate to grow at
      } else {
        // Signed amount: a withdrawal (negative) also un-accrues its growth.
        value += AccrualEngine.accrue(
          t.amount,
          ratePercent,
          days,
          net: !taxFree,
        );
      }
    }

    final isUsd = holding.currency == 'USD';
    final fx = isUsd ? usdKes : 1.0; // KES passes through
    final valueKes = fx == null ? null : value * fx;
    final principalKes = fx == null ? null : principal * fx;

    return HoldingValue(
      currency: holding.currency,
      principalNative: principal,
      valueNative: value,
      valueKes: valueKes,
      principalKes: principalKes,
      firstLot: earliest,
    );
  }
}

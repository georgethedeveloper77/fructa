import '../data/models/period_return.dart';
import 'tax.dart';

// A directly-held bond or bill is NOT quoted the way a fund is, so `net_of`
// does not really apply to it: a Treasury coupon is paid gross and withheld at
// source, full stop. What was wrong here was the RATE, hardcoded at 15 while
// the app reads benchmark.wht_pct from config everywhere it prints one.
//
// The deduction still routes through Tax.apply rather than an inline
// multiplication, so there stays exactly one function in the codebase that may
// reduce a number for tax. NetOf.fees is the argument that means "tax is still
// due", which is precisely the situation; the "fees" half of the name is
// vacuous for an instrument nobody manages, and harmless.
const NetOf _taxStillDue = NetOf.fees;

class CouponPayment {
  final DateTime date;
  final double gross;
  final double net;
  final bool isPrincipal; // final payment includes the face value back
  const CouponPayment({
    required this.date,
    required this.gross,
    required this.net,
    this.isPrincipal = false,
  });
}

class TbillResult {
  final double price; // what you pay now for [faceValue] at maturity
  final double grossInterest; // faceValue - price
  final double netInterest; // after withholding, at the configured rate
  const TbillResult({
    required this.price,
    required this.grossInterest,
    required this.netInterest,
  });
}

/// Treasury bonds (semi-annual coupons), infrastructure bonds (tax-free),
/// and Treasury bills (bought at a discount).
class BondEngine {
  /// One semi-annual coupon on [faceValue] at an annual [couponRatePercent].
  static double semiAnnualCouponGross(double faceValue, double couponRatePercent) =>
      faceValue * (couponRatePercent / 100.0) / 2.0;

  /// Net coupon. IFBs are [taxFree] → net equals gross.
  static double semiAnnualCouponNet(
    double faceValue,
    double couponRatePercent, {
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) {
    final gross = semiAnnualCouponGross(faceValue, couponRatePercent);
    return Tax.apply(gross,
        netOf: _taxStillDue, taxFree: taxFree, whtPct: whtPct);
  }

  /// Full semi-annual coupon schedule; the final payment returns the principal.
  static List<CouponPayment> couponSchedule({
    required double faceValue,
    required double couponRatePercent,
    required DateTime start,
    required int tenorYears,
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) {
    final periods = tenorYears * 2;
    final coupon = semiAnnualCouponGross(faceValue, couponRatePercent);
    final couponNet = Tax.apply(coupon,
        netOf: _taxStillDue, taxFree: taxFree, whtPct: whtPct);
    final out = <CouponPayment>[];
    for (var i = 1; i <= periods; i++) {
      final isLast = i == periods;
      // DateTime normalizes month overflow (e.g. month 18 -> next year).
      final date = DateTime(start.year, start.month + i * 6, start.day);
      out.add(CouponPayment(
        date: date,
        gross: coupon + (isLast ? faceValue : 0),
        net: couponNet + (isLast ? faceValue : 0),
        isPrincipal: isLast,
      ));
    }
    return out;
  }

  /// T-bill: pay [price] now, receive [faceValue] in [days].
  /// [annualYieldPercent] is the quoted market yield.
  static TbillResult tbill({
    required double faceValue,
    required double annualYieldPercent,
    required int days,
    // A T-bill is government paper and is withheld at source. taxFree exists for
    // symmetry with the coupon path, where an infrastructure bond genuinely is
    // exempt; on a bill it should stay false.
    bool taxFree = false,
    double whtPct = Tax.defaultWhtPct,
  }) {
    final y = annualYieldPercent / 100.0;
    final price = faceValue / (1 + y * (days / 365.0));
    final gross = faceValue - price;
    return TbillResult(
      price: price,
      grossInterest: gross,
      netInterest: Tax.apply(gross,
          netOf: _taxStillDue, taxFree: taxFree, whtPct: whtPct),
    );
  }
}

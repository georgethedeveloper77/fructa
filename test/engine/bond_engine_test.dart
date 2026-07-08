import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/bond_engine.dart';

void main() {
  group('BondEngine coupons', () {
    test('semi-annual coupon is half the annual coupon', () {
      // 100,000 @ 13% -> 13,000/yr -> 6,500 per half-year.
      expect(BondEngine.semiAnnualCouponGross(100000, 13), 6500);
    });

    test('taxable coupon loses 15% WHT; IFB coupon is tax-free', () {
      expect(
        BondEngine.semiAnnualCouponNet(100000, 13),
        closeTo(5525, 0.01),
      ); // 6500 * .85
      expect(BondEngine.semiAnnualCouponNet(100000, 13, taxFree: true), 6500);
    });

    test('schedule has 2 payments per year and returns principal last', () {
      final s = BondEngine.couponSchedule(
        faceValue: 100000,
        couponRatePercent: 13,
        start: DateTime(2026, 1, 15),
        tenorYears: 2,
      );
      expect(s.length, 4);
      expect(s.first.isPrincipal, isFalse);
      expect(s.last.isPrincipal, isTrue);
      expect(s.last.gross, closeTo(106500, 0.01)); // 6500 coupon + 100000 face
      expect(s.last.date, DateTime(2028, 1, 15)); // +24 months
      expect(s[1].date, DateTime(2026, 7, 15)); // +12 months
    });
  });

  group('BondEngine T-bill', () {
    test('91-day bill priced at a discount, accretes to face', () {
      final r = BondEngine.tbill(
        faceValue: 100000,
        annualYieldPercent: 8.5,
        days: 91,
      );
      expect(r.price, closeTo(97924.55, 0.5));
      expect(r.grossInterest, closeTo(2075.45, 0.5));
      expect(r.netInterest, closeTo(1764.13, 0.5)); // 2075.45 * .85
      expect(r.price + r.grossInterest, closeTo(100000, 0.01));
    });
  });
}

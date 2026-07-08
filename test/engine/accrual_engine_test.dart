import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/accrual_engine.dart';

void main() {
  group('AccrualEngine', () {
    test('daily rate compounds back to the annual rate over 365 days', () {
      // The defining invariant: (1 + daily)^365 == 1 + annual.
      final value = AccrualEngine.accrue(100000, 12, 365);
      expect(value, closeTo(112000, 0.5));
    });

    test('one year of gross interest equals rate x balance', () {
      final interest = AccrualEngine.interestOver(100000, 12, 365);
      expect(interest, closeTo(12000, 0.5));
    });

    test('daily interest on a known balance', () {
      // 12% EAR -> daily rate ~0.00031054 -> ~31.05 on 100,000.
      expect(AccrualEngine.dailyInterest(100000, 12), closeTo(31.05, 0.05));
    });

    test('net accrual is below gross and reflects 15% WHT on interest', () {
      final gross = AccrualEngine.interestOver(100000, 12, 365); // 12000
      final net = AccrualEngine.interestOver(100000, 12, 365, net: true);
      expect(net, lessThan(gross));
      // Net compounds at the reduced rate, so it lands near (but under) 85%.
      expect(net / gross, closeTo(0.843, 0.01));
      expect(net, closeTo(10113, 20));
    });

    test('zero days returns the principal untouched', () {
      expect(AccrualEngine.accrue(50000, 10, 0), 50000);
      expect(AccrualEngine.interestOver(50000, 10, 0), 0);
    });
  });
}

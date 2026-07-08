import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/projection_engine.dart';

void main() {
  group('ProjectionEngine', () {
    test('12 months of monthly compounding reproduces the annual rate', () {
      expect(ProjectionEngine.project(100000, 12, 12), closeTo(112000, 0.5));
    });

    test('monthly rate compounds to the annual rate', () {
      final m = ProjectionEngine.monthlyRate(12);
      expect(m, closeTo(0.009489, 1e-5));
    });

    test('monthly top-ups grow beyond their nominal sum', () {
      // 12 x 10,000 = 120,000 nominal; growth pushes it higher.
      final v = ProjectionEngine.project(0, 12, 12, monthlyTopUp: 10000);
      expect(v, greaterThan(120000));
      expect(v, closeTo(126465, 50));
    });

    test('series starts at principal, ends at the projected value', () {
      final s = ProjectionEngine.series(100000, 12, 12);
      expect(s.length, 13); // months 0..12
      expect(s.first, 100000);
      expect(s.last, closeTo(ProjectionEngine.project(100000, 12, 12), 0.01));
    });

    test('net projection stays below gross', () {
      final gross = ProjectionEngine.project(100000, 12, 12);
      final net = ProjectionEngine.project(100000, 12, 12, net: true);
      expect(net, lessThan(gross));
    });

    test('months-to-goal: doubling at 12% takes ~74 months', () {
      final n = ProjectionEngine.monthsToGoal(100000, 12, 200000);
      expect(n, isNotNull);
      expect(n, inInclusiveRange(72, 76));
    });

    test('months-to-goal: already at target is 0; unreachable is null', () {
      expect(ProjectionEngine.monthsToGoal(100000, 12, 50000), 0);
      expect(ProjectionEngine.monthsToGoal(100000, 0, 200000), isNull);
    });
  });
}

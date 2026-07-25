import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/fx_engine.dart';

// Golden numbers throughout are the ones printed on the mockup, so a change to
// the engine that moves the page shows up here first.
//
// Base case: CBK mean 129.20, one and a half percent one way spread, a KES
// money market fund at 10.85 gross and a USD one at 4.40 gross, both net of
// fifteen percent withholding.

const _mean = 129.20;
const _kesNet = 0.0922; // 10.85 * 0.85
const _usdNet = 0.0374; // 4.40 * 0.85

FxCase _caseFor(FxStance stance, {double years = 1, FxQuote? quote}) => FxCase(
      quote: quote ?? const FxQuote(mean: _mean),
      kesNet: _kesNet,
      usdNet: _usdNet,
      stance: stance,
      years: years,
    );

void main() {
  group('FxQuote', () {
    test('derives both legs from the modelled spread', () {
      const q = FxQuote(mean: _mean);
      expect(q.askRate, closeTo(131.138, 0.001));
      expect(q.bidRate, closeTo(127.262, 0.001));
      expect(q.measured, isFalse);
    });

    test('round trip costs about three percent at a 1.5 percent spread', () {
      const q = FxQuote(mean: _mean);
      expect(q.roundTrip, closeTo(0.0305, 0.0005));
    });

    test('measured legs take precedence over the assumption', () {
      const q = FxQuote(mean: _mean, bid: 128.00, ask: 130.50);
      expect(q.askRate, 130.50);
      expect(q.bidRate, 128.00);
      expect(q.measured, isTrue);
    });

    test('a user quote replaces only the leg supplied', () {
      const q = FxQuote(mean: _mean);
      final u = q.withUserQuote(userAsk: 132.40);
      expect(u.askRate, 132.40);
      expect(u.bidRate, closeTo(127.262, 0.001));
    });
  });

  group('breakeven', () {
    test('buying has to clear the yield gap and both spreads', () {
      expect(_caseFor(FxStance.buying).breakeven, closeTo(140.17, 0.02));
    });

    test('holding only has to clear the yield gap', () {
      expect(_caseFor(FxStance.holding).breakeven, closeTo(136.03, 0.02));
    });

    test('hedged has no position and therefore no breakeven', () {
      final c = _caseFor(FxStance.hedged);
      expect(c.breakeven, isNull);
      expect(c.impliedDepreciation, isNull);
      expect(c.hurdleBand, isNull);
    });

    test('holding sits below buying by roughly the round trip', () {
      final buy = _caseFor(FxStance.buying).breakeven!;
      final hold = _caseFor(FxStance.holding).breakeven!;
      expect(buy - hold, closeTo(4.14, 0.05));
    });

    test('the annualised hurdle is stable across horizons', () {
      final one = _caseFor(FxStance.holding).annualisedHurdle!;
      final five = _caseFor(FxStance.holding, years: 5).annualisedHurdle!;
      expect(one, closeTo(0.0528, 0.0005));
      expect(five, closeTo(one, 0.0005));
    });

    test('the buying hurdle falls with horizon as the spread amortises', () {
      final one = _caseFor(FxStance.buying).annualisedHurdle!;
      final five = _caseFor(FxStance.buying, years: 5).annualisedHurdle!;
      expect(five, lessThan(one));
      expect(five, closeTo(0.0591, 0.001));
    });

    test('a worse bank quote raises the bar', () {
      final base = _caseFor(FxStance.buying).breakeven!;
      final worse = _caseFor(
        FxStance.buying,
        quote: const FxQuote(mean: _mean).withUserQuote(userAsk: 133.00),
      ).breakeven!;
      expect(worse, greaterThan(base));
    });
  });

  group('hurdle bands', () {
    test('bands split at four and eight percent a year', () {
      expect(_caseFor(FxStance.holding).hurdleBand, FxHurdleBand.moderate);

      final narrow = FxCase(
        quote: const FxQuote(mean: _mean),
        kesNet: 0.06,
        usdNet: 0.04,
        stance: FxStance.holding,
      );
      expect(narrow.hurdleBand, FxHurdleBand.low);

      final wide = FxCase(
        quote: const FxQuote(mean: _mean),
        kesNet: 0.14,
        usdNet: 0.03,
        stance: FxStance.holding,
      );
      expect(wide.hurdleBand, FxHurdleBand.high);
    });
  });

  group('projectFlat', () {
    test('a flat pair leaves the KES fund well ahead for a buyer', () {
      final o = _caseFor(FxStance.buying).projectFlat(100000);
      expect(o.kesPath, closeTo(109220, 5));
      expect(o.usdPath, closeTo(100673, 5));
      expect(o.usdWins, isFalse);
      expect(o.lead, closeTo(8547, 10));
    });

    test('a holder gives up only the yield gap by staying long', () {
      final o = _caseFor(FxStance.holding).projectFlat(800);
      expect(o.kesPath, closeTo(111197, 20));
      expect(o.usdPath, closeTo(105606, 20));
      expect(o.usdWins, isFalse);
    });
  });

  group('race', () {
    // A pair that walks straight up past the buying hurdle.
    final rising = List<double>.generate(13, (i) => 129.20 * (1 + 0.01 * i));

    test('starts level and ends with the USD side ahead when it clears', () {
      final pts = FxEngine.race(
        fxCase: _caseFor(FxStance.buying),
        means: rising,
        start: 0,
        months: 12,
        amount: 100000,
      );
      expect(pts.length, 13);
      expect(pts.first.usdAhead, isFalse);
      expect(pts.last.usdAhead, isTrue);
    });

    test('a flat pair never lets the USD side in front', () {
      final flat = List<double>.filled(13, _mean);
      final pts = FxEngine.race(
        fxCase: _caseFor(FxStance.holding),
        means: flat,
        start: 0,
        months: 12,
        amount: 800,
      );
      expect(pts.every((p) => !p.usdAhead), isTrue);
    });

    test('a window past the end of the series throws rather than truncating',
        () {
      expect(
        () => FxEngine.race(
          fxCase: _caseFor(FxStance.buying),
          means: rising,
          start: 6,
          months: 12,
          amount: 100000,
        ),
        throwsRangeError,
      );
    });
  });

  group('rollingRecord', () {
    test('scores each window against the hurdle for that window length', () {
      // Two years: the first climbs hard, the second gives it back.
      final means = <double>[
        ...List<double>.generate(13, (i) => 120.0 + i * 2.5),
        ...List<double>.generate(12, (i) => 150.0 - i * 1.8),
      ];
      final rec = FxEngine.rollingRecord(
        fxCase: _caseFor(FxStance.holding),
        means: means,
        windowMonths: 12,
      );
      expect(rec.total, means.length - 12);
      expect(rec.wins, greaterThan(0));
      expect(rec.wins, lessThan(rec.total));
      expect(rec.winRate, closeTo(rec.wins / rec.total, 1e-9));
      expect(rec.lastWinIndex, isNotNull);
    });

    test('a flat pair never clears a positive hurdle', () {
      final rec = FxEngine.rollingRecord(
        fxCase: _caseFor(FxStance.holding),
        means: List<double>.filled(40, _mean),
      );
      expect(rec.wins, 0);
      expect(rec.lastWinIndex, isNull);
    });
  });

  group('drip', () {
    test('monthly conversion beats holding when the pair is flat', () {
      final flat = List<double>.filled(13, _mean);
      final pts = FxEngine.drip(
        fxCase: _caseFor(FxStance.holding),
        means: flat,
        start: 0,
        months: 12,
        monthlyUsd: 1500,
      );
      expect(pts.length, 12);
      expect(pts.last.convertEachMonth, greaterThan(pts.last.holdThenConvert));
    });

    test('interest is not paid on money that has not arrived yet', () {
      final flat = List<double>.filled(3, _mean);
      final pts = FxEngine.drip(
        fxCase: _caseFor(FxStance.holding),
        means: flat,
        start: 0,
        months: 1,
        monthlyUsd: 1000,
      );
      // One inflow, no compounding yet, so it is simply converted.
      expect(pts.single.convertEachMonth, closeTo(1000 * 127.262, 0.5));
    });
  });

  group('inUsd', () {
    test('a strong KES return shrinks once the currency is taken out', () {
      final r = FxEngine.inUsd(
        kesReturn: 0.584,
        meanStart: 108.50,
        meanEnd: 129.20,
      );
      expect(r, closeTo(0.330, 0.005));
    });

    test('an unchanged pair leaves the return alone', () {
      final r = FxEngine.inUsd(
        kesReturn: 0.10,
        meanStart: _mean,
        meanEnd: _mean,
      );
      expect(r, closeTo(0.10, 1e-9));
    });
  });

  group('regimeOf', () {
    test('too little history reports calm rather than guessing', () {
      expect(FxEngine.regimeOf(const [129.2, 129.3]), FxRegime.calm);
    });

    test('a flat year is calm', () {
      expect(FxEngine.regimeOf(List<double>.filled(20, _mean)), FxRegime.calm);
    });

    test('a steady slide is drifting', () {
      final m = List<double>.generate(20, (i) => 129.20 * (1 + 0.0035 * i));
      expect(FxEngine.regimeOf(m), FxRegime.drifting);
    });

    test('a fast slide is falling', () {
      final m = List<double>.generate(20, (i) => 120.0 * (1 + 0.012 * i));
      expect(FxEngine.regimeOf(m), FxRegime.falling);
    });

    test('a sharp recovery is a snapback whatever the year did', () {
      final m = <double>[
        ...List<double>.generate(16, (i) => 130.0 + i * 2.0),
        158.0,
        150.0,
        140.0,
        129.0,
      ];
      expect(FxEngine.regimeOf(m), FxRegime.snapback);
    });
  });

  group('copy bank keys', () {
    test('key shape is stance, regime and band', () {
      expect(
        FxEngine.copyKey(
          stance: FxStance.holding,
          regime: FxRegime.calm,
          band: FxHurdleBand.moderate,
        ),
        'fx.holding.calm.mod',
      );
    });

    test('hedged drops the band because it has no hurdle', () {
      expect(
        FxEngine.copyKey(
          stance: FxStance.hedged,
          regime: FxRegime.falling,
          band: FxHurdleBand.high,
        ),
        'fx.hedged.falling',
      );
    });

    test('rotation is stable within a day and moves across days', () {
      final a = FxEngine.rotation(now: DateTime(2026, 7, 25), count: 3);
      final b = FxEngine.rotation(now: DateTime(2026, 7, 25, 23), count: 3);
      final c = FxEngine.rotation(now: DateTime(2026, 7, 26), count: 3);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('a single template slot always returns the only entry', () {
      expect(FxEngine.rotation(now: DateTime.now(), count: 1), 0);
    });
  });
}

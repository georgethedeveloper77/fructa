// Pure USD/KES comparison maths. No widgets, no providers, no I/O, so every
// number the currency page prints can be asserted in a unit test.
//
// Conventions used throughout this file:
//
//   mean  CBK indicative mean for the pair.
//   ask   what a bank sells a dollar to you for. Above the mean.
//   bid   what a bank buys a dollar back from you at. Below the mean.
//
// Rates arrive here already net of withholding, as fractions: 9.22 percent is
// 0.0922. Applying tax is engine/tax.dart's job and doing it twice is the
// easiest mistake to make against this API.
//
// Nothing in here forecasts. Every historical function reports what a series
// did, and every forward function reports what would have to happen for one
// side to win. The difference matters, because the whole point of the feature
// is to price a bet rather than recommend one.

import 'dart:math' as math;

/// Which side of the trade the user is actually on.
///
/// The stance is not a preference, it is a fact about their cash flows, and it
/// changes the arithmetic rather than the presentation. Someone who already
/// holds dollars never pays the buy spread, so their hurdle is genuinely lower
/// than someone converting in.
enum FxStance {
  /// Holds KES and would convert into USD to invest. Crosses the spread twice.
  buying,

  /// Already holds USD, spends KES. The exit spread applies to both paths and
  /// therefore cancels, so only the yield gap is left.
  holding,

  /// Holds and spends USD. There is no currency position to take, so there is
  /// no breakeven to compute.
  hedged,
}

/// What the market is doing, used to pick which copy slot the insight bank
/// reads from. Deliberately coarse: four buckets that a reader would recognise
/// without being told, not a volatility model.
enum FxRegime {
  /// Twelve month move inside the noise band.
  calm,

  /// Steady one way move that has not yet covered the hurdle.
  drifting,

  /// Depreciating fast enough that a long USD position is winning.
  falling,

  /// Appreciating sharply. The 2024 first quarter shape.
  snapback,
}

/// How big the hurdle is relative to what the pair normally does in a year.
/// Combined with [FxStance] and [FxRegime] this gives the copy bank a stable
/// key, so the text moves with the market instead of at random.
enum FxHurdleBand { low, moderate, high }

/// A single day's quote. [bid] and [ask] are null when the source published a
/// mean only, which is the case for every row written before the CBK backfill.
class FxQuote {
  const FxQuote({
    required this.mean,
    this.bid,
    this.ask,
    this.spread = 0.015,
  })  : assert(mean > 0, 'mean must be positive'),
        assert(spread >= 0 && spread < 0.5, 'spread is a one way fraction');

  /// CBK indicative mean.
  final double mean;

  /// Measured bank buy leg, if known.
  final double? bid;

  /// Measured bank sell leg, if known.
  final double? ask;

  /// One way spread assumed when a leg is missing. Config key `fx.spread_pct`,
  /// divided by 100 before it reaches here.
  final double spread;

  /// What the user pays per dollar.
  double get askRate => ask ?? mean * (1 + spread);

  /// What the user receives per dollar.
  double get bidRate => bid ?? mean * (1 - spread);

  /// Ask expressed as a multiple of the mean. Used to project a future ask
  /// without pretending to know a future quote.
  double get askFactor => askRate / mean;

  /// Bid expressed as a multiple of the mean.
  double get bidFactor => bidRate / mean;

  /// Cost of going in and straight back out again, as a fraction. At a 1.5
  /// percent one way spread this is about 3 percent, which is most of a year
  /// of USD money market yield.
  double get roundTrip => (askFactor / bidFactor) - 1;

  /// True when both legs came from the source rather than the assumption.
  bool get measured => bid != null && ask != null;

  /// Replaces the legs with a quote the user was actually given. Passing a
  /// single figure treats it as the ask, which is what a buyer is quoted.
  FxQuote withUserQuote({double? userAsk, double? userBid}) => FxQuote(
        mean: mean,
        bid: userBid ?? bid,
        ask: userAsk ?? ask,
        spread: spread,
      );
}

/// One comparison, fully specified. Every figure on the page derives from an
/// instance of this.
class FxCase {
  const FxCase({
    required this.quote,
    required this.kesNet,
    required this.usdNet,
    required this.stance,
    this.years = 1,
  })  : assert(years > 0, 'years must be positive'),
        assert(kesNet > -1 && usdNet > -1, 'net rates are fractions');

  final FxQuote quote;

  /// Net annual KES fund rate as a fraction.
  final double kesNet;

  /// Net annual USD fund rate as a fraction.
  final double usdNet;

  final FxStance stance;
  final double years;

  /// How much further ahead the KES fund gets over the horizon on yield alone.
  /// This is the whole hurdle for a [FxStance.holding] user.
  double get growthGap =>
      math.pow((1 + kesNet) / (1 + usdNet), years).toDouble();

  /// Annualised yield gap as a fraction. At 9.22 against 3.74 this is 0.0528.
  double get annualGap => ((1 + kesNet) / (1 + usdNet)) - 1;

  /// The mean the pair has to reach by the horizon for the USD side to draw
  /// level. Null for [FxStance.hedged], where no position is being taken.
  ///
  ///   buying   ask paid now, bid received later, plus the yield gap
  ///   holding  the bid leg appears on both paths and cancels
  double? get breakeven {
    switch (stance) {
      case FxStance.buying:
        return quote.mean *
            quote.askFactor *
            growthGap /
            quote.bidFactor;
      case FxStance.holding:
        return quote.mean * growthGap;
      case FxStance.hedged:
        return null;
    }
  }

  /// Fall in the shilling implied by [breakeven], as a fraction of today.
  double? get impliedDepreciation {
    final b = breakeven;
    return b == null ? null : (b / quote.mean) - 1;
  }

  /// The same hurdle expressed per year, which is the number to compare
  /// against history. A five year hurdle of 30 percent is 5.4 percent a year.
  double? get annualisedHurdle {
    final d = impliedDepreciation;
    if (d == null) return null;
    return math.pow(1 + d, 1 / years).toDouble() - 1;
  }

  /// Which band the hurdle sits in. Thresholds are annualised so a one year
  /// and a five year view of the same market agree.
  FxHurdleBand? get hurdleBand {
    final h = annualisedHurdle;
    if (h == null) return null;
    if (h < 0.04) return FxHurdleBand.low;
    if (h < 0.08) return FxHurdleBand.moderate;
    return FxHurdleBand.high;
  }

  /// Both paths valued in KES at the horizon, assuming the pair does not move.
  ///
  /// [amount] is KES for [FxStance.buying] and USD for the other two, matching
  /// what the user actually holds.
  FxOutcome projectFlat(double amount) {
    final growKes = math.pow(1 + kesNet, years).toDouble();
    final growUsd = math.pow(1 + usdNet, years).toDouble();

    switch (stance) {
      case FxStance.buying:
        return FxOutcome(
          kesPath: amount * growKes,
          usdPath: (amount / quote.askRate) * growUsd * quote.bidRate,
        );
      case FxStance.holding:
      case FxStance.hedged:
        return FxOutcome(
          kesPath: amount * quote.bidRate * growKes,
          usdPath: amount * growUsd * quote.bidRate,
        );
    }
  }

  FxCase copyWith({
    FxQuote? quote,
    double? kesNet,
    double? usdNet,
    FxStance? stance,
    double? years,
  }) =>
      FxCase(
        quote: quote ?? this.quote,
        kesNet: kesNet ?? this.kesNet,
        usdNet: usdNet ?? this.usdNet,
        stance: stance ?? this.stance,
        years: years ?? this.years,
      );
}

/// Two paths valued in the same currency at the same moment.
class FxOutcome {
  const FxOutcome({required this.kesPath, required this.usdPath});

  final double kesPath;
  final double usdPath;

  /// Positive when converting to KES came out ahead.
  double get lead => kesPath - usdPath;
  bool get usdWins => usdPath > kesPath;
  double get best => usdWins ? usdPath : kesPath;
}

/// One month of the race chart. Both values are in KES so the two lines share
/// an axis, which is the only way the currency risk reads as a shape.
class FxRacePoint {
  const FxRacePoint({
    required this.monthIndex,
    required this.mean,
    required this.kesPath,
    required this.usdPath,
  });

  final int monthIndex;
  final double mean;
  final double kesPath;
  final double usdPath;

  bool get usdAhead => usdPath > kesPath;
}

/// One rolling window of history, and whether the USD side cleared its bar.
class FxWindow {
  const FxWindow({
    required this.startIndex,
    required this.realised,
    required this.required,
  });

  final int startIndex;

  /// What the pair actually did over the window, as a fraction.
  final double realised;

  /// What it needed to do, as a fraction, on the yields supplied.
  final double required;

  bool get usdWon => realised > required;

  /// How far past or short of the bar it landed.
  double get margin => realised - required;
}

/// The full record across a series.
class FxRecord {
  const FxRecord({required this.windows, required this.required});

  final List<FxWindow> windows;
  final double required;

  int get wins => windows.where((w) => w.usdWon).length;
  int get total => windows.length;
  double get winRate => total == 0 ? 0 : wins / total;

  /// The index of the last window the USD side won, or null if it never did.
  /// Used for the "and none since" line, which is the honest half of the story.
  int? get lastWinIndex {
    for (var i = windows.length - 1; i >= 0; i--) {
      if (windows[i].usdWon) return windows[i].startIndex;
    }
    return null;
  }
}

/// Cumulative outcome of a regular USD inflow, month by month.
class FxDripPoint {
  const FxDripPoint({
    required this.monthIndex,
    required this.convertEachMonth,
    required this.holdThenConvert,
  });

  final int monthIndex;

  /// Converted on arrival, then compounding in a KES fund.
  final double convertEachMonth;

  /// Held in a USD fund, valued at the rate ruling that month.
  final double holdThenConvert;
}

/// The maths, kept as free functions so they can be called without building a
/// case object where that would be noise.
abstract final class FxEngine {
  /// Month by month value of both paths, starting at [start] in [means].
  ///
  /// [means] is the monthly CBK mean series, oldest first. [months] is the
  /// horizon; the caller is responsible for ensuring `start + months` is in
  /// range, and an out of range call throws rather than silently truncating,
  /// because a short chart that looks complete is worse than a crash.
  static List<FxRacePoint> race({
    required FxCase fxCase,
    required List<double> means,
    required int start,
    required int months,
    required double amount,
  }) {
    if (start < 0 || start + months >= means.length) {
      throw RangeError(
        'race window $start..${start + months} outside series of ${means.length}',
      );
    }

    final q = fxCase.quote;
    final entry = means[start];
    final out = <FxRacePoint>[];

    for (var m = 0; m <= months; m++) {
      final y = m / 12;
      final growKes = math.pow(1 + fxCase.kesNet, y).toDouble();
      final growUsd = math.pow(1 + fxCase.usdNet, y).toDouble();
      final meanNow = means[start + m];

      // The exit leg is the mean of the day scaled by the same bid factor. The
      // alternative is holding today's absolute bid constant across five years
      // of history, which would be wrong in a way that flatters one side.
      final exitBid = meanNow * q.bidFactor;

      late final double kesPath;
      late final double usdPath;

      switch (fxCase.stance) {
        case FxStance.buying:
          kesPath = amount * growKes;
          usdPath = (amount / (entry * q.askFactor)) * growUsd * exitBid;
        case FxStance.holding:
        case FxStance.hedged:
          kesPath = amount * (entry * q.bidFactor) * growKes;
          usdPath = amount * growUsd * exitBid;
      }

      out.add(FxRacePoint(
        monthIndex: start + m,
        mean: meanNow,
        kesPath: kesPath,
        usdPath: usdPath,
      ));
    }
    return out;
  }

  /// Every window of [windowMonths] in [means], scored against the hurdle the
  /// supplied case implies over that same length.
  ///
  /// The hurdle is recomputed at the window length rather than reused from
  /// [fxCase], so a five year record is scored against a five year bar.
  static FxRecord rollingRecord({
    required FxCase fxCase,
    required List<double> means,
    int windowMonths = 12,
  }) {
    final scoped = fxCase.copyWith(years: windowMonths / 12);
    final need = scoped.impliedDepreciation ?? 0;
    final windows = <FxWindow>[];

    for (var i = 0; i + windowMonths < means.length; i++) {
      final realised = (means[i + windowMonths] / means[i]) - 1;
      windows.add(FxWindow(
        startIndex: i,
        realised: realised,
        required: need,
      ));
    }
    return FxRecord(windows: windows, required: need);
  }

  /// A fixed USD amount arriving every month, compared two ways.
  ///
  /// This is the case a lump sum model gets wrong. Regular inflows convert at
  /// whatever the rate was that month, which averages the entry and takes most
  /// of the timing risk out of the decision.
  static List<FxDripPoint> drip({
    required FxCase fxCase,
    required List<double> means,
    required int start,
    required int months,
    required double monthlyUsd,
  }) {
    if (start < 0 || start + months >= means.length) {
      throw RangeError(
        'drip window $start..${start + months} outside series of ${means.length}',
      );
    }

    final bidFactor = fxCase.quote.bidFactor;
    final stepKes = math.pow(1 + fxCase.kesNet, 1 / 12).toDouble();
    final stepUsd = math.pow(1 + fxCase.usdNet, 1 / 12).toDouble();

    var kesPot = 0.0;
    var usdPot = 0.0;
    final out = <FxDripPoint>[];

    for (var m = 1; m <= months; m++) {
      final meanNow = means[start + m];
      final bidNow = meanNow * bidFactor;

      // Compound what is already there, then add this month's inflow. Adding
      // first would pay a month of interest on money that has not arrived.
      kesPot = kesPot * stepKes + monthlyUsd * bidNow;
      usdPot = usdPot * stepUsd + monthlyUsd;

      out.add(FxDripPoint(
        monthIndex: start + m,
        convertEachMonth: kesPot,
        holdThenConvert: usdPot * bidNow,
      ));
    }
    return out;
  }

  /// A KES return restated in USD over the same period.
  ///
  /// This is the cheapest honest number in the whole feature: it needs no new
  /// data, and a KES fund that returned 58 percent over five years returned
  /// about 32 percent to a dollar holder. The gap is the currency, not the
  /// fund.
  static double inUsd({
    required double kesReturn,
    required double meanStart,
    required double meanEnd,
  }) {
    if (meanEnd <= 0) {
      throw ArgumentError.value(meanEnd, 'meanEnd', 'must be positive');
    }
    return (1 + kesReturn) * (meanStart / meanEnd) - 1;
  }

  /// Coarse read on what the pair is doing, from the tail of a monthly series.
  ///
  /// Needs at least 13 points. With fewer it reports [FxRegime.calm], which is
  /// the correct thing to say when there is not enough history to say anything
  /// else.
  static FxRegime regimeOf(List<double> means) {
    if (means.length < 13) return FxRegime.calm;

    final last = means.last;
    final yearAgo = means[means.length - 13];
    final year = (last / yearAgo) - 1;

    final quarterAgo = means[means.length - math.min(4, means.length)];
    final quarter = (last / quarterAgo) - 1;

    // A sharp appreciation reads as a snapback whatever the year did, because
    // it is the move that just wiped out anyone who converted at the top.
    if (quarter <= -0.05) return FxRegime.snapback;
    if (year >= 0.08) return FxRegime.falling;
    if (year.abs() < 0.02) return FxRegime.calm;
    return FxRegime.drifting;
  }

  /// Stable key for the copy bank. The insight templates are stored against
  /// this string, so a slot can be edited in admin without an app release.
  ///
  /// Shape: `fx.<stance>.<regime>.<band>`, for example `fx.holding.calm.mod`.
  /// Hedged has no hurdle, so its key omits the band.
  static String copyKey({
    required FxStance stance,
    required FxRegime regime,
    FxHurdleBand? band,
  }) {
    const bands = {
      FxHurdleBand.low: 'low',
      FxHurdleBand.moderate: 'mod',
      FxHurdleBand.high: 'high',
    };
    final head = 'fx.${stance.name}.${regime.name}';
    if (stance == FxStance.hedged || band == null) return head;
    return '$head.${bands[band]}';
  }

  /// Which template inside a slot to show today.
  ///
  /// Deterministic on the date, so the line is stable for a whole day and then
  /// moves on. Randomising per build would give a different string every time
  /// the widget rebuilt, which reads as a glitch on a screen full of numbers.
  static int rotation({required DateTime now, required int count}) {
    if (count <= 1) return 0;
    final dayOfYear =
        now.difference(DateTime(now.year)).inDays;
    return dayOfYear % count;
  }
}

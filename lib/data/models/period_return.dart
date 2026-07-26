import 'dart:math' as math;

/// What has ALREADY been taken out of a quoted number.
///
/// This enum exists because one fund manager publishes both conventions on
/// facing pages of one document. Etica's money market sheet says the yield is
/// net of fees and gross of withholding tax; its Special Multi Asset sheet says
/// the return is net of all fees and taxes. Same manager, same layout, opposite
/// answers. The app assumed the first for everything and quietly took 15% off a
/// number that had already paid it.
///
/// The value names what is already deducted, so the rule reads off the field
/// rather than out of a comment: deduct withholding tax only when [fees].
enum NetOf {
  /// Raw gross. Before the manager's fee and before tax. Rare, and always worth
  /// double-checking against the sheet when it appears.
  nothing,

  /// Net of fees, GROSS of withholding tax. The Kenyan unit trust convention
  /// and what every money market fund in the app quotes.
  fees,

  /// Net of fees AND tax. The app must not deduct anything further.
  feesAndTax;

  static NetOf? parse(String? raw) => switch (raw) {
    'nothing' => NetOf.nothing,
    'fees' => NetOf.fees,
    'fees_and_tax' => NetOf.feesAndTax,
    _ => null,
  };

  String get key => switch (this) {
    NetOf.nothing => 'nothing',
    NetOf.fees => 'fees',
    NetOf.feesAndTax => 'fees_and_tax',
  };

  /// Whether withholding tax is still owed on this number.
  ///
  /// The single question the whole enum exists to answer, and the one the app
  /// was previously answering with a hardcoded yes.
  bool get whtStillDue => this == NetOf.fees;

  /// Short label for a dense row, e.g. beside a figure in a table.
  String get shortLabel => switch (this) {
    NetOf.nothing => 'gross',
    NetOf.fees => 'net of fees',
    NetOf.feesAndTax => 'net of fees and tax',
  };
}

/// The kind of window a realized return covers.
///
/// A yield needs none of this, being per annum by definition. A realized return
/// is meaningless without it: 4.74% over a quarter and 4.74% over a year are
/// different facts that print identically, and nobody scanning a list can tell
/// them apart unless the app says which is which.
enum ReturnPeriod {
  month,
  quarter,
  half,
  year,
  ytd,

  /// A single cumulative total over the fund's whole life. NOT part of a series:
  /// charting it beside quarters would put a 259% bar next to a 4.74% one.
  sinceInception;

  static ReturnPeriod? parse(String? raw) => switch (raw) {
    'month' => ReturnPeriod.month,
    'quarter' => ReturnPeriod.quarter,
    'half' => ReturnPeriod.half,
    'year' => ReturnPeriod.year,
    'ytd' => ReturnPeriod.ytd,
    'since_inception' => ReturnPeriod.sinceInception,
    _ => null,
  };

  String get key => switch (this) {
    ReturnPeriod.month => 'month',
    ReturnPeriod.quarter => 'quarter',
    ReturnPeriod.half => 'half',
    ReturnPeriod.year => 'year',
    ReturnPeriod.ytd => 'ytd',
    ReturnPeriod.sinceInception => 'since_inception',
  };

  /// How many of these fit in a year. Null where the question is meaningless.
  ///
  /// Used ONLY to describe a period in words. It is deliberately not used to
  /// annualise: multiplying a quarter by four is the exact operation that put a
  /// 20.36% headline on a fund whose best published figure was 5.23%.
  int? get perYear => switch (this) {
    ReturnPeriod.month => 12,
    ReturnPeriod.quarter => 4,
    ReturnPeriod.half => 2,
    ReturnPeriod.year => 1,
    ReturnPeriod.ytd => null,
    ReturnPeriod.sinceInception => null,
  };

  /// Whether rows of this kind compose a chartable series.
  ///
  /// `ytd` is excluded even though it is a closed window, because it OVERLAPS
  /// the periods it contains. Etica's 10.51% year to date is its 5.02% and 5.23%
  /// quarters, and drawing all three puts the same money on the chart twice.
  bool get isSeriesMember => switch (this) {
    ReturnPeriod.month ||
    ReturnPeriod.quarter ||
    ReturnPeriod.half ||
    ReturnPeriod.year => true,
    ReturnPeriod.ytd || ReturnPeriod.sinceInception => false,
  };

  String get label => switch (this) {
    ReturnPeriod.month => 'Month',
    ReturnPeriod.quarter => 'Quarter',
    ReturnPeriod.half => 'Half year',
    ReturnPeriod.year => 'Year',
    ReturnPeriod.ytd => 'Year to date',
    ReturnPeriod.sinceInception => 'Since inception',
  };
}

/// One closed period of one fund, from the snapshot's `period_returns` array.
class PeriodReturn {
  const PeriodReturn({
    required this.fundId,
    required this.periodEnd,
    required this.period,
    required this.netPct,
    required this.netOf,
    this.grossPct,
  });

  final String fundId;

  /// YYYY-MM-DD. Kept as the raw ISO string, matching [RateHistory], so a bad
  /// date in the data cannot throw during parsing of an entire snapshot.
  final String periodEnd;

  final ReturnPeriod period;

  /// The return, as a percentage.
  ///
  /// MAY BE NEGATIVE, and nothing in this file or above it may assume otherwise.
  /// A multi-asset fund posting a down quarter is an ordinary event, and a rule
  /// that dropped the weak periods would leave a chart showing only the strong
  /// ones, which misleads far more than no chart at all.
  final double netPct;

  /// The same period before fees, when the sheet prints both. The gap between
  /// the two is the fee doing its work, made visible.
  final double? grossPct;

  /// Per row, not inherited from the fund. A manager can publish quarters net of
  /// fees and an annual figure net of fees and tax on one page.
  final NetOf netOf;

  /// Sortable key. String comparison is correct for ISO dates and needs no
  /// DateTime parse, so a malformed date sorts oddly instead of crashing.
  String get sortKey => periodEnd;

  /// The fee, in percentage points, when both figures are published.
  double? get feeDrag {
    final g = grossPct;
    return g == null ? null : g - netPct;
  }

  static PeriodReturn? fromJson(Map<String, dynamic> j) {
    final id = j['fund_id'] as String?;
    final end = j['period_end'] as String?;
    final p = ReturnPeriod.parse(j['period'] as String?);
    final net = (j['net_pct'] as num?)?.toDouble();
    if (id == null || end == null || p == null || net == null) return null;
    return PeriodReturn(
      fundId: id,
      periodEnd: end,
      period: p,
      netPct: net,
      grossPct: (j['gross_pct'] as num?)?.toDouble(),
      // Defaults to `fees`, the convention every Kenyan unit trust follows, and
      // the same default the admin writer uses. An unreadable value must not
      // become `feesAndTax`, which would suppress a tax deduction that is due.
      netOf: NetOf.parse(j['net_of'] as String?) ?? NetOf.fees,
    );
  }
}

/// Every published period for one fund, and the questions the detail page asks
/// of them.
///
/// A class rather than a bare list because every one of these accessors has a
/// rule behind it that a call site would otherwise have to remember, and the two
/// that matter most (do not mix period kinds, do not annualise) are exactly the
/// rules a hurried call site forgets.
class FundReturns {
  const FundReturns(this.all);

  /// Chronological, oldest first.
  final List<PeriodReturn> all;

  static const empty = FundReturns(<PeriodReturn>[]);

  bool get isEmpty => all.isEmpty;

  /// The manager's own cumulative total since inception, when published.
  PeriodReturn? get sinceInception {
    for (final r in all.reversed) {
      if (r.period == ReturnPeriod.sinceInception) return r;
    }
    return null;
  }

  /// The most recent year-to-date figure, when published.
  PeriodReturn? get ytd {
    for (final r in all.reversed) {
      if (r.period == ReturnPeriod.ytd) return r;
    }
    return null;
  }

  /// The period kind the chart should be drawn from.
  ///
  /// Whichever series-forming kind the fund publishes MOST of. A fund printing
  /// eight quarters and seven calendar years gets a quarterly chart, because the
  /// quarters are what its fact sheet leads with and what its peers publish.
  ///
  /// Mixing kinds on one axis is the failure this prevents: a 4.74% quarter and
  /// a 20.74% year on the same bar chart is not a comparison, it is two
  /// different questions answered at different scales in one picture.
  ReturnPeriod? get dominantPeriod {
    final counts = <ReturnPeriod, int>{};
    for (final r in all) {
      if (!r.period.isSeriesMember) continue;
      counts[r.period] = (counts[r.period] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }

  /// Every row of one kind, chronological.
  List<PeriodReturn> of(ReturnPeriod p) =>
      all.where((r) => r.period == p).toList();

  /// The chartable series: the dominant kind and nothing else.
  List<PeriodReturn> get series {
    final p = dominantPeriod;
    return p == null ? const [] : of(p);
  }

  /// Calendar years, for the gross-vs-net table. Newest first, which is how
  /// every fact sheet prints them.
  List<PeriodReturn> get years =>
      of(ReturnPeriod.year).reversed.toList(growable: false);

  /// The headline: the newest row of the dominant kind.
  PeriodReturn? get latest {
    final s = series;
    return s.isEmpty ? null : s.last;
  }

  /// Arithmetic mean of the series, which is what a fact sheet means by
  /// "quarterly average since inception".
  ///
  /// An average of returns, NOT a growth rate. See [compoundAnnualPct] for the
  /// number that describes how money actually grew, and note that the two differ:
  /// MansaX reports an 18.18% average annual net return, while the compound rate
  /// implied by its own published endpoint is about 19.3%.
  double? get averagePct {
    final s = series;
    if (s.isEmpty) return null;
    return s.fold<double>(0, (a, r) => a + r.netPct) / s.length;
  }

  /// Whether there is enough here to draw a trend.
  ///
  /// Four is the floor. Etica Special Multi Asset has two quarters, and a line
  /// through two points is not a trend, it is a line through two points. Below
  /// the floor the page states the holding period in words instead.
  bool get hasChartableSeries => series.length >= 4;

  /// Growth of [base] through the series, compounded, oldest to newest. The
  /// first element is [base] itself, so the list is one longer than the series.
  ///
  /// This is the FALLBACK path for the growth card, used only when the manager
  /// publishes no endpoint of its own. It is arithmetic on published figures
  /// rather than a forecast, but it is not the same number the manager prints:
  /// each stored percentage is rounded to two places and the rounding compounds
  /// along with the returns. On MansaX the gap is roughly 230,000 shillings on a
  /// million over seven years. Callers must label a compounded curve as derived.
  List<double> compoundedGrowth(double base) {
    final out = <double>[base];
    var v = base;
    for (final r in series) {
      v = v * (1 + r.netPct / 100);
      out.add(v);
    }
    return out;
  }

  /// Total growth multiple over the whole record: the manager's published
  /// endpoint when there is one, else the compounded series.
  ///
  /// Returns null when neither is available. 1.0 would mean the fund returned
  /// exactly nothing, which is a claim, and this function is not in a position
  /// to make it.
  ({double multiple, bool derived})? get growthMultiple {
    final published = sinceInception;
    if (published != null) {
      return (multiple: 1 + published.netPct / 100, derived: false);
    }
    final s = series;
    if (s.isEmpty) return null;
    var m = 1.0;
    for (final r in s) {
      m *= 1 + r.netPct / 100;
    }
    return (multiple: m, derived: true);
  }

  /// Compound annual growth rate implied by [growthMultiple] over [months].
  ///
  /// This is the honest "per year" figure and it is NOT what a fact sheet means
  /// by "average annual return", which is usually the arithmetic mean of the
  /// calendar years. Both are defensible; they are not the same; and only this
  /// one describes how money grew.
  double? compoundAnnualPct(int months) {
    final g = growthMultiple;
    if (g == null || months <= 0 || g.multiple <= 0) return null;
    return (math.pow(g.multiple, 12 / months).toDouble() - 1) * 100;
  }
}

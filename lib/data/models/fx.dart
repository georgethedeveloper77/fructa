/// FX rows from the snapshot. Two shapes, because they answer two questions.
///
/// [FxRate] is "what is the rate now" and is read anywhere a number gets
/// converted. [FxSeries] is "what has the rate done" and is read by one card
/// and one page. Keeping them apart is why five years of history does not ride
/// behind every currency conversion in the app.
library;

/// One day's published quote for a pair.
class FxRate {
  const FxRate({
    required this.pair,
    required this.rate,
    this.bid,
    this.ask,
    this.asOf,
  });

  /// e.g. 'USD/KES'.
  final String pair;

  /// CBK indicative mean.
  final double rate;

  /// What a bank buys the base currency from you at, when the source published
  /// it. Null on every row that came from the keyless fallback API.
  final double? bid;

  /// What a bank sells the base currency to you at, when published.
  final double? ask;

  final String? asOf;

  /// THESE LEGS ARE INTERBANK AND MUST NOT BE USED AS A RETAIL SPREAD.
  ///
  /// CBK's buy and sell are the wholesale indicative, roughly a quarter of a
  /// percent each way. On 04/01/2024 CBK printed mean 157.3912, buy 157.0000,
  /// sell 157.7824, and no walk-in customer converted at those. Feeding them
  /// into FxQuote would drop the buying hurdle by around three points and
  /// understate the cost of converting, which is most of the decision the
  /// currency card exists to price. The retail figure is the admin-editable
  /// `fx.spread_pct`, and only a quote the USER typed should ever replace it.
  ///
  /// The legs are kept because the gap between them and what a bank actually
  /// quotes IS the retail margin, which is worth showing on an assumptions
  /// list. They are a floor, not an input.
  double? get interbankSpreadPct {
    final b = bid;
    final a = ask;
    if (b == null || a == null || rate <= 0 || a < b) return null;
    return ((a - b) / 2 / rate) * 100;
  }

  static FxRate? fromJson(Map<String, dynamic> j) {
    final pair = j['pair'] as String?;
    final rate = (j['rate'] as num?)?.toDouble();
    if (pair == null || rate == null || rate <= 0) return null;
    return FxRate(
      pair: pair,
      rate: rate,
      bid: (j['bid'] as num?)?.toDouble(),
      ask: (j['ask'] as num?)?.toDouble(),
      asOf: j['as_of'] as String?,
    );
  }
}

/// Month-end history for a pair, oldest first.
///
/// Month-end rather than a monthly average, because the charts compare an entry
/// point against an exit point. An average of daily means is a rate that never
/// traded, and nobody converted at it.
class FxSeries {
  const FxSeries({
    required this.pair,
    required this.months,
    required this.mean,
    this.interbankSpreadPct,
    this.quotedDays = 0,
  });

  final String pair;

  /// 'YYYY-MM', index-aligned with [mean].
  final List<String> months;
  final List<double> mean;

  /// Mean interbank one-way spread over the window, or null when no row in it
  /// carried both legs. See the warning on [FxRate.interbankSpreadPct]: this is
  /// not the retail spread and must not be wired to one.
  final double? interbankSpreadPct;

  /// How many daily rows the spread was measured over.
  final int quotedDays;

  static const empty = FxSeries(pair: '', months: [], mean: []);

  double? get latest => mean.isEmpty ? null : mean.last;

  /// Move over the trailing [months] as a fraction, positive when the base
  /// currency strengthened against the quote currency, which for USD/KES means
  /// the shilling weakened. Null when the series is too short to say, because
  /// reporting zero would read as "unchanged" rather than "unknown".
  double? moveOver(int monthsBack) {
    final i = mean.length - 1 - monthsBack;
    if (i < 0 || mean.isEmpty || mean[i] <= 0) return null;
    return (mean.last / mean[i]) - 1;
  }

  static FxSeries? fromJson(Map<String, dynamic> j) {
    final pair = j['pair'] as String?;
    if (pair == null) return null;

    final months = (j['months'] as List? ?? const [])
        .whereType<String>()
        .toList();
    final mean = (j['mean'] as List? ?? const [])
        .whereType<num>()
        .map((n) => n.toDouble())
        .toList();

    // A ragged pair would misdate every point on the chart. Truncating to the
    // shorter of the two is wrong in a way nobody would notice, so a mismatch
    // drops the series entirely and the card hides itself.
    if (months.length != mean.length || mean.isEmpty) return null;

    return FxSeries(
      pair: pair,
      months: months,
      mean: mean,
      interbankSpreadPct: (j['interbank_spread_pct'] as num?)?.toDouble(),
      quotedDays: (j['quoted_days'] as num?)?.toInt() ?? 0,
    );
  }
}

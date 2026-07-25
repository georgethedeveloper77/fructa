/// One month of the market, for one fund type in one currency.
///
/// Published by the snapshot builder from `rate_history`, where the DATES are.
/// It cannot be derived on the phone: `Fund.spark` is up to twenty trailing
/// points with no dates attached, and managers file on different cadences, so
/// index three is a different month for every fund. Averaging sparks across a
/// category draws a line nobody measured.
class MarketPoint {
  const MarketPoint({
    required this.fundType,
    required this.currency,
    required this.month,
    required this.median,
    required this.lo,
    required this.hi,
    required this.funds,
  });

  final String fundType;
  final String currency;

  /// First of the month, local.
  final DateTime month;

  /// Gross median across the funds counted in [funds]. Withholding is applied
  /// app-side by the caller, per the standing rule that the database stores
  /// gross so the tax rate can change without a republish.
  final double median;
  final double lo;
  final double hi;

  /// How many funds stood behind the median that month.
  ///
  /// Load-bearing, not metadata. It is the gate the chart draws with: a month
  /// carried by five managers is a sample, not the market, and it misses in
  /// both directions. In the July 2026 data the eight-fund money market month
  /// printed high (10.14 against 9.78 and 9.50) while the five-fund special
  /// month printed low (7.61 against 11.37). Neither belongs on the line.
  final int funds;

  /// Below this the point is drawn, but not connected.
  static const reliable = 10;

  bool get isReliable => funds >= reliable;

  /// `median`, `lo` and `hi` do not agree on type coming out of Postgres:
  /// percentile_cont returns double precision and arrives as a JSON number,
  /// while min/max keep the column's numeric type and arrive as a STRING. A
  /// plain `as num` cast throws on the second. Parse both shapes here so no
  /// reader has to know.
  static double? _n(dynamic v) => v is num
      ? v.toDouble()
      : (v is String ? double.tryParse(v) : null);

  static MarketPoint? fromJson(Map<String, dynamic> j) {
    final type = j['fund_type'] as String?;
    final ccy = j['currency'] as String?;
    final month = DateTime.tryParse((j['month'] ?? '') as String);
    final median = _n(j['median']);
    if (type == null || ccy == null || month == null || median == null) {
      return null;
    }
    return MarketPoint(
      fundType: type,
      currency: ccy,
      month: month,
      median: median,
      lo: _n(j['lo']) ?? median,
      hi: _n(j['hi']) ?? median,
      funds: (j['funds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Every published month, indexed by the pair the chart asks for.
class MarketHistory {
  const MarketHistory(this._byKey);

  final Map<String, List<MarketPoint>> _byKey;

  static const empty = MarketHistory({});

  static String keyOf(String fundType, String currency) =>
      '$fundType|$currency';

  /// Oldest first. Empty when that pair has never been published, which is the
  /// normal state for a fund type only two managers quote.
  List<MarketPoint> series(String fundType, String currency) =>
      _byKey[keyOf(fundType, currency)] ?? const [];

  /// The pairs that carry enough history to draw at all, so the page can build
  /// its tabs from what exists rather than from a hardcoded list that goes
  /// stale the first time a category is added.
  Iterable<String> get keys => _byKey.keys;

  bool get isEmpty => _byKey.isEmpty;

  factory MarketHistory.fromList(List<dynamic> rows) {
    final by = <String, List<MarketPoint>>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final p = MarketPoint.fromJson(r.cast<String, dynamic>());
      if (p == null) continue;
      (by[keyOf(p.fundType, p.currency)] ??= []).add(p);
    }
    for (final l in by.values) {
      l.sort((a, b) => a.month.compareTo(b.month));
    }
    return MarketHistory(by);
  }
}

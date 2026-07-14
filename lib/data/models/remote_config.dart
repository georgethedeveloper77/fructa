/// A benchmark figure published in the snapshot config (inflation, CBR, T-bill).
class Benchmark {
  const Benchmark(this.rate, {this.asOf, this.source});
  final double rate;
  final String? asOf;
  final String? source;
}

/// One fund-type slice of the CMA market split  AUM and its share of the
/// whole CIS market. Published under `market.aum_by_fund_type`.
class MarketFundType {
  const MarketFundType(this.type, this.aumKes, this.share);
  final String type; // mmf | fixed_income | equity | balanced | special
  final double aumKes;
  final double share; // percent of total market AUM
}

/// One asset-class slice of the CMA market allocation  where the whole
/// market's money actually sits (Table 9). Published under
/// `market.asset_classes`. Share only: the CIS report gives allocation
/// percentages, not per-class AUM.
class MarketAssetClass {
  const MarketAssetClass(this.clazz, this.share);
  final String clazz; // gok | fixed_deposits | cash | unlisted | listed | offshore | other_cis | alternative
  final double share; // percent of total market assets
}

/// Admin-editable key/value config, published inside the snapshot (`config`).
/// Every getter takes a baked-in fallback so the app renders correctly with
/// an old snapshot, an empty table, or a bad value  remote config can only
/// override copy/flags/benchmarks, never break the UI.
class RemoteConfig {
  const RemoteConfig(this._values);
  final Map<String, dynamic> _values;

  static const empty = RemoteConfig({});

  String string(String key, String fallback) {
    final v = _values[key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  bool flag(String key, bool fallback) {
    final v = _values[key];
    return v is bool ? v : fallback;
  }

  double number(String key, double fallback) {
    final v = _values[key];
    return v is num ? v.toDouble() : fallback;
  }

  /// JSON array of strings (e.g. `search.suggestions`). Non-string entries
  /// are dropped; anything malformed falls back whole.
  List<String> stringList(String key, List<String> fallback) {
    final v = _values[key];
    if (v is! List) return fallback;
    final out = v.whereType<String>().where((s) => s.isNotEmpty).toList();
    return out.isEmpty ? fallback : out;
  }

  // ── Benchmarks ──────────────────────────────────────────────────────────
  // Stored as objects: {"rate":6.7,"as_of":"2026-05-31","source":"KNBS"}.

  /// Full benchmark object (rate + as_of + source), or null if unset/malformed.
  Benchmark? benchmark(String key) {
    final v = _values[key];
    if (v is Map && v['rate'] is num) {
      return Benchmark(
        (v['rate'] as num).toDouble(),
        asOf: v['as_of'] as String?,
        source: v['source'] as String?,
      );
    }
    return null;
  }

  /// Just the rate, with a baked fallback so the triad always computes.
  double benchmarkRate(String key, double fallback) =>
      benchmark(key)?.rate ?? fallback;

  // Convenience  fallbacks are the live figures at build time (Jun 2026).
  double get inflationPct => benchmarkRate('benchmark.inflation', 6.7);
  double get cbrPct => benchmarkRate('benchmark.cbr', 8.75);
  double get tbill91Pct => benchmarkRate('benchmark.tbill_91', 8.71);
  double get tbill182Pct => benchmarkRate('benchmark.tbill_182', 8.60);
  double get tbill364Pct => benchmarkRate('benchmark.tbill_364', 8.87);
  double get whtPct => benchmarkRate('benchmark.wht_pct', 15);

  /// Inflation for a given CURRENCY, or null when none is published for it.
  ///
  /// KES reads `benchmark.inflation`, the long-standing key, unrenamed because
  /// the snapshot contract is shared with the admin registry and the landing
  /// page. Every other currency reads `benchmark.inflation_<ccy>`, so USD reads
  /// `benchmark.inflation_usd` (BLS CPI-U, all items, 12-month).
  ///
  /// A foreign currency with no seeded CPI returns null and the caller shows
  /// nothing. It deliberately does NOT fall back to the Kenyan figure: a
  /// dollar yield deflated by Kenyan inflation silently assumes the shilling is
  /// pegged to the dollar, and it is not, having run from 160 to 129 inside
  /// eighteen months. The number that would answer the question in KES terms
  /// needs the exchange-rate move as well, which is a fact with a date on it and
  /// never a forecast. A missing figure is honest. A wrong one is not.
  ///
  /// KES keeps its baked fallback, so an old snapshot still renders a real
  /// return on every Kenyan fund.
  double? inflationFor(String currency) {
    if (currency == 'KES') return inflationPct;
    return benchmark('benchmark.inflation_${currency.toLowerCase()}')?.rate;
  }

  /// Withholding tax on DIVIDENDS from a listed company: 5% for a resident,
  /// and it is a FINAL tax.
  ///
  /// This is not [whtPct]. That one is 15%, and it is the rate on interest,
  /// which is what a money market fund and a T-bill pay you. Dividends are
  /// taxed at a third of it. Using the interest rate on a dividend, or the
  /// other way round, is exactly the error the Learn course spends a lesson on,
  /// and it is the difference between a stock looking worse than a T-bill and
  /// looking better.
  ///
  /// Config-overridable like every other benchmark, so a Finance Act can be
  /// answered by editing a row rather than shipping a release.
  double get dividendWhtPct => benchmarkRate('benchmark.dividend_wht_pct', 5);

  // ── Market (CMA quarterly) ────────────────────────────────────────────────
  // market.aum_by_fund_type:
  //   {"as_of":"2026-03-31","source":"CMA CIS Q1 2026","total_kes":…,
  //    "types":[{"type":"mmf","aum_kes":…,"share":51.9}, …]}
  //
  // Authoritative market split by AUM. This is the *market*  the funds fructa
  // tracks are a subset, so a count of them would misstate it (MMF reads ~95%
  // by count but is ~52% by AUM). Baked Q1-2026 fallback so the donut always
  // renders; SACCOs are a separate (SASRA) market and are not in this CIS set.

  static const _marketFallback = [
    MarketFundType('mmf', 442199966997, 51.9),
    MarketFundType('special', 203565448012, 23.9),
    MarketFundType('fixed_income', 198991286618, 23.4),
    MarketFundType('equity', 4751495471, 0.6),
    MarketFundType('balanced', 2200313187, 0.3),
  ];

  /// Market split by fund type (AUM), sorted by share desc. Falls back to the
  /// baked Q1-2026 figures when the key is unset or malformed.
  List<MarketFundType> marketFundTypes() {
    final v = _values['market.aum_by_fund_type'];
    if (v is Map && v['types'] is List) {
      final out = <MarketFundType>[];
      for (final e in (v['types'] as List)) {
        if (e is Map && e['type'] is String && e['share'] is num) {
          out.add(
            MarketFundType(
              e['type'] as String,
              (e['aum_kes'] as num?)?.toDouble() ?? 0,
              (e['share'] as num).toDouble(),
            ),
          );
        }
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => b.share.compareTo(a.share));
        return out;
      }
    }
    return _marketFallback;
  }

  String? get marketAsOf {
    final v = _values['market.aum_by_fund_type'];
    return v is Map ? v['as_of'] as String? : null;
  }

  String? get marketSource {
    final v = _values['market.aum_by_fund_type'];
    return v is Map ? v['source'] as String? : null;
  }

  // market.asset_classes:
  //   {"as_of":"2026-03-31","source":"CMA CIS Q1 2026",
  //    "classes":[{"class":"gok","share":44.0}, …]}
  //
  // Where the whole market's money sits (CIS Table 9). Feeds the asset-class
  // view on the Market-by-AUM page. Baked Q1-2026 fallback so it always renders.

  static const _assetClassFallback = [
    MarketAssetClass('gok', 44.0),
    MarketAssetClass('fixed_deposits', 23.5),
    MarketAssetClass('cash', 14.1),
    MarketAssetClass('unlisted', 8.8),
    MarketAssetClass('listed', 7.0),
    MarketAssetClass('offshore', 1.9),
    MarketAssetClass('other_cis', 0.4),
    MarketAssetClass('alternative', 0.3),
  ];

  /// Market allocation by asset class, sorted by share desc. Falls back to the
  /// baked Q1-2026 figures when the key is unset or malformed.
  List<MarketAssetClass> marketAssetClasses() {
    final v = _values['market.asset_classes'];
    if (v is Map && v['classes'] is List) {
      final out = <MarketAssetClass>[];
      for (final e in (v['classes'] as List)) {
        if (e is Map && e['class'] is String && e['share'] is num) {
          out.add(
            MarketAssetClass(
              e['class'] as String,
              (e['share'] as num).toDouble(),
            ),
          );
        }
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => b.share.compareTo(a.share));
        return out;
      }
    }
    return _assetClassFallback;
  }

  String? get marketAssetsAsOf {
    final v = _values['market.asset_classes'];
    return v is Map ? v['as_of'] as String? : null;
  }

  String? get marketAssetsSource {
    final v = _values['market.asset_classes'];
    return v is Map ? v['source'] as String? : null;
  }
}

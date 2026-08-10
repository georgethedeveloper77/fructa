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

/// How big the whole CIS market is and how fast it grew last quarter.
/// Published under `market.cis_size`.
///
/// Separate from [MarketFundType] on purpose. The fund-type split answers where
/// the money sits; this answers how much of it there is, which the split cannot
/// because the app only ever renders shares from it. It also carries the prior
/// period, so the card can state the quarter move in shillings rather than in a
/// percentage nobody can picture.
class MarketSize {
  const MarketSize({
    required this.totalKes,
    this.priorKes,
    this.changePct,
    this.schemeCount,
    this.asOf,
    this.priorAsOf,
    this.source,
  });

  final double totalKes;
  final double? priorKes;
  final double? changePct;
  final int? schemeCount;
  final String? asOf;
  final String? priorAsOf;
  final String? source;

  /// New money since the prior period, in shillings. Null when no prior figure
  /// is published, and never derived from [changePct]: a rounded percentage
  /// reflated into a shilling amount invents precision the source never had.
  double? get addedKes {
    final p = priorKes;
    return p == null ? null : totalKes - p;
  }
}

/// The NSE at a quarter end, from the CMA quarterly bulletin. Published under
/// `market.nse`.
///
/// EVERY FIGURE HERE IS A QUARTER-END READING and the Stocks page renders it
/// directly above end-of-day prices. Anything consuming this must say which
/// period it belongs to, because by the time the next bulletin lands these are
/// months old while the rows beneath them moved this morning.
class NseSnapshot {
  const NseSnapshot({
    required this.nasi,
    required this.nse20,
    this.nasiQoqPct,
    this.nse20QoqPct,
    this.bondIndex = 0,
    this.bondIndexQoqPct,
    this.marketCapKesBn = 0,
    this.marketCapQoqPct,
    this.listedCounters,
    this.foreignParticipationPct = 0,
    this.asOf,
    this.source,
  });

  final double nasi;
  final double nse20;
  final double? nasiQoqPct;
  final double? nse20QoqPct;
  final double bondIndex;
  final double? bondIndexQoqPct;

  /// In BILLIONS of shillings, which is how the bulletin prints it. Do not
  /// store raw shillings here or the formatter will read 3,761.74 as pocket
  /// change.
  final double marketCapKesBn;
  final double? marketCapQoqPct;

  /// Counters listed at the exchange, including suspensions, REITs and ETFs.
  /// This is NOT the number of stocks the app carries and the two must never be
  /// printed next to each other.
  final int? listedCounters;

  final double foreignParticipationPct;
  final String? asOf;
  final String? source;
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
  double get inflationPct => benchmarkRate('benchmark.inflation', 6.5);
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

  // -- FX (currency comparison) ---------------------------------------------

  /// The RETAIL one-way spread a Kenyan bank charges over the CBK indicative
  /// mean, as a percentage. Buying dollars costs mean x (1 + this); selling
  /// them back returns mean x (1 - this).
  ///
  /// THIS IS NOT CBK's PUBLISHED SPREAD, AND IT MUST NEVER BE WIRED TO IT.
  /// CBK's buy and sell legs are the interbank indicative, about a quarter of a
  /// percent each way. On 04/01/2024 CBK printed mean 157.3912, buy 157.0000,
  /// sell 157.7824, and no walk-in customer converted at those rates. Using
  /// them here would drop the one year buying hurdle from roughly 140.17 to
  /// 137.40 and understate the cost of converting by about three points, which
  /// is most of the decision the currency card exists to price.
  ///
  /// It is an ASSUMPTION and the card says so. A user who types the quote their
  /// own bank gave them replaces it, and that is always the better number,
  /// because a real quote depends on their branch, their amount and whether
  /// they negotiated, none of which any published feed knows.
  ///
  /// Clamped, because a config typo here silently rewrites every figure on the
  /// currency surface rather than failing visibly.
  double get fxSpreadPct => number('fx.spread_pct', 1.5).clamp(0.0, 10.0);

  /// Which pair the currency comparison runs on. One key so a future KES/GBP
  /// or KES/EUR view needs no code change.
  String get fxPair => string('fx.pair', 'USD/KES');

  // ── Market size (CMA quarterly) ──────────────────────────────────────────
  // market.cis_size:
  //   {"as_of":"2026-03-31","source":"CMA QSB 67/2026",
  //    "total_kes":851708510285,"prior_kes":756266044500,
  //    "prior_as_of":"2025-12-31","change_pct":12.6,"scheme_count":43}

  static const _sizeFallback = MarketSize(
    totalKes: 851708510285,
    priorKes: 756266044500,
    changePct: 12.6,
    schemeCount: 43,
    asOf: '2026-03-31',
    priorAsOf: '2025-12-31',
    source: 'CMA QSB 67/2026',
  );

  /// Total CIS market size, or the baked Q1-2026 figure when the key is unset
  /// or malformed. Never null, because the card that reads it is not optional.
  MarketSize? marketSize() {
    final v = _values['market.cis_size'];
    if (v is Map && v['total_kes'] is num) {
      return MarketSize(
        totalKes: (v['total_kes'] as num).toDouble(),
        priorKes: (v['prior_kes'] as num?)?.toDouble(),
        changePct: (v['change_pct'] as num?)?.toDouble(),
        schemeCount: (v['scheme_count'] as num?)?.toInt(),
        asOf: v['as_of'] as String?,
        priorAsOf: v['prior_as_of'] as String?,
        source: v['source'] as String?,
      );
    }
    return _sizeFallback;
  }

  // ── NSE quarter end (CMA quarterly) ──────────────────────────────────────
  // market.nse:
  //   {"as_of":"2026-06-30","source":"CMA QSB 67/2026","nasi":224.15,
  //    "nasi_qoq_pct":15.05,"nse_20":3755.44,"nse_20_qoq_pct":9.44,
  //    "bond_index":1129.57,"bond_index_qoq_pct":-4.89,
  //    "market_cap_kes_bn":3761.74,"market_cap_qoq_pct":16.44,
  //    "listed_counters":71,"foreign_participation_pct":25.58}

  static const _nseFallback = NseSnapshot(
    nasi: 224.15,
    nse20: 3755.44,
    nasiQoqPct: 15.05,
    nse20QoqPct: 9.44,
    bondIndex: 1129.57,
    bondIndexQoqPct: -4.89,
    marketCapKesBn: 3761.74,
    marketCapQoqPct: 16.44,
    listedCounters: 71,
    foreignParticipationPct: 25.58,
    asOf: '2026-06-30',
    source: 'CMA QSB 67/2026',
  );

  /// NSE quarter-end figures, falling back to the baked Q2-2026 reading. Both
  /// index levels are required: a card with one index and a hole in it is worse
  /// than the baked pair, which at least agree with each other.
  NseSnapshot? nse() {
    final v = _values['market.nse'];
    if (v is Map && v['nasi'] is num && v['nse_20'] is num) {
      return NseSnapshot(
        nasi: (v['nasi'] as num).toDouble(),
        nse20: (v['nse_20'] as num).toDouble(),
        nasiQoqPct: (v['nasi_qoq_pct'] as num?)?.toDouble(),
        nse20QoqPct: (v['nse_20_qoq_pct'] as num?)?.toDouble(),
        bondIndex: (v['bond_index'] as num?)?.toDouble() ?? 0,
        bondIndexQoqPct: (v['bond_index_qoq_pct'] as num?)?.toDouble(),
        marketCapKesBn: (v['market_cap_kes_bn'] as num?)?.toDouble() ?? 0,
        marketCapQoqPct: (v['market_cap_qoq_pct'] as num?)?.toDouble(),
        listedCounters: (v['listed_counters'] as num?)?.toInt(),
        foreignParticipationPct:
            (v['foreign_participation_pct'] as num?)?.toDouble() ?? 0,
        asOf: v['as_of'] as String?,
        source: v['source'] as String?,
      );
    }
    return _nseFallback;
  }
}

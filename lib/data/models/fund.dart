class Fund {
  final String id;
  final String name;
  final String manager;
  final String
  category; // legacy: mmf_kes | mmf_usd | bond | tbill | sacco | stock
  final String? fundType; // mmf | fixed_income | equity | balanced | special
  final String currency; // KES | USD
  final String?
  basis; // yield | nav | none  whether a single rate is meaningful
  final bool retail; // consumer-visible cut (~27 MMFs), vs the dormant tail
  final double? currentRate;
  final bool taxFree;
  final num? minInvest;
  final num? mgmtFee;
  final String? siteUrl;
  final String? investUrl;
  final String? contactUrl;
  final String? logoDomain;
  final String? companyId;
  final bool verified;
  final bool featured;

  // ── Profile & terms (snapshot 0026)  static fact-sheet fields. All
  // nullable; an unseeded fund reads them as null and the detail page degrades
  // to its prior shape (no credentials strip, no benchmark line, thinner terms).
  final String? inceptionDate; // YYYY-MM-DD
  final String? benchmarkKey; // tbill_91 | tbill_182 | tbill_364 | cbr
  final double? expenseRatio; // all-in TER, % p.a.
  final double? redemptionFee; // exit fee, %
  final int? lockInMonths; // 0/null = no lock-in
  final num? topUpMin; // subsequent top-up minimum
  final String? objective; // one-line fund aim

  // ── Trailing performance (snapshot 0027)  latest standing from the
  // manager's monthly fact sheet. Per-horizon benchmark so vs-benchmark is
  // on-basis. Nullable per horizon: a young fund with no 5Y just shows what it
  // has, and a fund with none seeded hides the performance card entirely.
  final double? returnYtd; // fund, %
  final double? return1y; // fund, annualised %
  final double? return3y;
  final double? return5y;
  final double? bench1y; // stated benchmark, annualised %
  final double? bench3y;
  final double? bench5y;
  final double? bestMonth; // best monthly return, trailing 12 mo, %
  final double? worstMonth; // worst monthly return, trailing 12 mo, %
  final String? returnsAsOf; // YYYY-MM-DD, fact-sheet month

  /// C2  compact sparkline (≤20 trailing points) published inside the
  /// snapshot, so list tiles don't fetch per-fund history. Empty when the
  /// snapshot predates the field or the fund has <2 history points.
  final List<double> spark;

  const Fund({
    required this.id,
    required this.name,
    required this.manager,
    required this.category,
    required this.currency,
    this.fundType,
    this.basis,
    this.retail = true,
    this.currentRate,
    this.taxFree = false,
    this.minInvest,
    this.mgmtFee,
    this.siteUrl,
    this.investUrl,
    this.contactUrl,
    this.logoDomain,
    this.companyId,
    this.verified = false,
    this.featured = false,
    this.inceptionDate,
    this.benchmarkKey,
    this.expenseRatio,
    this.redemptionFee,
    this.lockInMonths,
    this.topUpMin,
    this.objective,
    this.returnYtd,
    this.return1y,
    this.return3y,
    this.return5y,
    this.bench1y,
    this.bench3y,
    this.bench5y,
    this.bestMonth,
    this.worstMonth,
    this.returnsAsOf,
    this.spark = const [],
  });

  factory Fund.fromJson(Map<String, dynamic> j) => Fund(
    id: j['id'] as String,
    name: j['name'] as String,
    manager: (j['manager'] ?? '') as String,
    // category is legacy + nullable in newer snapshots  never assume non-null.
    category: (j['category'] ?? '') as String,
    fundType: j['fund_type'] as String?,
    currency: j['currency'] as String,
    basis: j['basis'] as String?,
    retail: (j['retail'] ?? true) as bool,
    currentRate: (j['current_rate'] as num?)?.toDouble(),
    taxFree: (j['tax_free'] ?? false) as bool,
    minInvest: j['min_invest'] as num?,
    mgmtFee: j['mgmt_fee'] as num?,
    siteUrl: j['site_url'] as String?,
    investUrl: j['invest_url'] as String?,
    contactUrl: j['contact_url'] as String?,
    logoDomain: j['logo_domain'] as String?,
    companyId: j['company_id'] as String?,
    verified: (j['verified'] ?? false) as bool,
    featured: (j['featured'] ?? false) as bool,
    inceptionDate: j['inception_date'] as String?,
    benchmarkKey: j['benchmark_key'] as String?,
    expenseRatio: (j['expense_ratio'] as num?)?.toDouble(),
    redemptionFee: (j['redemption_fee'] as num?)?.toDouble(),
    lockInMonths: (j['lock_in_months'] as num?)?.toInt(),
    topUpMin: j['top_up_min'] as num?,
    objective: j['objective'] as String?,
    returnYtd: (j['return_ytd'] as num?)?.toDouble(),
    return1y: (j['return_1y'] as num?)?.toDouble(),
    return3y: (j['return_3y'] as num?)?.toDouble(),
    return5y: (j['return_5y'] as num?)?.toDouble(),
    bench1y: (j['bench_1y'] as num?)?.toDouble(),
    bench3y: (j['bench_3y'] as num?)?.toDouble(),
    bench5y: (j['bench_5y'] as num?)?.toDouble(),
    bestMonth: (j['best_month'] as num?)?.toDouble(),
    worstMonth: (j['worst_month'] as num?)?.toDouble(),
    returnsAsOf: j['returns_as_of'] as String?,
    spark: ((j['spark'] as List?) ?? const [])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList(),
  );

  // ── Rate triad ────────────────────────────────────────────────────────────
  // gross = currentRate; net + real are derived, never stored, so a benchmark
  // change reprices the whole board without a re-scrape. whtPct / inflationPct
  // come from RemoteConfig.benchmark(...).

  /// Whether this fund quotes a single annual yield. MMF + Fixed Income do;
  /// Equity/Balanced/Special (basis 'none'/'nav') show AUM/composition instead.
  /// Missing basis (older snapshot) defaults to true for back-compat.
  bool get showsYield => (basis ?? 'yield') == 'yield';

  double? get grossRate => currentRate;

  /// After 15% withholding tax (unless the fund is tax-free). Reproduces the
  /// "After Tax" column exactly.
  double? netRate(double whtPct) {
    final g = currentRate;
    if (g == null) return null;
    return taxFree ? g : g * (1 - whtPct / 100);
  }

  /// Real return after inflation: (1+gross)/(1+infl) − 1.
  double? realRate(double inflationPct) {
    final g = currentRate;
    if (g == null) return null;
    return ((1 + g / 100) / (1 + inflationPct / 100) - 1) * 100;
  }

  // ── Profile helpers (0026) ─────────────────────────────────────────────────

  /// Snapshot config key for this fund's stated benchmark, e.g.
  /// 'benchmark.tbill_364'. Feeds RemoteConfig.benchmark(...). Null when unset.
  String? get benchmarkConfigKey =>
      benchmarkKey == null ? null : 'benchmark.$benchmarkKey';

  /// Whole years since inception, or null when unknown/unparseable.
  int? get yearsOperating {
    final iso = inceptionDate;
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return null;
    final now = DateTime.now();
    var y = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) y--;
    return y < 0 ? null : y;
  }

  /// No lock-in and no exit fee  the "easy access" case. Only meaningful once
  /// at least one liquidity term is seeded (see the detail page's guard).
  bool get freelyRedeemable =>
      (lockInMonths == null || lockInMonths == 0) &&
      (redemptionFee == null || redemptionFee == 0);

  // ── Performance helper (0027) ──────────────────────────────────────────────

  /// True when any trailing return or the monthly band is seeded  the
  /// performance card renders only then, never an empty table.
  bool get hasReturns =>
      returnYtd != null ||
      return1y != null ||
      return3y != null ||
      return5y != null ||
      (bestMonth != null && worstMonth != null);
}

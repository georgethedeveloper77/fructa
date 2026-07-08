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
}

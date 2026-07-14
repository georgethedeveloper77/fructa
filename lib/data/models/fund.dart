/// What a fund's tile leads with, and WHAT KIND OF NUMBER it is.
///
/// This type exists because [Fund] can hand out two doubles that print
/// identically and mean opposite things.
///
///   `currentRate` of 13.74 is a YIELD. Forward income the fund is paying now,
///   gross of a 15% withholding tax, and it compounds.
///
///   `return1y` of 22.4 is a REALISED TOTAL RETURN. What a unit price already
///   did. Already net of everything the fund paid, and perfectly capable of
///   being negative next year.
///
/// Rendered as bare percentages the two are indistinguishable, and a reader
/// scanning a list will rank them against each other. They cannot be ranked
/// against each other.
///
/// This is the same defect [Sacco] solved by REFUSING to expose a `rate` getter:
/// "any such getter is one refactor away from being the number a tile prints
/// without a label." Fund cannot take that route, because `currentRate` is
/// load-bearing across every money-market surface. So it takes the
/// machine-checked route instead: the headline cannot leave the model without
/// its kind attached, and `sealed` makes the compiler force every consumer,
/// tile, hero, peer bar, signal, to handle all three cases or fail to build.
sealed class Headline {
  const Headline();
}

/// An annual rate the fund is paying now. Money market, and any yielding
/// Special. Compounds, and is taxed.
final class YieldHeadline extends Headline {
  const YieldHeadline(this.gross);
  final double gross;
}

/// What the unit price already DID over [period]. Never a forecast, and never
/// taxed a second time: a NAV return is already net of everything the fund paid,
/// so pointing `engine/tax.dart` at it would understate every equity fund by a
/// sixth.
final class ReturnHeadline extends Headline {
  const ReturnHeadline(this.pct, {this.period = '1Y'});
  final double pct;
  final String period;
}

/// No number, and the reason there is none. NOT a zero. A fund whose manager has
/// not published a price does not have a price of zero, exactly as a share that
/// did not trade did not trade at nothing (see [Stock.hasPrice]).
final class NoHeadline extends Headline {
  const NoHeadline(this.reason);

  /// Shown under the dash, in place of the label a real figure would wear.
  final String reason;
}

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

  // ── Priced (NAV) fields  the unit price a `basis == 'nav'` fund quotes
  // instead of a yield (bond/equity/priced special), its as-of date, and an
  // optional income distribution %. All null for a yield fund, so the detail
  // page's yield path is untouched.
  final double? pricePerUnit; // NAV per unit, in the fund's own currency
  final String? priceAsOf; // YYYY-MM-DD, quote/fact-sheet date of the price
  final double? distributionPct; // income distribution / interest %, e.g. 4.00

  // ── Bond-fund fields (0070) ───────────────────────────────────────────────

  /// Modified duration, in years. THE number for a bond fund, and the reason one
  /// paying 5.1% income can post a NEGATIVE total return while one paying 4.4%
  /// posts +12.6%: rates up 1 point, unit price down roughly this many percent.
  ///
  /// Null means unknown and renders as unknown. It never renders as zero, which
  /// would claim the fund is insensitive to rates, which is a claim about a bond
  /// fund that is essentially never true.
  final double? durationYears;

  /// Share of the portfolio by credit standing, percentages summing to ~100.
  /// Keys: gov, aa, a, bbb, unrated. Null when unseeded.
  ///
  /// A government cannot run out of shillings. A company can. Everything that is
  /// not `gov` is where the extra income comes from, and it is also the part that
  /// can default.
  final Map<String, double>? creditQuality;

  /// Fund size, in the fund's OWN currency (see [currency]). Never
  /// KES-converted: converting at write time would freeze an exchange rate into
  /// stored data, and a dollar fund's recorded size would then drift every day
  /// the shilling moved without the fund changing at all.
  ///
  /// This means a USD figure and a KES figure are NOT comparable as raw numbers.
  /// Read naively, a KES 3.8B fund looks 3,304 times the size of a USD 1.15M
  /// fund; it is about 26 times the size, and the whole error is the exchange
  /// rate. Compare or aggregate across currencies only via FX, at read time.
  final double? aumNative;

  /// C2  compact sparkline (≤20 trailing points) published inside the
  /// snapshot, so list tiles don't fetch per-fund history. Empty when the
  /// snapshot predates the field or the fund has <2 history points.
  ///
  /// A RATE series, always. Built from `rate_history`, so it is empty on every
  /// NAV fund (which has no rate and therefore no rate history).
  final List<double> spark;

  /// The same idea for a priced fund: a PRICE series, built from `nav_history`.
  ///
  /// A separate field on purpose. Letting `spark` hold a rate for some funds and
  /// a price for others would be a number whose unit is decided by a neighbouring
  /// column, which is precisely the defect that put "KES 3.80 billion" on one
  /// fund and a naked "1150000" on another. Two series, two names, no shared slot,
  /// and no widget can draw a price against a percent axis by accident.
  final List<double> navSpark;

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
    this.pricePerUnit,
    this.priceAsOf,
    this.distributionPct,
    this.aumNative,
    this.durationYears,
    this.creditQuality,
    this.spark = const [],
    this.navSpark = const [],
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
    pricePerUnit: (j['price_per_unit'] as num?)?.toDouble(),
    priceAsOf: j['price_as_of'] as String?,
    distributionPct: (j['distribution_pct'] as num?)?.toDouble(),
    aumNative: (j['aum_native'] as num?)?.toDouble(),
    durationYears: (j['duration_years'] as num?)?.toDouble(),
    creditQuality: _credit(j['credit_quality']),
    spark: ((j['spark'] as List?) ?? const [])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList(),
    navSpark: ((j['nav_spark'] as List?) ?? const [])
        .whereType<num>()
        .map((v) => v.toDouble())
        .toList(),
  );

  /// Parsed defensively: a missing or malformed jsonb yields null and the credit
  /// section hides itself, rather than rendering a fabricated split.
  static Map<String, double>? _credit(Object? raw) {
    if (raw is! Map) return null;
    final m = <String, double>{};
    raw.forEach((k, v) {
      if (k is String && v is num && v > 0) m[k] = v.toDouble();
    });
    return m.isEmpty ? null : m;
  }

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

  /// Real return after inflation, Fisher: (1 + net) / (1 + infl) - 1.
  ///
  /// Deflates the NET rate, not the gross. The chip sits directly beside
  /// "NET (15% WHT)" and a reader takes the row as a progression (gross, then
  /// net, then after inflation too), so deflating the gross quietly hands back
  /// the tax and overstates what the holder actually keeps: at a 13.74% gross
  /// it read +6.60% when the honest figure is +4.67%.
  ///
  /// [inflationPct] must be the inflation of THIS fund's own currency. Kenyan
  /// CPI does not deflate a dollar fund, and the answer that would is not a
  /// deflation at all: it needs the exchange-rate move as well. The caller
  /// supplies the right figure for the currency, and shows nothing when it has
  /// none, rather than reaching for the one CPI it happens to hold.
  double? realRate(double inflationPct, {required double whtPct}) {
    final n = netRate(whtPct);
    if (n == null) return null;
    return ((1 + n / 100) / (1 + inflationPct / 100) - 1) * 100;
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

  // ── The headline, and the gates around it (0070) ──────────────────────────

  /// The single gate every price-derived widget checks. Exactly [Stock.hasPrice],
  /// for exactly the same reason: no price means no chart, no return, no
  /// comparison against a priced peer, and NOT a plausible-looking zero.
  bool get hasPrice => pricePerUnit != null && pricePerUnit! > 0;

  /// What this fund's tile leads with, carrying its own kind.
  ///
  /// A priced fund is ranked by what its price already DID, never by the price
  /// itself. A NAV of 142.86 beside a NAV of 10.42 says nothing about which fund
  /// did better for anyone, only about how finely each manager chose to slice its
  /// units. The price is context; the return is the claim.
  ///
  /// The two empty states are distinct because they are different facts and they
  /// ask for different things: a fund with a price but no published return is
  /// waiting on a fact sheet, and a fund with neither is waiting on everything.
  Headline get headline {
    if (showsYield) {
      final g = currentRate;
      return g == null ? const NoHeadline('NO RATE') : YieldHeadline(g);
    }
    final r = return1y;
    if (r != null) return ReturnHeadline(r);
    return hasPrice
        ? const NoHeadline('NO RETURN YET')
        : const NoHeadline('NO PRICE YET');
  }

  /// Whether this fund can appear in a ranked list at all. False funds still
  /// appear in the directory, because a real licensed fund is worth knowing about,
  /// but they are not ranked rather than ranked at zero, which would be a claim
  /// nobody can make. Same rule as [Sacco.hasDepositRate].
  bool get isRankable => headline is! NoHeadline;

  // ── Bond-fund helpers (0070) ──────────────────────────────────────────────

  /// Share of the portfolio that is NOT government paper, as a percentage.
  ///
  /// This is the number that explains the extra income, and it is the same number
  /// that explains the risk. Null when the split is unseeded, so the section
  /// hides rather than implying a fund is 100% government paper by omission.
  double? get creditRiskPct {
    final q = creditQuality;
    if (q == null || q.isEmpty) return null;
    final total = q.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return null;
    final gov = q['gov'] ?? 0;
    return (total - gov) / total * 100;
  }

  /// Approximate price move for a 1 percentage-point rise in market rates, as a
  /// NEGATIVE percentage: rates up, bond prices down.
  ///
  /// This is the one thing about a bond fund that a money-market user will get
  /// backwards. There, a rising rate is simply good news. Here it cuts the value
  /// of the bonds the fund already owns, and the holder feels it in the unit price
  /// before ever feeling the higher income.
  ///
  /// Deliberately signed, and deliberately approximate. Modified duration is a
  /// first-order estimate and convexity is ignored, which is fine for a one-point
  /// move and dishonest for a large one, so callers must not scale it past a
  /// point or two.
  double? get priceMovePerPoint {
    final d = durationYears;
    return (d == null || d <= 0) ? null : -d;
  }

  // ── Size (0064) ───────────────────────────────────────────────────────────

  /// Fund size, compact and carrying its OWN currency: "KES 3.8B", "USD 1.2M".
  /// Null when unseeded, so the caller hides the row rather than showing a zero.
  ///
  /// The currency is always printed. A bare "3.8B" next to a bare "1.2M" invites
  /// exactly the comparison that cannot be made.
  String? get aumLabel {
    final v = aumNative;
    if (v == null || v <= 0) return null;
    String n;
    if (v >= 1e9) {
      final b = v / 1e9;
      n = '${b >= 10 ? b.round() : b.toStringAsFixed(1)}B';
    } else if (v >= 1e6) {
      final m = v / 1e6;
      n = '${m >= 10 ? m.round() : m.toStringAsFixed(1)}M';
    } else if (v >= 1e3) {
      n = '${(v / 1e3).round()}K';
    } else {
      n = v.round().toString();
    }
    return '$currency $n';
  }
}

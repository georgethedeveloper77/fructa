import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/categories.dart';
import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/insights/signal_engine.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/agent.dart';
import '../../data/models/fund.dart';
import '../../data/models/fund_composition.dart';
import '../../data/models/holding.dart';
import '../../data/models/remote_config.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/accrual_engine.dart';
import '../../engine/projection_engine.dart';
import '../../engine/tax.dart';
import '../alerts/alerts_page.dart';
import 'widgets/composition_pie.dart';
import 'widgets/fund_credentials.dart';
import 'widgets/fund_performance.dart';
import 'widgets/peer_compare.dart';
import 'widgets/rate_chart.dart';

const _typeNames = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};
String _typeName(Fund f) => _typeNames[f.fundType] ?? categoryLabel(f.category);

// Human labels for the stated-benchmark key (funds.benchmark_key, 0026). Used
// by the benchmark-relative line and the terms card.
const _benchLabels = {
  'tbill_91': '91-day T-bill',
  'tbill_182': '182-day T-bill',
  'tbill_364': '364-day T-bill',
  'cbr': 'Central Bank Rate',
};

String _commas(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String _quarter(String asOf) {
  final d = DateTime.tryParse(asOf);
  if (d == null) return asOf;
  return 'Q${((d.month - 1) ~/ 3) + 1} ${d.year}';
}

/// v6 `.co` — company/fund detail. Carded sections (chart · performance ·
/// manager CIS · credentials · composition · peers · terms) over a brand-tinted
/// ambient glow, matched to the mockup, with the kit-based position/signals/
/// agents/CTAs preserved.
class CompanyPage extends ConsumerWidget {
  const CompanyPage(this.fund, {super.key});
  final Fund fund;

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Holding? _heldIn(List<Holding> holdings) {
    for (final h in holdings) {
      if (h.fundId == fund.id) return h;
    }
    return null;
  }

  /// First reachable agent as a launch URL — WhatsApp when the agent takes it,
  /// otherwise a dialer link. Null when no agent has a usable number, so the
  /// Contact CTA hides rather than dangling. Mirrors the per-agent row logic.
  String? _contactUrl(List<Agent> agents) {
    for (final a in agents) {
      final digits = (a.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (a.whatsapp && digits.isNotEmpty) return 'https://wa.me/$digits';
      if (a.phone != null && a.phone!.isNotEmpty) return 'tel:${a.phone}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final tint =
        ref.watch(brandColorProvider(fund.id)) ?? categoryColor(fund.category);
    final logoUrl = ref.watch(logoUrlProvider(fund.id));
    final peers = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final held = _heldIn(ref.watch(holdingsProvider));
    final following = ref.watch(subscriptionsProvider).contains(fund.id);
    final signals = buildSignals(fund, peers,
        bank: ref.watch(snapshotExtrasProvider).templateBank);
    final agents = ref.watch(agentsForCompanyProvider(fund.companyId));
    final d7 = ref.watch(fundDeltaProvider(fund.id));

    final rate = fund.currentRate;
    final netPct = fund.taxFree ? (rate ?? 0) : Tax.net(rate ?? 0);
    final realPct = fund.realRate(cfg.inflationPct);
    final invest = fund.investUrl ?? fund.siteUrl;

    // Benchmark-relative: gross fund yield vs its stated benchmark (same basis
    // as the fact sheet's fund-vs-T-bill line). Null unless seeded + yielding.
    final Benchmark? bench = (fund.showsYield &&
            rate != null &&
            fund.benchmarkConfigKey != null)
        ? cfg.benchmark(fund.benchmarkConfigKey!)
        : null;

    // Terms card helpers (0026).
    final benchLabel =
        fund.benchmarkKey != null ? _benchLabels[fund.benchmarkKey] : null;
    final hasLiquidity =
        fund.lockInMonths != null || fund.redemptionFee != null;
    String liquidityText() {
      final parts = <String>[];
      final m = fund.lockInMonths;
      final r = fund.redemptionFee;
      if (m != null && m > 0) parts.add('$m-month lock-in');
      if (r != null && r > 0) parts.add('$r% exit fee');
      return parts.isEmpty ? 'No lock-in, no exit fee' : parts.join(' \u00b7 ');
    }

    // Rank among same-type, same-currency retail peers on net yield — the same
    // basis as the peer bars below. Null when it can't be ranked meaningfully.
    int? fundRank;
    var rankTotal = 0;
    if (fund.showsYield && rate != null) {
      final wht = cfg.whtPct;
      double net(Fund p) {
        final r = p.currentRate;
        if (r == null) return double.negativeInfinity;
        return p.taxFree ? r : r * (1 - wht / 100);
      }

      final sameSet = peers
          .where((p) =>
              p.retail &&
              p.fundType == fund.fundType &&
              p.currency == fund.currency &&
              p.showsYield &&
              p.currentRate != null)
          .toList()
        ..sort((a, b) => net(b).compareTo(net(a)));
      final i = sameSet.indexWhere((p) => p.id == fund.id);
      if (i >= 0) {
        fundRank = i + 1;
        rankTotal = sameSet.length;
      }
    }

    // ── CMA CIS quarterly composition. Null (section hidden) until the
    // snapshot carries a breakdown for this fund.
    final fc = ref.watch(compositionProvider(fund.id));

    // Manager market position (CMA Table 1 via companies): share + rank.
    final allCompanies = ref.watch(companiesProvider);
    final manager =
        fund.companyId != null ? allCompanies[fund.companyId] : null;
    final rankedCount =
        allCompanies.values.where((co) => co.marketShare != null).length;
    int? managerRank;
    if (manager?.marketShare != null) {
      final ranked = allCompanies.values
          .where((co) => co.marketShare != null)
          .toList()
        ..sort((a, b) => b.marketShare!.compareTo(a.marketShare!));
      final i = ranked.indexWhere((co) => co.id == manager!.id);
      if (i >= 0) managerRank = i + 1;
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        // Full fund name as the title. FittedBox.scaleDown shrinks a long name
        // to fit the bar instead of clipping or ellipsising it (no-truncation
        // rule); short names stay at full size.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(fund.name,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                  color: c.text, fontSize: 16.5, fontWeight: FontWeight.w700)),
        ),
        actions: [
          IconButton(
            tooltip: t('nav.alerts'),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AlertsPage())),
            icon: Icon(Icons.notifications_none, color: c.muted),
          ),
          IconButton(
            tooltip: following ? t('company.following') : t('company.follow'),
            onPressed: () =>
                ref.read(subscriptionsProvider.notifier).toggle(fund.id),
            icon: Icon(
              following ? Icons.star : Icons.star_border,
              color: following ? c.accent : c.muted,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Ambient brand glow behind the top of the page (.cglow).
          Positioned(
            top: -140,
            left: -80,
            right: -80,
            height: 520,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.2, -0.3),
                    radius: 0.85,
                    colors: [tint.withValues(alpha: 0.20), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              // ── Identity (det-hero) ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    FundLogo(
                        domain: fund.logoDomain,
                        logoUrl: logoUrl,
                        seed: fund.manager,
                        size: 46,
                        brandColor: tint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fund.name,
                              style: TextStyle(
                                  color: c.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              '${fund.manager} \u00b7 ${_typeName(fund)} \u00b7 ${fund.currency}',
                              style: TextStyle(
                                  color: c.muted,
                                  fontFamily: AkibaFonts.mono,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Big rate + % gross + inline 7d delta ───────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          color: c.text,
                          fontFamily: AkibaFonts.mono,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                        children: rate != null
                            ? [
                                TextSpan(
                                    text: rate.toStringAsFixed(2),
                                    style: const TextStyle(
                                        fontSize: 46, letterSpacing: -1.5)),
                                TextSpan(
                                    text: fund.showsYield ? '% gross' : '%',
                                    style: TextStyle(
                                        fontSize: 18, color: c.muted)),
                              ]
                            : [
                                TextSpan(
                                    text: t('common.dash'),
                                    style: const TextStyle(
                                        fontSize: 46, letterSpacing: -1.5)),
                              ],
                      ),
                    ),
                    if (d7 != null && d7 != 0) ...[
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                d7 > 0
                                    ? Icons.arrow_drop_up
                                    : Icons.arrow_drop_down,
                                size: 18,
                                color: c.delta(d7)),
                            Text(
                                '${d7.abs().toStringAsFixed(2)} ${t('company.pts7d')}',
                                style: TextStyle(
                                    color: c.delta(d7),
                                    fontFamily: AkibaFonts.mono,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Triad: net / real / min ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: _Triad(
                  netLabel: fund.taxFree
                      ? 'TAX-FREE'
                      : 'NET (${cfg.whtPct.toStringAsFixed(0)}% WHT)',
                  netValue: rate != null ? '${netPct.toStringAsFixed(2)}%' : '\u2014',
                  real: fund.showsYield ? realPct : null,
                  minValue: fund.minInvest != null
                      ? '${fund.currency} ${_commas(fund.minInvest!)}'
                      : '\u2014',
                ),
              ),

              // ── Rank vs same-type peers (context line) ─────────────────
              if (fundRank case final r? when rankTotal > 1)
                _RankLine(
                  rank: r,
                  total: rankTotal,
                  typeLabel: _typeName(fund).toLowerCase(),
                  currency: fund.currency,
                ),

              // ── Beating / trailing its stated benchmark ────────────────
              if (bench != null && rate != null)
                _BenchmarkLine(
                  fundRate: rate,
                  benchRate: bench.rate,
                  label: _benchLabels[fund.benchmarkKey] ?? 'benchmark',
                ),

              // ── Risk profile — editorial band from fund_type ───────────
              _RiskBand(fund.fundType),

              // ── Rate history (carded) ──────────────────────────────────
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _card(context, child: RateChart(fund.id, color: tint)),
              ),

              // ── Trailing performance vs benchmark (Bucket B) ───────────
              if (fund.hasReturns) FundPerformance(fund, tint: tint),

              // ── Project your returns — reuses ProjectionEngine ─────────
              _ProjectionSection(fund, tint: tint),

              // ── Your position (.pos) — only when held ─────────────────
              if (held != null) ...[
                SectionHeader(title: t('company.yourPosition')),
                _position(context, held, netPct,
                    usdKes: ref.watch(usdKesProvider)),
              ],

              // ── Manager · CMA CIS position ─────────────────────────────
              if (manager?.aumKes != null || manager?.marketShare != null) ...[
                _eyebrow(
                    context,
                    'MANAGER${manager?.aumAsOf != null ? ' \u00b7 CMA CIS ${_quarter(manager!.aumAsOf!)}' : ''}'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _card(context,
                      child: _Stat3(
                        aum: manager?.aumKes,
                        rank: managerRank,
                        rankTotal: rankedCount,
                        share: manager?.marketShare,
                      )),
                ),
              ],

              // ── Credentials — age + independent custody (trust strip) ──
              FundCredentials(fund, manager),

              // ── What the fund holds — donut + legend + provenance ──────
              if (fc != null) CompositionPie(fc),

              // ── Vs category leaders — net-yield bars (carded widget) ───
              PeerCompare(fund, tint: tint),

              // ── Terms ──────────────────────────────────────────────────
              _eyebrow(context, 'TERMS'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _card(context,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _Facts(rows: [
                      if (fund.mgmtFee != null)
                        _Fact('Mgmt fee', '${fund.mgmtFee}% p.a.'),
                      if (fund.expenseRatio != null)
                        _Fact('Expense ratio', '${fund.expenseRatio}% p.a.'),
                      _Fact(
                          'Tax',
                          fund.taxFree
                              ? 'Tax-free'
                              : '${cfg.whtPct.toStringAsFixed(0)}% WHT'),
                      if (benchLabel != null) _Fact('Benchmark', benchLabel),
                      if (fund.topUpMin != null)
                        _Fact('Top-up min',
                            '${fund.currency} ${_commas(fund.topUpMin!)}'),
                      if (hasLiquidity) _Fact('Liquidity', liquidityText()),
                    ])),
              ),

              // ── Signals ────────────────────────────────────────────────
              if (signals.isNotEmpty) ...[
                SectionHeader(title: t('company.signals')),
                for (var i = 0; i < signals.length; i++)
                  SignalRow(
                    tag: _tagLabel(signals[i].tag),
                    text: signals[i].text,
                    tone: _tone(signals[i].tag),
                    showDivider: i < signals.length - 1,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(t('company.signalsFoot'),
                      style: TextStyle(color: c.faint, fontSize: 9.5)),
                ),
              ],

              // ── Talk to an agent ───────────────────────────────────────
              if (agents.isNotEmpty) ...[
                SectionHeader(title: t('company.talkToAgent')),
                for (var i = 0; i < agents.length; i++)
                  _agentRow(agents[i], tint, i < agents.length - 1),
              ],

              // ── CTAs ───────────────────────────────────────────────────
              if (invest != null)
                CtaFull(
                    icon: Icons.add,
                    label: t('company.fundTopUp'),
                    onTap: () => _open(invest)),
              if (_contactUrl(agents) case final contact?)
                CtaGhost(
                    icon: Icons.chat_bubble_outline,
                    label: t('company.contact'),
                    onTap: () => _open(contact)),
              if (fund.siteUrl != null)
                CtaGhost(
                    icon: Icons.north_east,
                    label: t('company.officialSite'),
                    onTap: () => _open(fund.siteUrl)),

              Disclaimer(t('company.moneyNote'), center: true),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  // ── Position → kit PositionBlock ──────────────────────────────────────
  Widget _position(BuildContext context, Holding held, double netPct,
      {double? usdKes}) {
    final c = context.c;
    final rate = fund.currentRate ?? 0;
    final daily = fund.taxFree
        ? AccrualEngine.dailyInterest(held.balance, rate)
        : AccrualEngine.dailyInterestNet(held.balance, rate);
    final netLbl = fund.taxFree
        ? t('company.atTaxFree', {'net': netPct.toStringAsFixed(2)})
        : t('company.atNet', {'net': netPct.toStringAsFixed(2)});

    if (held.currency == 'USD') {
      final kesNote = usdKes != null
          ? '\u2248 ${money('KES', (daily * usdKes).round())} \u00b7 $netLbl'
          : netLbl;
      return PositionBlock(
        value: '\$${withCommas(held.balance)}',
        delta: '+\$${daily.toStringAsFixed(2)}/day',
        deltaColor: c.up,
        sub: kesNote,
      );
    }
    return PositionBlock(
      value: money('KES', held.balance),
      delta: '+${money('KES', daily.round())}/day',
      deltaColor: c.up,
      sub: netLbl,
    );
  }

  // ── Agent → kit AgentRow ──────────────────────────────────────────────
  Widget _agentRow(Agent a, Color tint, bool divider) {
    final digits = (a.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final sub = [
      if (a.role != null && a.role!.isNotEmpty) a.role!,
      if (a.phone != null && a.phone!.isNotEmpty) a.phone!,
    ].join(' \u00b7 ');
    return AgentRow(
      name: a.name,
      phone: sub,
      avatarColor: tint,
      onCall: a.phone != null ? () => _open('tel:${a.phone}') : null,
      onWhatsApp: (a.whatsapp && digits.isNotEmpty)
          ? () => _open('https://wa.me/$digits')
          : null,
      showDivider: divider,
    );
  }

  SignalTone _tone(SignalTag tag) => switch (tag) {
        SignalTag.strength => SignalTone.positive,
        SignalTag.watch => SignalTone.negative,
        SignalTag.note => SignalTone.neutral,
      };

  String _tagLabel(SignalTag tag) => switch (tag) {
        SignalTag.strength => t('company.tag.strength'),
        SignalTag.watch => t('company.tag.watch'),
        SignalTag.note => t('company.tag.note'),
      };
}

// ── local building blocks (mockup cards) ─────────────────────────────────

Widget _card(BuildContext context, {required Widget child, EdgeInsets? padding}) {
  final c = context.c;
  return Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: c.s1,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.line),
    ),
    child: child,
  );
}

Widget _eyebrow(BuildContext context, String text) {
  final c = context.c;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
    child: Text(text,
        style: TextStyle(
            color: c.faint,
            fontFamily: AkibaFonts.mono,
            fontSize: 10.5,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w600)),
  );
}

class _RankLine extends StatelessWidget {
  const _RankLine({
    required this.rank,
    required this.total,
    required this.typeLabel,
    required this.currency,
  });
  final int rank;
  final int total;
  final String typeLabel;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(Icons.trending_up, size: 15, color: c.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                      color: c.muted,
                      fontFamily: AkibaFonts.mono,
                      fontSize: 11,
                      height: 1.3),
                  children: [
                    TextSpan(
                        text: '#$rank of $total',
                        style: TextStyle(
                            color: c.accent, fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: ' $currency $typeLabel funds by net yield'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under-triad line: this fund's gross yield vs its stated benchmark, on the
/// same basis the fact sheet uses (fund vs T-bill). Only rendered when a
/// benchmark is seeded and the fund yields (see the call-site guard).
class _BenchmarkLine extends StatelessWidget {
  const _BenchmarkLine({
    required this.fundRate,
    required this.benchRate,
    required this.label,
  });
  final double fundRate;
  final double benchRate;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final delta = fundRate - benchRate;
    final beating = delta >= 0;
    final col = c.delta(delta);
    final mag =
        beating ? '+${delta.toStringAsFixed(2)}' : delta.abs().toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(beating ? Icons.trending_up : Icons.trending_down,
                size: 15, color: col),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                      color: c.muted,
                      fontFamily: AkibaFonts.mono,
                      fontSize: 11,
                      height: 1.3),
                  children: [
                    TextSpan(text: beating ? 'Beating the ' : 'Trailing the '),
                    TextSpan(
                        text: label,
                        style: TextStyle(
                            color: c.text, fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' by '),
                    TextSpan(
                        text: '$mag pts',
                        style:
                            TextStyle(color: col, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editorial risk band derived purely from `fund_type` — no stored data. A
/// four-step gauge (lower → higher) filled up to the fund's level on a
/// green→gold→red ramp, plus a plain one-line characterisation. The ramp is
/// lerped from the theme's own semantic tokens (`up` → `accent` → `down`), so
/// it's theme-aware and reads clearly on both surfaces without introducing raw
/// hex. Renders nothing for a type we haven't placed on the scale (e.g.
/// `special` or a null legacy type), so it never guesses a level.
class _RiskBand extends StatelessWidget {
  const _RiskBand(this.fundType);
  final String? fundType;

  static const _steps = 4;

  /// Risk ramp at fraction [t] (0 = lowest, 1 = highest): green → gold → red,
  /// all from live theme tokens. Gold midpoint keeps a brand note between the
  /// two clear endpoints.
  static Color hueAt(AkibaColors c, double t) => t <= 0.5
      ? Color.lerp(c.up, c.accent, t / 0.5)!
      : Color.lerp(c.accent, c.down, (t - 0.5) / 0.5)!;

  // fund_type → (level 1..4, label, one-line note). Omitted types → no band.
  static ({int level, String label, String note})? _spec(String? t) =>
      switch (t) {
        'mmf' => (
            level: 1,
            label: 'Low',
            note: 'Capital-stable and highly liquid. Returns track '
                'short-term interest rates.',
          ),
        'fixed_income' => (
            level: 2,
            label: 'Low to medium',
            note: 'Mostly bonds and fixed deposits. Priced day to day but '
                'capital-oriented.',
          ),
        'balanced' => (
            level: 3,
            label: 'Medium',
            note: 'Blends equities and fixed income, so the value can rise '
                'and fall.',
          ),
        'equity' => (
            level: 4,
            label: 'High',
            note: 'Mostly listed shares. Higher long-run potential with '
                'larger swings.',
          ),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _spec(fundType);
    if (s == null) return const SizedBox.shrink();
    // fraction for a 1-based level on a 4-step scale (0, .33, .67, 1).
    double frac(int level) => (level - 1) / (_steps - 1);
    final labelHue = hueAt(c, frac(s.level));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('RISK PROFILE',
                    style: TextStyle(
                        color: c.faint,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 10.5,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(s.label.toUpperCase(),
                    style: TextStyle(
                        color: labelHue,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 1; i <= _steps; i++) ...[
                  if (i > 1) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= s.level ? hueAt(c, frac(i)) : c.s3,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Text('Lower risk',
                    style: TextStyle(
                        color: c.faint,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 8.5,
                        letterSpacing: 0.4)),
                const Spacer(),
                Text('Higher risk',
                    style: TextStyle(
                        color: c.faint,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 8.5,
                        letterSpacing: 0.4)),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.note,
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.45)),
          ],
        ),
      ),
    );
  }
}

/// "Project your returns" — a fund-specific forward projection reusing
/// [ProjectionEngine]. Initial prefills from `fund.minInvest`; the top-up and
/// horizon sliders drive a live monthly-compounded value, growth line, and an
/// honest ledger. The management fee is shown as informational (it's already
/// inside the published yield), never a deduction; only WHT is subtracted —
/// and for tax-free funds even that row becomes a "Tax-free" note. Rendered
/// only for funds that quote a yield and have a rate.
class _ProjectionSection extends StatefulWidget {
  const _ProjectionSection(this.fund, {this.tint});
  final Fund fund;
  final Color? tint;

  @override
  State<_ProjectionSection> createState() => _ProjectionSectionState();
}

class _ProjectionSectionState extends State<_ProjectionSection> {
  late final TextEditingController _initial;
  double _topUp = 10000;
  int _months = 24;

  @override
  void initState() {
    super.initState();
    final seed = widget.fund.minInvest;
    _initial =
        TextEditingController(text: seed != null ? _commas(seed) : '');
  }

  @override
  void dispose() {
    _initial.dispose();
    super.dispose();
  }

  double get _initialAmt =>
      double.tryParse(_initial.text.replaceAll(',', '').trim()) ?? 0;

  static String _horizonLabel(int m) {
    final y = m ~/ 12;
    final mm = m % 12;
    if (y == 0) return '$mm ${mm == 1 ? 'month' : 'months'}';
    if (mm == 0) return '$y ${y == 1 ? 'year' : 'years'}';
    return '${y}y ${mm}m';
  }

  @override
  Widget build(BuildContext context) {
    final fund = widget.fund;
    final rate = fund.currentRate;
    if (!fund.showsYield || rate == null) return const SizedBox.shrink();

    final c = context.c;
    final tint = widget.tint ?? c.accent;
    final cur = fund.currency;
    final taxFree = fund.taxFree;

    final initial = _initialAmt;
    final contributed = initial + _topUp * _months;

    final projNet = ProjectionEngine.project(initial, rate, _months,
        monthlyTopUp: _topUp, net: !taxFree);
    final projGross = ProjectionEngine.project(initial, rate, _months,
        monthlyTopUp: _topUp, net: false);
    final grossInterest = projGross - contributed;
    final netInterest = projNet - contributed;
    final whtPaid = (grossInterest - netInterest).clamp(0, double.infinity);

    final series = ProjectionEngine.series(initial, rate, _months,
        monthlyTopUp: _topUp, net: !taxFree);

    String kes(num v) => money(cur, v.round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(context, 'PROJECT YOUR RETURNS'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _card(
            context,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // headline projected value
                Text(kes(projNet),
                    style: TextStyle(
                        color: c.text,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.1)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.arrow_drop_up, size: 18, color: c.up),
                    Flexible(
                      child: Text(
                        '${kes(netInterest < 0 ? 0 : netInterest)} net growth \u00b7 over ${_horizonLabel(_months)}',
                        style: TextStyle(
                            color: c.up,
                            fontFamily: AkibaFonts.mono,
                            fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                // growth curve
                if (series.length >= 2) ...[
                  const SizedBox(height: 14),
                  SizedBox(height: 96, child: _ProjChart(series, tint)),
                ],
                // inputs
                const SizedBox(height: 12),
                _amountField(c, cur, rate),
                const SizedBox(height: 14),
                _sliderRow(
                  c,
                  label: 'Monthly top-up',
                  valueText: kes(_topUp),
                  slider: Slider(
                    value: _topUp,
                    min: 0,
                    max: 100000,
                    divisions: 20,
                    onChanged: (v) => setState(() => _topUp = v),
                  ),
                ),
                _sliderRow(
                  c,
                  label: 'Horizon',
                  valueText: _horizonLabel(_months),
                  slider: Slider(
                    value: _months.toDouble(),
                    min: 6,
                    max: 120,
                    divisions: 19,
                    onChanged: (v) => setState(() => _months = v.round()),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Breakdown ledger (WHT-only; fee is informational) ──────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Container(
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _LedgerRow(
                  k: 'You contribute',
                  sub:
                      '${kes(initial)} + ${kes(_topUp)} \u00d7 $_months',
                  v: kes(contributed),
                ),
                _LedgerRow(
                  k: 'Gross interest',
                  v: '+${kes(grossInterest)}',
                  vColor: c.up,
                ),
                if (taxFree)
                  _LedgerRow(
                    k: 'Tax',
                    v: 'Tax-free',
                    vColor: c.muted,
                  )
                else
                  _LedgerRow(
                    k: 'Less ${(Tax.wht * 100).toStringAsFixed(0)}% withholding tax',
                    v: '\u2212${kes(whtPaid)}',
                    vColor: c.muted,
                  ),
                _LedgerRow(
                  k: 'Net interest earned',
                  v: '+${kes(netInterest < 0 ? 0 : netInterest)}',
                  vColor: c.up,
                ),
                _LedgerRow(
                  k: 'Projected value',
                  v: kes(projNet),
                  total: true,
                  accent: tint,
                  last: true,
                ),
              ],
            ),
          ),
        ),

        // ── Fee: shown, not deducted ───────────────────────────────────
        if (fund.mgmtFee != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: c.faint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Manager fee ${fund.mgmtFee}% p.a. is already reflected in the ${rate.toStringAsFixed(2)}% yield \u2014 it isn\u2019t charged on top.',
                    style: TextStyle(
                        color: c.faint, fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'Illustration only, at today\u2019s rate held flat. Rates move, so returns aren\u2019t guaranteed. Compounded monthly, net of tax.',
            style: TextStyle(color: c.faint, fontSize: 10, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _amountField(AkibaColors c, String cur, double rate) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Initial amount',
                  style: TextStyle(color: c.muted, fontSize: 11.5)),
              if (widget.fund.minInvest != null)
                Text('min ${money(cur, widget.fund.minInvest!)}',
                    style: TextStyle(
                        color: c.faint,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(cur,
                    style: TextStyle(
                        color: c.muted,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _initial,
                    keyboardType: const TextInputType.numberWithOptions(),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                        color: c.text,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      hintText: '0',
                      hintStyle: TextStyle(
                          color: c.faint, fontFamily: AkibaFonts.mono),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('earning ${rate.toStringAsFixed(2)}%',
                    style: TextStyle(
                        color: c.faint,
                        fontFamily: AkibaFonts.mono,
                        fontSize: 10.5)),
              ],
            ),
          ),
        ],
      );

  Widget _sliderRow(AkibaColors c,
          {required String label,
          required String valueText,
          required Widget slider}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
              Text(valueText,
                  style: TextStyle(
                      color: c.text,
                      fontFamily: AkibaFonts.mono,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: 34, child: slider),
        ],
      );
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.k,
    required this.v,
    this.sub,
    this.vColor,
    this.total = false,
    this.accent,
    this.last = false,
  });
  final String k;
  final String v;
  final String? sub;
  final Color? vColor;
  final bool total;
  final Color? accent;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final acc = accent ?? c.accent;
    return Container(
      decoration: BoxDecoration(
        color: total ? acc.withValues(alpha: 0.12) : null,
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k,
                    style: TextStyle(
                        color: total ? c.text : c.muted,
                        fontSize: total ? 13 : 12.5,
                        fontWeight:
                            total ? FontWeight.w600 : FontWeight.w400)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!,
                      style: TextStyle(
                          color: c.faint,
                          fontFamily: AkibaFonts.mono,
                          fontSize: 10)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(v,
              style: TextStyle(
                  color: total ? acc : (vColor ?? c.text),
                  fontFamily: AkibaFonts.mono,
                  fontSize: total ? 16 : 13.5,
                  fontWeight: total ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProjChart extends StatelessWidget {
  const _ProjChart(this.series, this.color);
  final List<double> series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) return const SizedBox.shrink();
    final lo = series.reduce((a, b) => a < b ? a : b);
    final hi = series.reduce((a, b) => a > b ? a : b);
    if (hi <= lo) return const SizedBox.shrink();
    return LineChart(LineChartData(
      minX: 0,
      maxX: (series.length - 1).toDouble(),
      minY: lo,
      maxY: hi + (hi - lo) * 0.05,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < series.length; i++)
              FlSpot(i.toDouble(), series[i]),
          ],
          isCurved: true,
          curveSmoothness: 0.28,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    ));
  }
}

class _Triad extends StatelessWidget {
  const _Triad({
    required this.netLabel,
    required this.netValue,
    required this.real,
    required this.minValue,
  });
  final String netLabel;
  final String netValue;
  final double? real;
  final String minValue;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget divider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: c.line);
    return Row(
      children: [
        _TriadCell(k: netLabel, v: netValue),
        divider(),
        _TriadCell(
          k: 'REAL VS INFL.',
          v: real != null
              ? '${real! >= 0 ? '+' : ''}${real!.toStringAsFixed(2)}%'
              : '\u2014',
          color: real != null ? c.delta(real!) : null,
        ),
        divider(),
        _TriadCell(k: 'MIN INVEST', v: minValue),
      ],
    );
  }
}

class _TriadCell extends StatelessWidget {
  const _TriadCell({required this.k, required this.v, this.color});
  final String k;
  final String v;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  color: c.faint,
                  fontFamily: AkibaFonts.mono,
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(v,
              style: TextStyle(
                  color: color ?? c.text,
                  fontFamily: AkibaFonts.mono,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Stat3 extends StatelessWidget {
  const _Stat3({
    required this.aum,
    required this.rank,
    required this.rankTotal,
    required this.share,
  });
  final double? aum;
  final int? rank;
  final int rankTotal;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: c.line);
    return Row(
      children: [
        _StatCell(
            k: 'MANAGER AUM',
            v: aum != null ? FundComposition.kesShort(aum!) : '\u2014'),
        divider(),
        _StatCell(
            k: 'RANK',
            v: rank != null ? '#$rank / $rankTotal' : '\u2014'),
        divider(),
        _StatCell(
            k: 'MARKET SHARE',
            v: share != null ? '${share!.toStringAsFixed(1)}%' : '\u2014'),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.k, required this.v});
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  color: c.faint,
                  fontFamily: AkibaFonts.mono,
                  fontSize: 9.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(v,
              style: TextStyle(
                  color: c.text,
                  fontFamily: AkibaFonts.mono,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Fact {
  const _Fact(this.k, this.v);
  final String k;
  final String v;
}

class _Facts extends StatelessWidget {
  const _Facts({required this.rows});
  final List<_Fact> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pairs = <List<_Fact>>[];
    for (var i = 0; i < rows.length; i += 2) {
      pairs.add(rows.sublist(i, (i + 2) > rows.length ? rows.length : i + 2));
    }
    Widget cell(_Fact f, {required bool left}) => Padding(
          padding: EdgeInsets.only(
              top: 12, bottom: 12, left: left ? 14 : 0, right: left ? 0 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.k,
                  style: TextStyle(
                      color: c.faint,
                      fontFamily: AkibaFonts.mono,
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(f.v,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        );
    return Column(
      children: [
        for (var p = 0; p < pairs.length; p++)
          Container(
            decoration: p < pairs.length - 1
                ? BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)))
                : null,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: cell(pairs[p][0], left: false)),
                  Container(width: 1, color: c.line),
                  Expanded(
                    child: pairs[p].length > 1
                        ? cell(pairs[p][1], left: true)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

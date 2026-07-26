import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/follow_star.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/stock.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../alerts/alerts_page.dart';
import 'brokers_page.dart';
import 'widgets/broker_row.dart';
import 'widgets/stock_chart.dart';

/// Stock detail. Mirrors the fund detail shape (identity, hero figure, stat
/// triad, context lines, risk band, chart) so a stock reads as the same kind of
/// object as a fund, then adds the two things a stock needs and a fund does
/// not: a dividend record and a route to a broker.
///
/// EVERY price-derived surface below is gated on [Stock.hasPrice]:
///   hero figure, day change, market cap, dividend yield, price chart.
///
/// That gate is NOT about a licence, whatever the old comment here said. Fructa
/// publishes end-of-day closes, which are facts of public record printed in the
/// Kenyan press daily. The gate is about honesty: roughly ten of the sixty four
/// counters do not trade on a given day, so they have no price, and the page
/// falls back to the declared dividend rather than inventing a number. Do not
/// remove these guards to "fill the layout": a share that did not trade did not
/// trade at zero.
class StockPage extends ConsumerWidget {
  const StockPage(this.stock, {super.key});
  final Stock stock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    // Re-read from the snapshot so a refresh while the page is open updates it.
    final s = ref.watch(stockByIdProvider(stock.id)) ?? stock;
    final brokers = ref.watch(brokersProvider);
    final tint = s.brandColor ?? c.accent;
    final following = ref.watch(stockSubscriptionsProvider).contains(s.id);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text(
          s.name,
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: t('nav.alerts'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AlertsPage()),
            ),
            icon: Icon(Icons.notifications_none, color: c.muted),
          ),
          // Following a stock buys exactly one thing: the book-closure alert.
          // Not a price ping. See StockSubscriptionsNotifier.
          FollowStar(
            following: following,
            tint: tint,
            onToggle: () =>
                ref.read(stockSubscriptionsProvider.notifier).toggle(s.id),
          ),
        ],
      ),
      body: Stack(
        children: [
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
                    colors: [
                      tint.withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _identity(context, s, tint),
              _hero(context, s),
              if (s.about != null) _about(context, s),
              if (!s.hasPrice) _noPriceNote(context),
              if (s.hasPrice) _statTriad(context, s),
              if (s.hasPrice) _rank(context, s, ref),
              if (s.hasPrice) _vsTbill(context, s, ref),
              _riskBand(context),
              if (s.hasPrice) _chart(context, s, tint),
              _deadline(context, s, tint, following, ref),
              if (s.hasDividend) _dividends(context, s),
              _howToBuy(context),
              if (brokers.isNotEmpty) _whereToBuy(context, brokers, tint),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, Stock s, Color tint) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          FundLogo(
            domain: null,
            logoUrl: s.logoUrl,
            seed: s.name,
            size: 52,
            brandColor: tint,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    'NSE',
                    if (s.sector != null) s.sector!,
                    s.ticker,
                  ].join(' \u00B7 '),
                  style: TextStyle(color: c.muted, fontSize: 13.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The hero figure. Price when licensed, declared dividend when not.
  Widget _hero(BuildContext context, Stock s) {
    final c = context.c;

    if (s.hasPrice) {
      final up = s.isUp ?? true;
      final chKes = s.changeKes;
      final chPct = s.changePct;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'KES ',
              style: TextStyle(
                color: c.muted,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              s.closeKes!.toStringAsFixed(2),
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            if (chPct != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${up ? '+' : ''}${chKes != null ? chKes.toStringAsFixed(2) : ''} \u00B7 ${chPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: c.delta(chPct),
                    fontFamily: fructaFonts.mono,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (s.hasDividend) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.dpsLatest!.toStringAsFixed(2),
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    t('stocks.perShare'),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t('stocks.declaredFy', {'y': '${s.dpsYear}'}),
              style: TextStyle(color: c.faint, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return const SizedBox(height: 8);
  }

  Widget _about(BuildContext context, Stock s) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Text(
        s.about!,
        style: TextStyle(color: c.text, fontSize: 14.5, height: 1.55),
      ),
    );
  }

  /// Stated plainly rather than left as a mysterious gap. This is the honest
  /// answer to "why is there no price here".
  Widget _noPriceNote(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.s2,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 17, color: c.faint),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                t('stocks.noPriceDetail'),
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Market cap and dividend yield BOTH need a price, so this whole triad is
  /// inside the licence gate. A yield computed without a price would be a
  /// fabricated number.
  Widget _statTriad(BuildContext context, Stock s) {
    final c = context.c;
    // Div yield, market cap, then P/E, which is what the mockup drew.
    //
    // The third cell falls back to the declared dividend when there is no P/E,
    // which is the normal state until an admin has typed the EPS off the
    // company's results. An empty "P / E  --" cell would be worse than a real
    // number in its place. The mockup's 12.4 was invented; this one is
    // price / earnings, and it is simply absent until both halves exist.
    final cells = <(String, String)>[
      if (s.divYield != null)
        (t('stocks.stat.divYield'), '${s.divYield!.toStringAsFixed(1)}%'),
      if (s.marketCap != null)
        (t('stocks.stat.marketCap'), _cap(s.marketCap!)),
      if (s.pe != null)
        (t('stocks.stat.pe'), s.pe!.toStringAsFixed(1))
      else if (s.dpsLatest != null)
        (t('stocks.stat.dividend'), s.dpsLatest!.toStringAsFixed(2)),
    ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                Container(width: 1, color: c.line),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 16, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cells[i].$1,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cells[i].$2,
                        style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _cap(double v) {
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(1)}T';
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(0)}B';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(0)}M';
    return v.toStringAsFixed(0);
  }

  /// Shares are higher risk than an MMF or a T-bill, and the app says so
  /// plainly. This is not a disclaimer bolted on, it is the honest framing that
  /// the rest of the product's rate-first thesis implies.
  Widget _riskBand(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.s1,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t('stocks.risk.label'),
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  t('stocks.risk.high'),
                  style: TextStyle(
                    color: c.down,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.down,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t('stocks.risk.lower'),
                  style: TextStyle(color: c.faint, fontSize: 12.5),
                ),
                Text(
                  t('stocks.risk.higher'),
                  style: TextStyle(color: c.faint, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              t('stocks.risk.body'),
              style: TextStyle(color: c.text, fontSize: 14.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  /// The mockup's `.ctx` card: a panel with a leading icon and a line of text.
  /// One helper, so the rank line and the T-bill line cannot drift apart.
  Widget _ctxCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// "#3 of 64 NSE companies by market cap."
  ///
  /// Computed live from the snapshot, not stored: market cap is close x shares
  /// outstanding, and both move. Only counters that HAVE a market cap are
  /// ranked, and the denominator says so, because ranking a company against
  /// sixty four when only forty have a price would put it higher than it is.
  ///
  /// Size is not quality. This line tells a user how big a company is, which is
  /// a fact, and pointedly does not tell them it is therefore a good buy.
  Widget _rank(BuildContext context, Stock s, WidgetRef ref) {
    final mine = s.marketCap;
    if (mine == null || mine <= 0) return const SizedBox.shrink();

    final ranked =
        ref
            .watch(stocksProvider)
            .where((x) => x.marketCap != null && x.marketCap! > 0)
            .toList()
          ..sort((a, b) => b.marketCap!.compareTo(a.marketCap!));
    if (ranked.length < 2) return const SizedBox.shrink();

    final pos = ranked.indexWhere((x) => x.id == s.id) + 1;
    if (pos < 1) return const SizedBox.shrink();

    final c = context.c;
    return _ctxCard(
      context,
      icon: Icons.trending_up,
      iconColor: c.accent,
      child: Text.rich(
        TextSpan(
          style: TextStyle(color: c.text, fontSize: 13.5, height: 1.45),
          children: [
            TextSpan(
              text: t('stocks.rank.pos', {
                'n': '$pos',
                'total': '${ranked.length}',
              }),
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: ' ${t('stocks.rank.sub')}',
              style: TextStyle(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Dividend yield against the 91-day T-bill. The whole thesis of the app, in
  /// one line: is this dividend actually beating the risk-free rate?
  ///
  /// ── TWO THINGS THE MOCKUP GOT WRONG, AND WHY THEY MATTER ──────────────────
  ///
  /// 1. IT COMPARED GROSS TO GROSS. A resident pays 5% withholding on a
  ///    dividend and 15% on T-bill interest, and both are final taxes. So the
  ///    honest comparison is net of each one's OWN tax, not a raw subtraction
  ///    of one headline number from another. At an 8.71% bill and a 5.71%
  ///    dividend yield, gross says the stock trails by 3.0 points; net says it
  ///    trails by 1.99. Same facts, and the gross version overstates the gap by
  ///    half again. Getting this backwards is precisely the error the Learn
  ///    course devotes a lesson to.
  ///
  /// 2. A DIVIDEND YIELD AND A BILL YIELD ARE NOT THE SAME KIND OF NUMBER. The
  ///    bill's return is contractual: the government tells you the number up
  ///    front and pays it. A dividend is discretionary, the board can cut it to
  ///    nothing, and the share price can fall further than the dividend ever
  ///    pays you. Standard Chartered cut its dividend 31% for FY2025. Britam
  ///    has paid none since 2019. Printing "trails by 2 points" and stopping
  ///    invites a reader to treat those as interchangeable, which is the single
  ///    most expensive mistake a first-time investor can make here. So the line
  ///    always carries the caveat. It is not a disclaimer bolted on; it is the
  ///    other half of the fact.
  Widget _vsTbill(BuildContext context, Stock s, WidgetRef ref) {
    final gross = s.divYield;
    if (gross == null || gross <= 0) return const SizedBox.shrink();

    final cfg = ref.watch(remoteConfigProvider);
    final bill = cfg.tbill91Pct;
    if (bill <= 0) return const SizedBox.shrink();

    // Each net of its OWN withholding. Both are final taxes for a resident.
    final netDiv = gross * (1 - cfg.dividendWhtPct / 100);
    final netBill = bill * (1 - cfg.whtPct / 100);
    final gap = netDiv - netBill;
    final beats = gap >= 0;

    final c = context.c;
    final tone = beats ? c.up : c.down;

    return _ctxCard(
      context,
      icon: beats ? Icons.trending_up : Icons.trending_down,
      iconColor: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: TextStyle(color: c.text, fontSize: 13.5, height: 1.45),
              children: [
                TextSpan(
                  text: beats
                      ? t('stocks.vsBill.beats')
                      : t('stocks.vsBill.trails'),
                  style: TextStyle(color: c.muted),
                ),
                TextSpan(
                  text: t('stocks.vsBill.gap', {
                    'pts': gap.abs().toStringAsFixed(2),
                  }),
                  style: TextStyle(color: tone, fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: t('stocks.vsBill.net', {
                    'div': netDiv.toStringAsFixed(2),
                    'bill': netBill.toStringAsFixed(2),
                  }),
                  style: TextStyle(color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('stocks.vsBill.caveat'),
            style: TextStyle(color: c.faint, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// The price line. Says "average price" and not "close", because the NSE's
  /// daily list has no closing-price column: it prints HIGH, LOW, VWAP,
  /// PREVIOUS PRICE and VOLUME, and what we store is the VWAP. It is also
  /// end-of-day, not delayed intraday, and the header says that too.
  Widget _chart(BuildContext context, Stock s, Color tint) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        decoration: BoxDecoration(
          color: c.s1,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The mockup's header reads "PRICE . NSE DELAYED". Both halves are
            // wrong and I am not shipping them.
            //
            // "Delayed" describes an intraday feed running behind real time.
            // Fructa has no such feed and makes no such claim: this is the
            // end-of-day board, read after the 15:00 close.
            //
            // "Price" is the bigger one. The NSE daily list has NO closing
            // price column. It prints 52WK HIGH, 52WK LOW, HIGH, LOW, VWAP,
            // PREVIOUS PRICE, VOLUME. What every source quotes, including the
            // one we scrape, is the VWAP: the volume-weighted average of the
            // day's trades. Calling that "the price" implies a last trade at
            // that number, which may never have happened.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                t('stocks.chart.head'),
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            StockChart(s.id, color: tint),
          ],
        ),
      ),
    );
  }

  /// The one number on this page a user can still act on.
  ///
  /// To receive a dividend you must be on the register when the books close.
  /// Miss the date by a single day and you get nothing, however long you then
  /// hold the share. That date is published in an image-only PDF on the
  /// exchange's website and effectively nowhere a retail investor would look,
  /// which is exactly the asymmetry this app exists to close.
  ///
  /// Renders nothing when no dividend is pending, which is the normal state for
  /// most of the year. An empty card saying "no upcoming dividend" would be
  /// noise; absence is the message.
  Widget _deadline(
    BuildContext context,
    Stock s,
    Color tint,
    bool following,
    WidgetRef ref,
  ) {
    final d = s.upcomingDividend;
    if (d == null) return const SizedBox.shrink();

    final c = context.c;
    final days = d.daysToBookClosure!;
    final urgent = days <= 3;
    final accent = urgent ? c.accent : tint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available_outlined, size: 17, color: accent),
                const SizedBox(width: 9),
                Text(
                  t('stocks.deadline.title'),
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Text(
                  days == 0
                      ? t('stocks.deadline.today')
                      : days == 1
                      ? t('stocks.deadline.tomorrow')
                      : t('stocks.deadline.days', {'n': '$days'}),
                  style: TextStyle(
                    color: accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              t('stocks.deadline.body', {
                'ticker': s.ticker,
                'date': _shortDate(d.bookClosure!),
                'dps': d.dpsKes.toStringAsFixed(2),
              }),
              style: TextStyle(color: c.text, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 6),
            Text(
              t('stocks.deadline.note'),
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
            ),
            if (!following) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () =>
                    ref.read(stockSubscriptionsProvider.notifier).toggle(s.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border_rounded, size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      t('stocks.deadline.remind'),
                      style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "4 Aug". Parsed, not string-sliced: a malformed date returns the raw value
  /// rather than a confidently wrong one.
  static String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]}';
  }

  /// The mockup's `.divline`: "1.20 KES / share . FY2025 . paid twice a year".
  ///
  /// "Paid twice a year" is DERIVED, by counting the distinct kinds recorded for
  /// the year, not asserted. A company with an interim and a final pays twice; a
  /// company with a single first-and-final pays once. Getting this from the data
  /// rather than a hardcoded string is what stops the app telling a Kakuzi
  /// holder to expect a second cheque that is never coming.
  ///
  /// It is silent when we hold only one kind and cannot tell whether that is
  /// the whole year or half of it. Saying nothing beats guessing the cadence.
  Widget _divSummary(BuildContext context, Stock s) {
    final c = context.c;
    final rows = s.latestYearDividends;
    if (rows.isEmpty || s.dpsLatest == null) return const SizedBox.shrink();

    final kinds = rows.map((d) => d.kind).toSet();
    final cadence = kinds.length >= 2
        ? t('stocks.div.twice')
        : (kinds.contains('final') && kinds.length == 1
              ? t('stocks.div.once')
              : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.payments_outlined, size: 18, color: c.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                  children: [
                    TextSpan(
                      text: t('stocks.div.perShare', {
                        'dps': s.dpsLatest!.toStringAsFixed(2),
                      }),
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: ' \u00b7 FY${s.dpsYear}'),
                    if (cadence != null) TextSpan(text: ' \u00b7 $cadence'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dividends(BuildContext context, Stock s) {
    final c = context.c;
    final rows = s.latestYearDividends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _divSummary(context, s),
        const SizedBox(height: 8),
        SectionHeader(title: t('stocks.dividends')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.s1,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == rows.length - 1
                              ? Colors.transparent
                              : c.line,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _kindLabel(rows[i].kind),
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                rows[i].paymentDate != null
                                    ? t('stocks.dividend.paid', {
                                        'd': '${rows[i].paymentDate}',
                                      })
                                    : t('stocks.dividend.fy', {
                                        'y': '${rows[i].financialYear}',
                                      }),
                                style: TextStyle(color: c.faint, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${rows[i].dpsKes.toStringAsFixed(2)} KES',
                          style: TextStyle(
                            color: c.text,
                            fontFamily: fructaFonts.mono,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'interim':
        return t('stocks.dividend.interim');
      case 'special':
        return t('stocks.dividend.special');
      default:
        return t('stocks.dividend.final');
    }
  }

  Widget _howToBuy(BuildContext context) {
    final c = context.c;
    final steps = <(String, String)>[
      (t('stocks.step.cds.title'), t('stocks.step.cds.body')),
      (t('stocks.step.broker.title'), t('stocks.step.broker.body')),
      (t('stocks.step.fund.title'), t('stocks.step.fund.body')),
      (t('stocks.step.order.title'), t('stocks.step.order.body')),
      (t('stocks.step.settle.title'), t('stocks.step.settle.body')),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SectionHeader(title: t('stocks.howToBuy')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.s3,
                          border: Border.all(color: c.line2),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].$1,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              steps[i].$2,
                              style: TextStyle(
                                color: c.faint,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Routes out to a licensed broker. Fructa never takes the order itself, so
  /// there is no Buy button that does anything but hand off. The label says so.
  /// Where to buy. A FEW brokers, not all twenty eight.
  ///
  /// The full directory is one tap away. A wall of twenty eight licensed firms
  /// on a stock page is not a service, it is an index, and it buries the one
  /// sentence that actually matters: Fructa does not hold your money and does
  /// not place the trade.
  ///
  /// The ones shown are the first by the admin's sort_order. They are NOT
  /// labelled "popular", because we have no usage data and would be inventing
  /// the claim. Trade opens the firm's own site, in a real browser, and the
  /// order is placed there, with them, not here.
  Widget _whereToBuy(BuildContext context, List<Broker> brokers, Color tint) {
    final c = context.c;
    const show = 3;
    final shown = brokers.take(show).toList();
    final rest = brokers.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        SectionHeader(title: t('stocks.whereToBuy')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            t('stocks.whereToBuy.sub'),
            style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
          ),
        ),
        for (final b in shown) BrokerRow(b, tint: tint),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BrokersPage()),
              ),
              child: Row(
                children: [
                  Text(
                    t('stocks.brokers.seeAll', {'n': '$rest'}),
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18, color: c.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }

}

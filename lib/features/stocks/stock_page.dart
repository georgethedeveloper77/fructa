import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/cta.dart';
import '../../core/widgets/fund_logo.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/stock.dart';
import '../../data/snapshot_providers.dart';

/// Stock detail. Mirrors the fund detail shape (identity, hero figure, stat
/// triad, context lines, risk band, chart) so a stock reads as the same kind of
/// object as a fund, then adds the two things a stock needs and a fund does
/// not: a dividend record and a route to a broker.
///
/// EVERY price-derived surface below is gated on [Stock.hasPrice]:
///   hero figure, day change, market cap, dividend yield, price chart.
/// With no licence they are simply absent, and the hero falls back to the
/// declared dividend per share, which is public data. The page stays useful and
/// stays legal in both states. Do not remove these guards to "fill the layout".
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
              _riskBand(context),
              if (s.hasDividend) _dividends(context, s),
              _howToBuy(context),
              if (brokers.isNotEmpty) _whereToBuy(context, brokers, tint),
              const SizedBox(height: 8),
              Disclaimer(t('stocks.disclaimer'), center: true),
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
    final cells = <(String, String)>[
      if (s.divYield != null)
        (t('stocks.stat.divYield'), '${s.divYield!.toStringAsFixed(1)}%'),
      if (s.marketCap != null)
        (t('stocks.stat.marketCap'), _cap(s.marketCap!)),
      if (s.dpsLatest != null)
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

  Widget _dividends(BuildContext context, Stock s) {
    final c = context.c;
    final rows = s.latestYearDividends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
  Widget _whereToBuy(BuildContext context, List<Broker> brokers, Color tint) {
    final c = context.c;
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
        for (final b in brokers)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: c.s1,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  FundLogo(
                    domain: null,
                    logoUrl: b.logoUrl,
                    seed: b.name,
                    size: 40,
                    brandColor: tint,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (b.blurb != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            b.blurb!,
                            style: TextStyle(color: c.muted, fontSize: 12.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (b.openUrl != null)
                    GestureDetector(
                      onTap: () => _open(b.openUrl!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          t('stocks.trade'),
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

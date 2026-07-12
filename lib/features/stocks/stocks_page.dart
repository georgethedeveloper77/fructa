import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/stock.dart';
import '../../data/snapshot_providers.dart';
import 'stock_page.dart';

/// Stocks list. The tile is a deliberate sibling of `FundTile`: same shell
/// (Material + r16 + hairline), same logo/rank/name/meta/spark/figure rhythm,
/// same mono + tabular figures. A stock should read as the same KIND of object
/// as a fund, because to the user it is: a thing you can put money in.
///
/// What differs is the right-hand figure, and that difference is the licence:
///
///   licensed    price + day change. Ranked by day move.
///   unlicensed  declared dividend per share. Ranked by dividend.
///
/// Both are honest. Neither invents a number. The list never sorts by a price
/// it does not have, and "Top movers" is not offered when there are no moves.
class StocksPage extends ConsumerStatefulWidget {
  const StocksPage({super.key});

  @override
  ConsumerState<StocksPage> createState() => _StocksPageState();
}

enum _Sort { movers, dividend, alpha }

extension on _Sort {
  String get label => switch (this) {
    _Sort.movers => t('stocks.sort.movers'),
    _Sort.dividend => t('stocks.sort.dividend'),
    _Sort.alpha => t('stocks.sort.alpha'),
  };
}

class _StocksPageState extends ConsumerState<StocksPage> {
  String _sector = '';  // empty = the All tab, resolved against i18n at build
  _Sort _sort = _Sort.movers;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stocks = ref.watch(stocksProvider);
    final pricesLive = ref.watch(stockPricesLiveProvider);

    // No licensed prices means nothing to rank by day move, so the control is
    // not offered at all rather than offered and dead.
    final sort = (!pricesLive && _sort == _Sort.movers) ? _Sort.dividend : _sort;

    final sectors = <String>[t('stocks.sectorAll')];
    for (final s in stocks) {
      final sec = s.sector;
      if (sec != null && sec.isNotEmpty && !sectors.contains(sec)) {
        sectors.add(sec);
      }
    }

    final rows =
        stocks
            .where((s) => _sector.isEmpty || s.sector == _sector)
            .toList()
          ..sort((a, b) => switch (sort) {
            _Sort.movers => _cmpNullableDesc(
              a.changePct,
              b.changePct,
              a.name,
              b.name,
            ),
            _Sort.dividend => _cmpNullableDesc(
              a.dpsLatest,
              b.dpsLatest,
              a.name,
              b.name,
            ),
            _Sort.alpha => a.name.compareTo(b.name),
          });

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          t('stocks.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: stocks.isEmpty
          ? _empty(context)
          : ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(
                    t('stocks.listedCount', {'n': '${stocks.length}'}),
                    style: TextStyle(
                      color: c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 11.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (!pricesLive) _noPriceNote(context),
                const SizedBox(height: 12),
                if (sectors.length > 1) ...[
                  _sectorTabs(context, sectors),
                  const SizedBox(height: 8),
                ],
                _sortPills(context, pricesLive, sort),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    rows.length == 1
                        ? t('stocks.countOne')
                        : t('stocks.count', {'n': '${rows.length}'}),
                    style: TextStyle(color: c.faint, fontSize: 11.5),
                  ),
                ),
                for (var i = 0; i < rows.length; i++)
                  StockTile(
                    rows[i],
                    rank: sort == _Sort.alpha ? null : i + 1,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StockPage(rows[i])),
                    ),
                  ),
              ],
            ),
    );
  }

  /// Nulls always sort last, whichever direction. A stock with no dividend
  /// recorded is not a stock with a dividend of zero.
  int _cmpNullableDesc(double? a, double? b, String an, String bn) {
    if (a == null && b == null) return an.compareTo(bn);
    if (a == null) return 1;
    if (b == null) return -1;
    final r = b.compareTo(a);
    return r != 0 ? r : an.compareTo(bn);
  }

  Widget _empty(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(
              t('stocks.empty.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('stocks.empty.body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Says plainly why there is no price, rather than leaving a gap the user has
  /// to explain to themselves.
  Widget _noPriceNote(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: c.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t('stocks.noPriceList'),
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same shell as CategoryTabs: r14, 46px, selected inverts to the text colour.
  Widget _sectorTabs(BuildContext context, List<String> sectors) {
    final c = context.c;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sectors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final s = sectors[i];
          final on = s == _sector || (i == 0 && _sector.isEmpty);
          return GestureDetector(
            onTap: () => setState(() => _sector = i == 0 ? '' : s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: on ? c.text : c.s1,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? c.text : c.line),
              ),
              child: Text(
                s,
                style: TextStyle(
                  color: on ? c.bg : c.muted,
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortPills(BuildContext context, bool pricesLive, _Sort active) {
    final c = context.c;
    final options = <_Sort>[
      // Ranking by day move needs a licensed price. No price, no pill.
      if (pricesLive) _Sort.movers,
      _Sort.dividend,
      _Sort.alpha,
    ];
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = options[i];
          final on = s == active;
          return GestureDetector(
            onTap: () => setState(() => _sort = s),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: on ? c.accent : c.s1,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? c.accent : c.line),
              ),
              child: Text(
                s.label,
                style: TextStyle(
                  color: on ? c.onAccent : c.muted,
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Directory tile for a stock. Mirrors `FundTile`: same Material shell, hairline
/// border, r16, 13/11 padding, fading rank badge, mono tabular figures.
class StockTile extends ConsumerStatefulWidget {
  const StockTile(this.stock, {super.key, required this.onTap, this.rank});

  final Stock stock;
  final VoidCallback onTap;
  final int? rank;

  @override
  ConsumerState<StockTile> createState() => _StockTileState();
}

class _StockTileState extends ConsumerState<StockTile> {
  bool _showRank = true;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.stock;

    final meta = [
      if (s.sector != null && s.sector!.isNotEmpty) s.sector!,
      'NSE',
      s.ticker,
    ].join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FundLogo(
                        domain: null,
                        logoUrl: s.logoUrl,
                        seed: s.name,
                        size: 34,
                        brandColor: s.brandColor,
                      ),
                      if (widget.rank != null)
                        Positioned(
                          left: -5,
                          top: -5,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showRank ? 1 : 0,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOut,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 18),
                                height: 18,
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.rank! <= 3 ? c.accent : c.s2,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: c.s1, width: 1.5),
                                ),
                                child: Text(
                                  '${widget.rank}',
                                  style: TextStyle(
                                    color: widget.rank! <= 3
                                        ? c.onAccent
                                        : c.muted,
                                    fontFamily: fructaFonts.mono,
                                    fontSize: 10,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              meta,
                              style: TextStyle(
                                color: c.faint,
                                fontFamily: fructaFonts.mono,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                          if (s.segment != null && s.segment != 'MIM') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.s3,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                s.segment!,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 9,
                                  letterSpacing: 0.3,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Sparkline is price history, so it exists only under licence.
                if (s.spark.length >= 2) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 52,
                    height: 30,
                    child: CustomPaint(
                      painter: _StockSpark(s.spark, up: c.up, down: c.down),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                _figure(context, s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Price when licensed, declared dividend when not, and an honest blank when
  /// there is neither. Never a zero standing in for a missing number.
  Widget _figure(BuildContext context, Stock s) {
    final c = context.c;

    if (s.hasPrice) {
      final ch = s.changePct;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.closeKes!.toStringAsFixed(2),
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (ch != null) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ch >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 14,
                  color: c.delta(ch),
                ),
                Text(
                  '${ch.abs().toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: c.delta(ch),
                    fontFamily: fructaFonts.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    if (s.hasDividend) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            s.dpsLatest!.toStringAsFixed(2),
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            t('stocks.perShareShort'),
            style: TextStyle(
              color: c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
            ),
          ),
        ],
      );
    }

    return Text(
      '\u2014',
      style: TextStyle(
        color: c.faint,
        fontFamily: fructaFonts.mono,
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Trailing sparkline, same construction as the fund tile's.
class _StockSpark extends CustomPainter {
  _StockSpark(this.points, {required this.up, required this.down});
  final List<double> points;
  final Color up;
  final Color down;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = points.first, hi = points.first;
    for (final v in points) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = size.height - ((points[i] - lo) / span) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = (points.last >= points.first ? up : down).withValues(
          alpha: 0.9,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StockSpark old) => old.points != points;
}

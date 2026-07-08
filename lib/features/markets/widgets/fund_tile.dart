import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/categories.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/fund.dart';
import '../../../data/snapshot_providers.dart';

/// Directory tile (v6 `.tile`)  a card: panel surface, hairline border, 16px
/// radius, 14px padding, 10px inter-card gap. Name wraps (no-ellipsis); the
/// gross rate flashes up/down on refresh. Shows gross + net-of-tax (the honest
/// comparator); funds that quote no single yield (basis 'none') show an
/// em-dash, never a fabricated number.
///
/// [rank] is the fund's position in the current filter+sort. It shows as a
/// small badge on the logo corner that FADES OUT after a couple of seconds
/// long enough to read the ranking, then out of the way for a clean list. It
/// flashes back briefly whenever the rank changes (re-sort). Top 3 wear gold.
class FundTile extends ConsumerStatefulWidget {
  const FundTile(
    this.fund, {
    super.key,
    required this.onTap,
    this.rank,
    this.selectable = false,
    this.selected = false,
    this.onToggleSelect,
    this.brandColor,
    this.delta,
  });

  final Fund fund;
  final VoidCallback onTap;
  final int? rank;
  final bool selectable;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final Color? brandColor;
  final double? delta;

  @override
  ConsumerState<FundTile> createState() => _FundTileState();
}

const _typeNames = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

String _typeLabel(Fund f) {
  final t = _typeNames[f.fundType];
  if (t != null) return '$t \u00b7 ${f.currency}';
  return categoryLabel(f.category); // legacy: tbill / bond / sacco
}

String _commas(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _FundTileState extends ConsumerState<FundTile> {
  double? _prevRate;
  int _flash = 0; // -1 down, 0 none, +1 up

  bool _showRank = true;
  Timer? _rankTimer;

  @override
  void initState() {
    super.initState();
    _prevRate = widget.fund.currentRate;
    _armRankFade();
  }

  /// Show the rank badge, then fade it after ~2.6s. Re-armed when the rank
  /// changes so a re-sort briefly re-reveals positions.
  void _armRankFade() {
    if (widget.rank == null) return;
    _rankTimer?.cancel();
    _showRank = true;
    _rankTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _showRank = false);
    });
  }

  @override
  void didUpdateWidget(covariant FundTile old) {
    super.didUpdateWidget(old);
    if (old.rank != widget.rank) _armRankFade();

    final now = widget.fund.currentRate;
    final was = _prevRate;
    if (now != null && was != null && now != was) {
      setState(() => _flash = now > was ? 1 : -1);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _flash = 0);
      });
    }
    _prevRate = now;
  }

  @override
  void dispose() {
    _rankTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = widget.fund;
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final logoUrl = ref.watch(logoUrlProvider(f.id));
    final d = widget.delta;
    final rateBg = _flash == 0
        ? Colors.transparent
        : (_flash > 0 ? c.upSoft : c.downSoft);

    final rate = f.currentRate;
    final hasRate = f.showsYield && rate != null;
    final net = hasRate ? f.netRate(wht) : null;

    final meta =
        '${_typeLabel(f)}'
        '${f.minInvest != null ? ' \u00b7 min ${f.currency} ${_commas(f.minInvest!)}' : ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: widget.selected ? c.accentSoft : c.s1,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: widget.selected ? c.accent.withValues(alpha: 0.4) : c.line,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.selectable ? widget.onToggleSelect : widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // logo + rank badge (fades) + optional select badge
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      FundLogo(
                        domain: f.logoDomain,
                        logoUrl: logoUrl,
                        seed: f.manager,
                        size: 38,
                        brandColor: widget.brandColor,
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
                      if (widget.selectable && widget.selected)
                        Positioned(
                          right: -3,
                          top: -3,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.s1, width: 2),
                            ),
                            child: Icon(
                              Icons.check,
                              size: 10,
                              color: c.onAccent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                // name + meta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
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
                          if (f.taxFree) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.upSoft,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                'TAX-FREE',
                                style: TextStyle(
                                  color: c.up,
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
                // sparkline from spark[]
                if (f.spark.length >= 2) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 52,
                    height: 30,
                    child: CustomPaint(
                      painter: _TileSpark(f.spark, up: c.up, down: c.down),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                // gross + net + delta
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: rateBg,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        hasRate ? '${rate.toStringAsFixed(2)}%' : '\u2014',
                        style: TextStyle(
                          color: hasRate ? c.text : c.faint,
                          fontFamily: fructaFonts.mono,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (net != null && !f.taxFree) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${net.toStringAsFixed(2)}% net',
                        style: TextStyle(
                          color: c.muted,
                          fontFamily: fructaFonts.mono,
                          fontSize: 11,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (d != null && d != 0) ...[
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            d > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            size: 14,
                            color: c.delta(d),
                          ),
                          Text(
                            d.abs().toStringAsFixed(2),
                            style: TextStyle(
                              color: c.delta(d),
                              fontFamily: fructaFonts.mono,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal trailing sparkline: 1.5px polyline, coloured by overall trend
/// (first vs last point). Self-contained so the tile has no dependency on
/// the chart stack.
class _TileSpark extends CustomPainter {
  _TileSpark(this.points, {required this.up, required this.down});
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
  bool shouldRepaint(_TileSpark old) => old.points != points;
}

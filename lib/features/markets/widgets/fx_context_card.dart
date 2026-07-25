import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/insights/fx_copy.dart';
import '../../../core/series_colors.dart';
import '../../../core/theme.dart';
import '../../../data/snapshot_providers.dart';
import '../../../engine/fx_engine.dart';
import '../currency_compare_page.dart';

/// The wired card. Everything it needs is derived in snapshot_providers, and
/// every one of those providers returns null rather than a placeholder, so the
/// whole section disappears cleanly whenever any part of the picture is
/// missing: no FX history, no USD money market fund, no published mean.
///
/// It will render nothing until fx_rates has been backfilled. That is the
/// designed behaviour, not a fault: [fxMovesProvider] needs 13 monthly points
/// before it will describe a regime, because a two month window is not a trend
/// and calling it "calm" would be an assertion nobody measured.
class FxContextSection extends ConsumerWidget {
  const FxContextSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holding = ref.watch(fxHoldingCaseProvider);
    final series = ref.watch(fxSeriesProvider);
    final line = ref.watch(fxLineProvider);

    if (holding == null || series == null || line == null) {
      return const SizedBox.shrink();
    }

    return FxContextCard(
      holding: holding,
      series: series.mean,
      line: line,
      // The card answers the question at one horizon for one stance. The page
      // answers it for the stance the reader is in, over the horizon they have,
      // and shows what the same bet did every time it could have been placed.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CurrencyComparePage(),
        ),
      ),
    );
  }
}

/// "USD or KES" for the Market context block, sitting under the same kicker as
/// [MarketContextCard]. Inflation, the yield curve and the currency are all
/// macro context, so they share one section at the foot of Markets rather than
/// competing with the fund list above it.
///
/// Deliberately a plain widget with no provider of its own: the wiring lives at
/// the call site, which already knows how to read the snapshot. That keeps the
/// chart, the hurdle geometry and the copy testable without a container.
///
/// Hides itself when there is no series to draw. A currency card with one point
/// on it would be a flat line asserting a stability nobody measured.
class FxContextCard extends StatelessWidget {
  const FxContextCard({
    super.key,
    required this.holding,
    required this.series,
    required this.line,
    this.onTap,
  });

  /// The comparison for someone already holding dollars. The buying case is
  /// derived from it, so the two can never disagree about the quote or the
  /// yields they were built from.
  final FxCase holding;

  /// Monthly means, oldest first, from the snapshot's fx_series block.
  final List<double> series;

  /// The filled copy line. May contain `<b>`.
  final FxLine line;

  final VoidCallback? onTap;

  static const _minPoints = 6;

  @override
  Widget build(BuildContext context) {
    if (series.length < _minPoints) return const SizedBox.shrink();

    final c = context.c;
    final tint = seriesColor(2);
    final buying = holding.copyWith(stance: FxStance.buying);

    final holdBe = holding.breakeven;
    final buyBe = buying.breakeven;
    if (holdBe == null || buyBe == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _head(c, tint),
                const SizedBox(height: 14),
                SizedBox(
                  height: 78,
                  child: _FxSpark(
                    series: series,
                    breakeven: holdBe,
                    color: tint,
                  ),
                ),
                const SizedBox(height: 8),
                _axis(c, tint),
                const SizedBox(height: 12),
                if (line.text.isNotEmpty) ...[
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                      children: _spans(line.text, c.text),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                _hurdles(c, tint, holdBe, buyBe),
                if (onTap != null) ...[
                  const SizedBox(height: 14),
                  _cta(c, tint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(fructaColors c, Color tint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.swap_horiz, size: 17, color: tint),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              t('markets.fx.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              holding.quote.mean.toStringAsFixed(2),
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              holding.quote.measured
                  ? t('markets.fx.sourceQuoted')
                  : t('markets.fx.sourceMean'),
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 8.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _axis(fructaColors c, Color tint) {
    final months = series.length;
    final years = months ~/ 12;
    // Separate singular and plural keys rather than a formatter, matching
    // stocks.countOne / stocks.count. A language that pluralises differently
    // gets to say so instead of receiving an English rule with its own words in
    // it.
    final span = years >= 1
        ? (years == 1
            ? t('markets.fx.spanYearOne')
            : t('markets.fx.spanYears', {'n': '$years'}))
        : t('markets.fx.spanMonths', {'n': '$months'});
    return Row(
      children: [
        Text(
          span,
          style: TextStyle(
            color: c.faint,
            fontFamily: fructaFonts.mono,
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          t('markets.fx.legendShaded'),
          style: TextStyle(
            color: c.faint,
            fontFamily: fructaFonts.mono,
            fontSize: 9,
            letterSpacing: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// The two hurdles side by side. Showing both is the point of the card:
  /// whether the pair has to reach one number or the other depends entirely on
  /// whether the reader already owns dollars, and that is the fact most people
  /// asking this question have never been told.
  Widget _hurdles(fructaColors c, Color tint, double hold, double buy) {
    Widget cell(String label, double value, bool accent) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: c.faint,
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  color: accent ? tint : c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        Divider(height: 1, color: c.line),
        const SizedBox(height: 12),
        Row(
          children: [
            cell(t('markets.fx.hurdleHold'), hold, true),
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: c.line,
            ),
            cell(t('markets.fx.hurdleBuy'), buy, false),
          ],
        ),
      ],
    );
  }

  Widget _cta(fructaColors c, Color tint) {
    return Row(
      children: [
        Text(
          t('markets.fx.cta'),
          style: TextStyle(
            color: tint,
            fontFamily: fructaFonts.mono,
            fontSize: 10.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, size: 15, color: tint),
      ],
    );
  }

  /// Minimal `<b>` renderer, matching how the fund signal templates are
  /// written. Swap for core/widgets/markup.dart if its API takes a style, so
  /// there is one parser rather than two.
  static List<TextSpan> _spans(String src, Color strong) {
    final out = <TextSpan>[];
    final re = RegExp(r'<b>(.*?)</b>', dotAll: true);
    var at = 0;
    for (final m in re.allMatches(src)) {
      if (m.start > at) out.add(TextSpan(text: src.substring(at, m.start)));
      out.add(TextSpan(
        text: m.group(1),
        style: TextStyle(color: strong, fontWeight: FontWeight.w600),
      ));
      at = m.end;
    }
    if (at < src.length) out.add(TextSpan(text: src.substring(at)));
    return out;
  }
}

/// The series, with everything above the break even shaded. The shading is the
/// whole idea: it shows at a glance that the pair has been in the winning zone
/// before, so the hurdle never reads as an argument that it cannot be cleared.
class _FxSpark extends StatefulWidget {
  const _FxSpark({
    required this.series,
    required this.breakeven,
    required this.color,
  });

  final List<double> series;
  final double breakeven;
  final Color color;

  @override
  State<_FxSpark> createState() => _FxSparkState();
}

class _FxSparkState extends State<_FxSpark>
    with SingleTickerProviderStateMixin {
  // Built in initState, never lazily: a late controller whose first touch could
  // be dispose() runs createTicker against a deactivated context.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(
        size: Size.infinite,
        painter: _FxSparkPainter(
          pts: widget.series,
          breakeven: widget.breakeven,
          color: widget.color,
          t: Curves.easeInOutCubic.transform(_c.value),
        ),
      ),
    );
  }
}

class _FxSparkPainter extends CustomPainter {
  _FxSparkPainter({
    required this.pts,
    required this.breakeven,
    required this.color,
    required this.t,
  });

  final List<double> pts;
  final double breakeven;
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;

    var lo = pts.first, hi = pts.first;
    for (final v in pts) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    // The break even has to be inside the frame or the shaded band is either
    // the whole chart or none of it, which says nothing.
    if (breakeven < lo) lo = breakeven;
    if (breakeven > hi) hi = breakeven;

    final raw = hi - lo;
    final pad = (raw == 0 ? 1.0 : raw * 0.12).clamp(0.5, double.infinity);
    lo -= pad;
    hi += pad;
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);

    double xOf(int i) => i / (pts.length - 1) * size.width;
    double yOf(double v) =>
        size.height - ((v - lo) / span).clamp(0.0, 1.0) * size.height;

    // Winning zone: everything above the break even rate.
    final beY = yOf(breakeven);
    canvas.drawRect(
      Rect.fromLTRB(0, 0, size.width, beY),
      Paint()..color = color.withValues(alpha: 0.10),
    );

    // Dashed break even line, drawn by hand because Flutter has no dash phase.
    final dash = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, beY), Offset(x + 4, beY), dash);
    }

    final line = Path()..moveTo(xOf(0), yOf(pts[0]));
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(xOf(i), yOf(pts[i]));
    }

    final metrics = line.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final frac = t.clamp(0.0, 1.0);

    final drawn = Path();
    for (final m in metrics) {
      drawn.addPath(m.extractPath(0, m.length * frac), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final tan = metrics.first.getTangentForOffset(metrics.first.length * frac);
    if (frac > 0.02 && tan != null) {
      canvas.drawCircle(tan.position, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_FxSparkPainter old) =>
      old.t != t ||
      old.color != color ||
      old.breakeven != breakeven ||
      old.pts != pts;
}

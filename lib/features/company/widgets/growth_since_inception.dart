import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/models/period_return.dart';

/// What an amount invested at inception is worth now.
///
/// This card is what a return-basis fund gets INSTEAD of the projection, and the
/// swap is the whole point. A projection compounds a rate forward and therefore
/// makes a claim about the future; this looks backwards at periods that have
/// already closed and makes none. Same shape on the page, opposite epistemic
/// status, and only one of them is available to a fund whose headline is a
/// quarter that has already happened.
///
/// TWO WAYS TO GET THE NUMBER, AND THEY DISAGREE.
///
/// The manager publishes an endpoint: MansaX prints that a million invested in
/// January 2019 was worth 3,594,335 by March 2026. Compounding its published
/// annual returns instead gives about 3,365,000. The gap is roughly 230,000
/// shillings and neither figure is a mistake. The published line is an actual
/// account track; the percentages are each rounded to two places and then
/// multiplied, and rounding compounds along with the returns.
///
/// So the manager's endpoint wins whenever one exists, and a compounded curve is
/// the fallback. When the fallback runs, the card says so, because a number the
/// app derived and a number the manager published are not the same kind of
/// claim and the reader is entitled to know which one is on screen.
class GrowthSinceInception extends StatelessWidget {
  const GrowthSinceInception(this.fund, this.returns, {super.key, this.tint});

  final Fund fund;
  final FundReturns returns;
  final Color? tint;

  /// A round number to grow, in the fund's own currency.
  ///
  /// Presentation, not data: the fact stored is a percentage, and every manager
  /// picks its own base for the same fact. These match the bases the Kenyan
  /// sheets actually print, so the figure on the card reconciles with the figure
  /// on the PDF a reader may have open beside it.
  static double baseFor(String currency) =>
      currency == 'KES' ? 1000000 : 10000;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final growth = returns.growthMultiple;
    if (growth == null) return const SizedBox.shrink();

    final colour = tint ?? c.accent;
    final base = baseFor(fund.currency);
    final end = base * growth.multiple;
    final gain = end - base;
    final months = _months();
    final cagr = months == null ? null : returns.compoundAnnualPct(months);

    // Curve only when compounding it is what produced the endpoint. Drawing a
    // compounded path up to a DIFFERENT, published endpoint would show a line
    // that does not arrive where the number beneath it says it arrives.
    final curve = growth.derived && returns.series.length >= 4
        ? returns.compoundedGrowth(base)
        : const <double>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (curve.length >= 2) ...[
          SizedBox(
            height: 132,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1300),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => CustomPaint(
                painter: _CurvePainter(curve, t, colour),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _Row(
          k: fund.inceptionDate != null
              ? 'Invested ${_monthYear(fund.inceptionDate!)}'
              : 'Invested at inception',
          v: money(fund.currency, base),
        ),
        _Row(
          k: 'Worth today',
          v: money(fund.currency, end),
          vColor: colour,
          strong: true,
        ),
        _Row(
          k: gain >= 0 ? 'Growth' : 'Decline',
          v: '${gain >= 0 ? '+' : ''}${money(fund.currency, gain)}',
          vColor: c.delta(gain),
        ),
        if (cagr != null)
          _Row(
            k: 'Compound annual rate',
            v: '${cagr >= 0 ? '+' : ''}${cagr.toStringAsFixed(2)}%',
            vColor: c.delta(cagr),
          ),
        const SizedBox(height: 10),
        Text(
          growth.derived
              ? 'Compounded from the completed periods above. The manager publishes no growth figure of its own, so this is our arithmetic on its published returns, not a number it has quoted.'
              : 'As published by the fund manager.',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 4),
        Text(
          'Past performance of this fund. Not a projection, and not a forecast.',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
        if (cagr != null) ...[
          const SizedBox(height: 4),
          Text(
            'The compound annual rate is how fast the money actually grew. A manager quoting an "average annual return" is usually averaging its calendar years instead, which is a different figure.',
            style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
          ),
        ],
      ],
    );
  }

  /// Months from inception to the last published period, for the compound rate.
  ///
  /// Null when either end is missing or unparseable, and the rate is then simply
  /// not shown. An annualised figure over a guessed window is worse than none:
  /// it is the same error as annualising a quarter, one level up.
  int? _months() {
    final startIso = fund.inceptionDate;
    if (startIso == null) return null;
    final start = DateTime.tryParse(startIso);
    if (start == null) return null;

    final last = returns.sinceInception ?? returns.latest;
    final endIso = last?.periodEnd ?? fund.returnAsOf;
    final end = endIso == null ? null : DateTime.tryParse(endIso);
    if (end == null) return null;

    final m = (end.year - start.year) * 12 + (end.month - start.month);
    return m > 0 ? m : null;
  }

  static String _monthYear(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.k, required this.v, this.vColor, this.strong = false});

  final String k;
  final String v;
  final Color? vColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            v,
            style: TextStyle(
              color: vColor ?? c.text,
              fontFamily: fructaFonts.mono,
              fontSize: strong ? 19 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points, this.progress, this.colour);

  final List<double> points;
  final double progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = points.first;
    var hi = points.first;
    for (final v in points) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    double x(int i) => i / (points.length - 1) * size.width;
    double y(double v) => size.height - 6 - (v - lo) / span * (size.height - 18);

    // Progressive reveal along the path, matching the sweep the other charts
    // use, so the whole page animates in one language.
    final shown = (points.length * progress).ceil().clamp(2, points.length);
    final path = Path()..moveTo(x(0), y(points[0]));
    for (var i = 1; i < shown; i++) {
      path.lineTo(x(i), y(points[i]));
    }

    final fill = Path.from(path)
      ..lineTo(x(shown - 1), size.height)
      ..lineTo(x(0), size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colour.withValues(alpha: 0.24),
            colour.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      Offset(x(shown - 1), y(points[shown - 1])),
      3.4,
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.progress != progress || old.points != points;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../data/models/fund.dart';
import '../../../data/providers.dart';
import '../markets_controller.dart';

/// A slim live market pulse in the top bar. It plots the leading fund's own
/// history for whatever category the user is viewing, in that category's colour,
/// and the line draws itself in slowly (the way rates actually move) rather than
/// appearing whole. Switching category tabs redraws a touch quicker.
///
/// SACCOs and stocks carry no series here, so on those tabs (and All) it falls
/// back to the money-market leader; with no money-market history either it hides
/// rather than draw a flat lie.
///
/// [onTap] opens the market page.
///
/// It briefly opened the leading FUND instead, on the reasoning that the line
/// is that fund's own history. True, and still the wrong destination: nothing
/// on this strip names a fund, so a reader tapping an unlabelled line in the
/// top bar is asking what the market is doing, not which manager happens to
/// lead this week. Left null the strip is inert, which is what it was before
/// and is still correct on a surface that does not want the navigation.
class MarketPulse extends ConsumerStatefulWidget {
  const MarketPulse({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  ConsumerState<MarketPulse> createState() => _MarketPulseState();
}

class _MarketPulseState extends ConsumerState<MarketPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  List<double> _lastSeries = const [];
  bool _firstDraw = true;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
    final tab = ref.watch(marketTabProvider);
    final ccy = ref.watch(marketMoneyCcyProvider);

    var sel = funds.where(tab.matches).toList();
    if (tab == MarketTab.moneyMarket && ccy != null) {
      sel = sel.where((f) => f.currency == ccy).toList();
    }

    var lead = _leader(sel);
    var color = _tabColor(tab);
    if (lead == null) {
      lead = _leader(funds.where(MarketTab.moneyMarket.matches).toList());
      color = fundTypeColor('mmf');
    }
    if (lead == null) return const SizedBox.shrink();

    final full = lead.spark;
    final series = full.length > 40 ? full.sublist(full.length - 40) : full;
    if (series.length < 2) return const SizedBox.shrink();

    // Replay the draw-on when the plotted series changes (first paint, or a
    // category switch). A tab switch redraws quicker than the first appearance.
    if (!_same(_lastSeries, series)) {
      final first = _firstDraw;
      _lastSeries = series;
      _firstDraw = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _c.duration = Duration(milliseconds: first ? 1600 : 650);
        _c.forward(from: 0);
      });
    }

    final chart = SizedBox(
      height: 30,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          size: Size.infinite,
          painter: _PulsePainter(series, color, _c.value),
        ),
      ),
    );

    final onTap = widget.onTap;
    if (onTap == null) return chart;

    // Opaque, so the whole 30px band takes the tap rather than only the two
    // pixels of stroke. A sparkline is a thin target and hit-testing the drawn
    // path would make it a lottery.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chart,
    );
  }
}

/// The highest-rate fund in [funds] that carries enough history to draw. Its own
/// spark is what the pulse plots, so the line has real shape.
Fund? _leader(List<Fund> funds) {
  Fund? best;
  var bestRate = double.negativeInfinity;
  for (final f in funds) {
    if (f.spark.length < 2) continue;
    final r = f.currentRate ?? double.negativeInfinity;
    if (r > bestRate) {
      bestRate = r;
      best = f;
    }
  }
  return best;
}

/// The line colour for a tab, from the central data palette. sacco/stock/all
/// rarely reach here because they fall back to the money-market line.
Color _tabColor(MarketTab t) => switch (t) {
  MarketTab.moneyMarket => fundTypeColor('mmf'),
  MarketTab.fixedIncome => fundTypeColor('fixed_income'),
  MarketTab.equity => fundTypeColor('equity'),
  MarketTab.balanced => fundTypeColor('balanced'),
  MarketTab.special => fundTypeColor('special'),
  MarketTab.sacco => categoryColor('sacco'),
  MarketTab.stock => categoryColor('stock'),
  MarketTab.all => fundTypeColor('mmf'),
};

/// Frames the domain on the series' own padded range so a slow line still fills
/// the band, then draws the leading [t] fraction of the line with the area under
/// it clipped to the drawing tip and a live dot at the tip.
class _PulsePainter extends CustomPainter {
  _PulsePainter(this.pts, this.color, this.t);

  final List<double> pts;
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
    final raw = hi - lo;
    final pad = (raw == 0 ? 0.05 : raw * 0.5).clamp(0.02, double.infinity);
    lo -= pad;
    hi += pad;
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);

    double xOf(int i) => i / (pts.length - 1) * size.width;
    double yOf(double v) =>
        size.height - ((v - lo) / span).clamp(0.0, 1.0) * (size.height - 4) - 2;

    final line = Path()..moveTo(xOf(0), yOf(pts[0]));
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(xOf(i), yOf(pts[i]));
    }

    final metrics = line.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final frac = t.clamp(0.0, 1.0);
    final tan = metrics.first.getTangentForOffset(metrics.first.length * frac);
    final tipX = tan?.position.dx ?? 0;

    // Area under the full line, clipped to how far the line has drawn.
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, 0, tipX <= 0 ? 0.001 : tipX, size.height),
    );
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // The drawn portion of the line.
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

    if (frac > 0.02 && tan != null) {
      canvas.drawCircle(tan.position, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.t != t || old.color != color || old.pts != pts;
}

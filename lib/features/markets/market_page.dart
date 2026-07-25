import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fructa/core/series_colors.dart';

import '../../core/category_colors.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/models/market_history.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// The market, behind the pulse on the top bar.
///
/// The pulse plots the leading fund's own history, so for a while its tap went
/// to that fund. That was the wrong destination: a reader who taps a line
/// labelled with no fund name is asking about the market, not about whichever
/// manager happens to lead this week.
///
/// Three things, in the order they answer that question. What the spread is
/// today, what it has done since 2024, and where the market's money actually
/// sits against what that money is paid. It replaces MarketByAumPage rather
/// than sitting beside it: that page was the third of these on its own.
class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});

  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  String _type = 'mmf';
  String _ccy = 'KES';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final history = ref.watch(marketHistoryProvider);
    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];

    final wht = cfg.whtPct;
    final infl = cfg.inflationPct;
    final tb91 = cfg.tbill91Pct;

    double net(Fund f) {
      final r = f.currentRate ?? 0;
      return f.taxFree ? r : r * (1 - wht / 100);
    }

    bool quotes(Fund f) => f.retail && f.showsYield && (f.currentRate ?? 0) > 0;

    // Tabs are built from what the book actually holds, so a category added
    // next quarter appears without an edit here, and one nobody quotes never
    // shows an empty ladder.
    final pairs = <String, List<Fund>>{};
    for (final f in funds.where(quotes)) {
      final t = f.fundType;
      if (t == null) continue;
      (pairs['$t|${f.currency}'] ??= []).add(f);
    }
    final keys = pairs.keys.toList()
      ..sort((a, b) => pairs[b]!.length.compareTo(pairs[a]!.length));
    if (keys.isEmpty) return _empty(c);

    final key = pairs.containsKey('$_type|$_ccy') ? '$_type|$_ccy' : keys.first;
    final shown = [...pairs[key]!]..sort((a, b) => net(a).compareTo(net(b)));
    final tint = fundTypeColor(key.split('|').first);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: c.text),
        title: Text(
          t('market.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 44),
        children: [
          _Ladder(
            key: ValueKey(key),
            funds: shown,
            net: net,
            tint: tint,
            inflation: infl,
            tbill: tb91,
            label: _pairLabel(key),
          ),
          _Tabs(
            keys: keys,
            selected: key,
            labelOf: _pairLabel,
            onTap: (k) => setState(() {
              final p = k.split('|');
              _type = p.first;
              _ccy = p.last;
            }),
          ),
          _Trend(
            key: ValueKey('trend-$key'),
            points: history.series(key.split('|').first, key.split('|').last),
            tint: tint,
            inflation: infl,
            tbill: tb91,
          ),
          _MoneyVsPays(
            funds: funds.where(quotes).toList(),
            net: net,
            tbill: tb91,
          ),
          const _Venues(),
          NoteCard(t('market.note'), title: t('common.goodToKnow')),
        ],
      ),
    );
  }

  String _pairLabel(String key) {
    final p = key.split('|');
    return '${t('fundType.${p.first}')} ${p.last}';
  }

  Widget _empty(fructaColors c) => Scaffold(
    backgroundColor: c.bg,
    appBar: AppBar(
      backgroundColor: c.bg,
      elevation: 0,
      iconTheme: IconThemeData(color: c.text),
      title: Text(t('market.title'), style: TextStyle(color: c.text)),
    ),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Text(
        t('market.empty'),
        textAlign: TextAlign.center,
        style: TextStyle(color: c.muted, height: 1.6),
      ),
    ),
  );
}

// ── the ladder ────────────────────────────────────────────────────────────

/// Every retail fund in the category as one tick on a single net-yield axis,
/// with inflation and the 91-day bill drawn as gates.
///
/// The headline is the SPREAD, not an average. The distance between the best
/// and the worst is the reason to compare at all, and no publisher in Kenya
/// prints it. A tick below inflation is drawn in the down colour, because a
/// fund that loses buying power is a different object from one that merely
/// trails.
class _Ladder extends StatefulWidget {
  const _Ladder({
    super.key,
    required this.funds,
    required this.net,
    required this.tint,
    required this.inflation,
    required this.tbill,
    required this.label,
  });

  final List<Fund> funds;
  final double Function(Fund) net;
  final Color tint;
  final double inflation;
  final double tbill;
  final String label;

  @override
  State<_Ladder> createState() => _LadderState();
}

class _LadderState extends State<_Ladder> with SingleTickerProviderStateMixin {
  // Built in initState, never lazily: a late controller whose first touch could
  // be dispose() runs createTicker against a deactivated context.
  late final AnimationController _c;
  Fund? _touched;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
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
    final c = context.c;
    final f = widget.funds;
    if (f.length < 2) return const SizedBox.shrink();

    final vals = f.map(widget.net).toList();
    final median = vals[vals.length ~/ 2];
    final worst = vals.first;
    final best = vals.last;
    final lo = math.min(widget.inflation, worst) - 0.9;
    final hi = best + 0.9;
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final belowInflation = vals.where((v) => v < widget.inflation).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('market.kicker', {
              'label': widget.label,
              'n': '${f.length}',
            }).toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 9.5,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _CountUp(
                value: best - worst,
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  t('market.spread'),
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            belowInflation > 0
                ? t('market.belowInflation', {'n': '$belowInflation'})
                : t('market.allBeatInflation'),
            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 126,
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                double x(double v) => ((v - lo) / span) * w;

                return AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: Container(height: 1, color: c.line2),
                      ),
                      _gate(
                        c,
                        x(widget.inflation),
                        c.down,
                        t('market.gate.inflation'),
                      ),
                      _gate(
                        c,
                        x(widget.tbill),
                        c.faint,
                        t('market.gate.tbill'),
                      ),
                      for (var i = 0; i < f.length; i++)
                        _tick(
                          c,
                          f[i],
                          vals[i],
                          median,
                          x(vals[i]),
                          i,
                          f.length,
                          best,
                          worst,
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _scale(c, lo),
                            _scale(c, (lo + hi) / 2),
                            _scale(c, hi),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(height: 38, child: _read(c, median)),
        ],
      ),
    );
  }

  Widget _scale(fructaColors c, double v) => Text(
    '${v.toStringAsFixed(0)}%',
    style: TextStyle(
      color: c.faint,
      fontFamily: fructaFonts.mono,
      fontSize: 9,
      letterSpacing: 0.5,
    ),
  );

  Widget _gate(fructaColors c, double left, Color color, String label) =>
      Positioned(
        left: left,
        top: 4,
        bottom: 24,
        child: Opacity(
          opacity: Curves.easeIn.transform(_c.value.clamp(0.0, 1.0)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 1, color: color.withValues(alpha: 0.55)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: fructaFonts.mono,
                  fontSize: 8.5,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _tick(
    fructaColors c,
    Fund fund,
    double v,
    double median,
    double left,
    int i,
    int n,
    double best,
    double worst,
  ) {
    // Staggered along the ladder, so it reads as filling left to right rather
    // than every tick jumping at once.
    final start = (i / n) * 0.45;
    final p = Curves.easeOutCubic.transform(
      ((_c.value - start) / (1 - start)).clamp(0.0, 1.0),
    );
    final isMedian = (v - median).abs() < 1e-9;
    final target = isMedian
        ? 86.0
        : 56.0 +
              ((v - worst) / ((best - worst) == 0 ? 1 : best - worst)) * 28.0;
    final below = v < widget.inflation;
    final on = _touched?.id == fund.id;

    return Positioned(
      left: left - 6,
      bottom: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _touched = fund),
        child: SizedBox(
          width: 12,
          height: target * p + 2,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: on ? 4 : (isMedian ? 3 : 2),
              height: target * p,
              decoration: BoxDecoration(
                color: below ? c.down : widget.tint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _read(fructaColors c, double median) {
    final f = _touched;
    final base = TextStyle(color: c.muted, fontSize: 12, height: 1.5);
    final strong = TextStyle(
      color: c.text,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w600,
    );
    final mono = TextStyle(
      color: c.accent,
      fontFamily: fructaFonts.mono,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w600,
    );

    if (f == null) {
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: t('market.medianIs')),
            TextSpan(text: ' ${median.toStringAsFixed(2)}% ', style: mono),
            TextSpan(text: t('market.touchHint')),
          ],
        ),
      );
    }
    final v = widget.net(f);
    final gap = v - widget.inflation;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: f.name, style: strong),
          TextSpan(text: '  \u00b7 '),
          TextSpan(text: '${v.toStringAsFixed(2)}%', style: mono),
          TextSpan(text: ' ${t('market.netSuffix')} \u00b7 '),
          if (gap >= 0)
            TextSpan(
              text: t('market.aboveInflation', {'d': gap.toStringAsFixed(2)}),
            )
          else
            TextSpan(
              text: t('market.underInflation'),
              style: TextStyle(color: c.down, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// ── tabs ──────────────────────────────────────────────────────────────────

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.keys,
    required this.selected,
    required this.labelOf,
    required this.onTap,
  });

  final List<String> keys;
  final String selected;
  final String Function(String) labelOf;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          for (final k in keys) ...[
            if (k != keys.first) const SizedBox(width: 7),
            GestureDetector(
              onTap: () => onTap(k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: k == selected ? c.text : c.s1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: k == selected ? c.text : c.line),
                ),
                child: Text(
                  labelOf(k),
                  style: TextStyle(
                    color: k == selected ? c.bg : c.muted,
                    fontSize: 12,
                    fontWeight: k == selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── the trend ─────────────────────────────────────────────────────────────

/// Median net yield by month, on a real date axis.
///
/// The line connects only months where at least [MarketPoint.reliable] managers
/// stood behind the median. Thin months are still drawn, hollow and off the
/// line, because they are data rather than error: they simply are not the
/// market. In the July 2026 snapshot the eight-fund money market month printed
/// 10.14 against neighbours of 9.78 and 9.50, while the five-fund special month
/// printed 7.61 against 11.37. Connecting either would have drawn a turn that
/// did not happen.
class _Trend extends StatefulWidget {
  const _Trend({
    super.key,
    required this.points,
    required this.tint,
    required this.inflation,
    required this.tbill,
  });

  final List<MarketPoint> points;
  final Color tint;
  final double inflation;
  final double tbill;

  @override
  State<_Trend> createState() => _TrendState();
}

class _TrendState extends State<_Trend> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
    final c = context.c;
    final pts = widget.points;
    final firm = pts.where((p) => p.isReliable).toList();

    // Nothing to draw is the normal state for a category two managers quote,
    // and for every snapshot published before the builder emitted the block.
    if (firm.length < 2) return const SizedBox.shrink();

    final drop = firm.first.median - firm.last.median;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              t('market.trend.title').toUpperCase(),
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 9.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CountUp(
                      value: drop.abs(),
                      signed: false,
                      style: TextStyle(
                        color: drop > 0 ? c.down : c.up,
                        fontFamily: fructaFonts.mono,
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t(
                          drop > 0 ? 'market.trend.fell' : 'market.trend.rose',
                          {'m': _monthYear(firm.first.month)},
                        ),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 172,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _TrendPainter(
                        points: pts,
                        tint: widget.tint,
                        inflation: widget.inflation,
                        tbill: widget.tbill,
                        line: c.line2,
                        faint: c.faint,
                        down: c.down,
                        bg: c.bg,
                        inflationLabel: t('market.gate.inflation'),
                        tbillLabel: t('market.gate.tbill'),
                        t: Curves.easeInOutCubic.transform(_c.value),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _axis(c, _monthYear(pts.first.month)),
                    _axis(c, _monthYear(pts.last.month)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _axis(fructaColors c, String s) => Text(
    s,
    style: TextStyle(
      color: c.faint,
      fontFamily: fructaFonts.mono,
      fontSize: 8.5,
      letterSpacing: 0.5,
    ),
  );
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthYear(DateTime d) =>
    '${_months[(d.month - 1).clamp(0, 11)]} ${d.year % 100}';

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.tint,
    required this.inflation,
    required this.tbill,
    required this.line,
    required this.faint,
    required this.down,
    required this.bg,
    required this.inflationLabel,
    required this.tbillLabel,
    required this.t,
  });

  final List<MarketPoint> points;
  final Color tint;
  final double inflation;
  final double tbill;
  final Color line;
  final Color faint;
  final Color down;
  final Color bg;
  final String inflationLabel;
  final String tbillLabel;
  final double t;

  static int _mi(DateTime d) => d.year * 12 + d.month;

  @override
  void paint(Canvas canvas, Size size) {
    final firm = points.where((p) => p.isReliable).toList();
    if (firm.length < 2) return;

    const padR = 34.0;
    final w = size.width - padR;
    final h = size.height;

    // Positioned by real month, not by index. The series has gaps in it (no
    // month between June 2024 and January 2025 cleared the filing threshold),
    // and spacing the points evenly would quietly close them.
    final m0 = _mi(points.first.month);
    final m1 = _mi(points.last.month);
    final mSpan = (m1 - m0) == 0 ? 1 : m1 - m0;

    var lo = inflation, hi = inflation;
    for (final p in points) {
      lo = math.min(lo, p.lo);
      hi = math.max(hi, p.hi);
    }
    lo -= 1;
    hi += 1;
    final vSpan = (hi - lo) == 0 ? 1.0 : hi - lo;

    double x(DateTime d) => (_mi(d) - m0) / mSpan * w;
    double y(double v) => (1 - (v - lo) / vSpan) * h;

    // The lo-hi band. The spread is as much the story as the median: July 2026
    // runs 5.14 to 11.74, and the bottom of that band is under inflation.
    final band = Path()..moveTo(x(firm.first.month), y(firm.first.hi));
    for (final p in firm.skip(1)) {
      band.lineTo(x(p.month), y(p.hi));
    }
    for (final p in firm.reversed) {
      band.lineTo(x(p.month), y(p.lo));
    }
    band.close();
    canvas.drawPath(
      band,
      Paint()..color = tint.withValues(alpha: 0.13 * t.clamp(0.0, 1.0)),
    );

    void ref(double v, Color color, String label) {
      if (v < lo || v > hi) return;
      final yy = y(v);
      final p = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (var dx = 0.0; dx < w; dx += 7) {
        canvas.drawLine(Offset(dx, yy), Offset(dx + 3, yy), p);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: color, fontSize: 8, letterSpacing: 0.6),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w + 4, yy - tp.height / 2));
    }

    ref(inflation, down, inflationLabel);
    ref(tbill, faint, tbillLabel);

    final path = Path()..moveTo(x(firm.first.month), y(firm.first.median));
    for (final p in firm.skip(1)) {
      path.lineTo(x(p.month), y(p.median));
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final frac = t.clamp(0.0, 1.0);
    final drawn = Path();
    for (final m in metrics) {
      drawn.addPath(m.extractPath(0, m.length * frac), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = tint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots land as the line reaches them.
    final reached = metrics.first.length * frac;
    var walked = 0.0;
    for (var i = 0; i < firm.length; i++) {
      if (i > 0) {
        walked +=
            (Offset(x(firm[i].month), y(firm[i].median)) -
                    Offset(x(firm[i - 1].month), y(firm[i - 1].median)))
                .distance;
      }
      if (walked > reached) break;
      canvas.drawCircle(
        Offset(x(firm[i].month), y(firm[i].median)),
        3,
        Paint()..color = tint,
      );
    }

    // Thin months, hollow and unconnected. Drawn last so they sit above the
    // band, and only once the line has finished, so they read as a footnote to
    // it rather than part of it.
    if (frac > 0.96) {
      for (final p in points.where((p) => !p.isReliable)) {
        final o = Offset(x(p.month), y(p.median));
        canvas.drawCircle(o, 3, Paint()..color = bg);
        canvas.drawCircle(
          o,
          3,
          Paint()
            ..color = tint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.t != t || old.points != points || old.tint != tint;
}

// ── where the money is, what it pays ──────────────────────────────────────

/// The join nobody makes. The CMA return says where the market's money sits;
/// our own rate table says what it pays. Side by side, with the 91-day bill as
/// the bar every one of them has to clear, is the analysis.
class _MoneyVsPays extends ConsumerWidget {
  const _MoneyVsPays({
    required this.funds,
    required this.net,
    required this.tbill,
  });

  final List<Fund> funds;
  final double Function(Fund) net;
  final double tbill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final types = cfg.marketFundTypes();
    if (types.isEmpty) return const SizedBox.shrink();

    double? medianOf(String type) {
      final vs =
          funds
              .where((f) => f.fundType == type && f.currency == 'KES')
              .map(net)
              .toList()
            ..sort();
      return vs.isEmpty ? null : vs[vs.length ~/ 2];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              t('market.money.title').toUpperCase(),
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 9.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                for (var i = 0; i < types.length; i++) ...[
                  if (i > 0) const SizedBox(height: 15),
                  _MoneyRow(
                    label: t('fundType.${types[i].type}'),
                    color: fundTypeColor(types[i].type),
                    share: types[i].share,
                    aum: _compact(types[i].aumKes),
                    median: medianOf(types[i].type),
                    tbill: tbill,
                    delay: i * 90,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 229_000_000_000 to "229B". Local rather than shared: the market page is
  /// the only surface that prints a figure this large.
  static String _compact(double? v) {
    if (v == null || v <= 0) return '';
    if (v >= 1e12) {
      final x = v / 1e12;
      return '${x >= 10 ? x.round() : x.toStringAsFixed(1)}T';
    }
    if (v >= 1e9) {
      final x = v / 1e9;
      return '${x >= 10 ? x.round() : x.toStringAsFixed(1)}B';
    }
    if (v >= 1e6) return '${(v / 1e6).round()}M';
    return v.round().toString();
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.color,
    required this.share,
    required this.aum,
    required this.median,
    required this.tbill,
    required this.delay,
  });

  final String label;
  final Color color;
  final double share;
  final String aum;
  final double? median;
  final double tbill;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = median;
    final d = m == null ? null : m - tbill;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (m == null)
              Text(
                t('market.money.noYield'),
                style: TextStyle(color: c.faint, fontSize: 12),
              )
            else
              _CountUp(
                value: m,
                suffix: '%',
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    children: [
                      // The channel is tinted with the row's own colour rather
                      // than left as a neutral surface. With a grey track the
                      // row read as grey furniture containing a dab of colour;
                      // tinted, the whole bar belongs to its fund type and the
                      // fill is the part that is full.
                      Positioned.fill(
                        child: ColoredBox(color: barTrack(color)),
                      ),
                      // Positioned.fill on the FILL too, not only on the
                      // track. FractionallySizedBox with no heightFactor
                      // passes the incoming height constraint straight
                      // through, and a childless ColoredBox under a loose one
                      // lays out at zero. The track was tight and painted, the
                      // fill was loose and did not, which is exactly the grey
                      // empty bar on the screenshot.
                      Positioned.fill(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(milliseconds: 900 + delay),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: (share / 100).clamp(0.0, 1.0) * v,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: barFill(color),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            SizedBox(
              width: 66,
              child: Text(
                aum.isEmpty
                    ? '${share.toStringAsFixed(1)}%'
                    : '${share.toStringAsFixed(1)}% \u00b7 $aum',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: Text(
                d == null
                    ? ''
                    : t('market.money.vs91', {
                        'v': '${d >= 0 ? '+' : ''}${d.toStringAsFixed(2)}',
                      }),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: d == null ? c.faint : (d >= 0 ? c.up : c.down),
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── a number that arrives rather than appears ─────────────────────────────

class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.style,
    this.suffix = '',
    this.signed = false,
    this.duration = const Duration(milliseconds: 1000),
  });

  final double value;
  final TextStyle style;
  final String suffix;
  final bool signed;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: duration,
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Text(
      '${signed && v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}$suffix',
      style: style,
    ),
  );
}

// ── the money that is not in a fund ───────────────────────────────────────

/// SACCOs and the NSE, each with the one number that describes it and the one
/// sentence that stops it being read as a fund.
///
/// NEITHER GOES ON THE LADDER, and the reasons are different.
///
/// A SACCO is deliberately not a Fund in this codebase: it pays two rates on
/// two pots, and `Sacco` refuses to expose a `rate` getter precisely so no
/// widget can print an unlabelled percentage. Feeding it through a ladder typed
/// on `Fund` would be the flattening that model exists to prevent. It also pays
/// once a year, needs membership, and `Sacco.locked` is a constant: the money is
/// not callable. Comparable to a money market yield, not interchangeable with
/// one.
///
/// A share is not a yield at all. The dividend yield IS a yield, and it is shown
/// here, but it is the one number on this page that carries the risk of losing
/// the capital that pays it. On the same axis as a money market fund it would
/// read as a better version of the same thing.
class _Venues extends ConsumerWidget {
  const _Venues();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final saccos = ref.watch(saccosProvider);
    final stocks = ref.watch(stocksProvider);

    // Ranked on DEPOSITS, never on the dividend. The dividend is the bigger
    // percentage and the smaller cheque, because it is paid on a capped pot,
    // and every SACCO headline in Kenya leads with it.
    final deposits =
        saccos
            .where((s) => s.hasDepositRate)
            .map((s) => s.interestOnDeposits!)
            .toList()
          ..sort();
    final saccoMedian = deposits.isEmpty
        ? null
        : deposits[deposits.length ~/ 2];
    final joinable = saccos.where((s) => s.isActionable).length;

    // Only counters that actually traded carry a price, and about ten of the
    // sixty four do not on a given day. The label says "that traded" rather
    // than implying the whole exchange.
    final priced = stocks.where((s) => s.hasPrice).toList();
    final cap = priced.fold<double>(0, (a, s) => a + (s.marketCap ?? 0));
    final yields =
        priced
            .map((s) => s.divYield)
            .whereType<double>()
            .where((v) => v > 0)
            .toList()
          ..sort();
    final divMedian = yields.isEmpty ? null : yields[yields.length ~/ 2];

    if (saccoMedian == null && cap <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              t('market.venue.title').toUpperCase(),
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 9.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                if (saccoMedian != null)
                  _Venue(
                    badge: 'SAC',
                    tint: categoryColor('sacco'),
                    title: t('market.venue.sacco'),
                    value: saccoMedian,
                    suffix: '%',
                    body: t('market.venue.saccoBody', {
                      'n': '${saccos.length}',
                      'j': '$joinable',
                    }),
                    divider: cap > 0,
                  ),
                if (cap > 0)
                  _Venue(
                    badge: 'NSE',
                    tint: categoryColor('stock'),
                    title: t('market.venue.nse'),
                    value: cap / 1e12,
                    suffix: 'T',
                    body: divMedian == null
                        ? t('market.venue.nseBody', {'n': '${priced.length}'})
                        : t('market.venue.nseBodyYield', {
                            'n': '${priced.length}',
                            'y': divMedian.toStringAsFixed(2),
                          }),
                    divider: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Venue extends StatelessWidget {
  const _Venue({
    required this.badge,
    required this.tint,
    required this.title,
    required this.value,
    required this.suffix,
    required this.body,
    required this.divider,
  });

  final String badge;
  final Color tint;
  final String title;
  final double value;
  final String suffix;
  final String body;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              badge,
              style: TextStyle(
                color: tint,
                fontFamily: fructaFonts.mono,
                fontSize: 10,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CountUp(
                      value: value,
                      suffix: suffix,
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
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

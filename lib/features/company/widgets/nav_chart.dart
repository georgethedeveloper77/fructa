import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/range_bar.dart';
import '../../../data/models/nav_history.dart';
import '../../../data/providers.dart';

/// The price line for a `basis == 'nav'` fund. [RateChart]'s twin.
///
/// A priced fund had no chart at all. `RateChart` sits behind
/// `fund.showsYield`, so an equity, balanced or priced special fund rendered a
/// headline, a set of terms, and nothing in between: the one page where a
/// price movement IS the return showed no movement.
///
/// Deliberately NOT `RateChart` with a different provider. The two differ in
/// three ways that each matter. A price is an amount in the fund's own
/// currency, so it needs a currency and more decimals than a percentage. A
/// price series has no meaningful floor at zero, so the axis is free to sit
/// anywhere. And the number a reader wants from it is not the level but the
/// CHANGE across the window, which a yield chart never has to state because the
/// level is the answer there.
class NavChart extends ConsumerStatefulWidget {
  const NavChart(this.fundId, {super.key, required this.currency, this.color});

  final String fundId;
  final String currency;
  final Color? color;

  @override
  ConsumerState<NavChart> createState() => _NavChartState();
}

class _NavChartState extends ConsumerState<NavChart> {
  ChartRange _range = ChartRange.y1;
  bool _userPicked = false;

  List<NavHistory> _inRange(List<NavHistory> all, ChartRange r) {
    if (all.isEmpty) return all;
    final last = DateTime.parse(all.last.asOf);
    final cutoff = last.subtract(Duration(days: r.days));
    return all.where((p) => !DateTime.parse(p.asOf).isBefore(cutoff)).toList();
  }

  /// Smallest window holding at least two points, falling back to the widest.
  ///
  /// Defaults wider than [RateChart] does. Rates are scraped several times a
  /// week; NAV marks arrive when a manager publishes a fact sheet, which is
  /// monthly at best and quarterly in practice, so opening on 1W would show
  /// "not enough data" on a fund with three good years behind it.
  ChartRange _autoRange(List<NavHistory> all) {
    final ranges = [...ChartRange.values]
      ..sort((a, b) => a.days.compareTo(b.days));
    for (final r in ranges) {
      if (_inRange(all, r).length >= 2) return r;
    }
    return ranges.last;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final line = widget.color ?? c.accent;
    final async = ref.watch(navHistoryProvider(widget.fundId));

    return async.when(
      loading: () => SizedBox(
        height: 180,
        child: Center(child: AppLoader(color: line)),
      ),
      // The reason is stated, not swallowed. A priced fund whose series fails to
      // load looks identical to one that has never been priced, and those are
      // different problems for whoever has to fix them.
      error: (e, _) => SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Could not load the price history.',
            style: TextStyle(color: c.muted),
          ),
        ),
      ),
      data: (all) {
        final sorted = [...all]..sort((a, b) => a.asOf.compareTo(b.asOf));

        if (sorted.length < 2) {
          return _Empty(hasOne: sorted.length == 1);
        }

        final effective = _userPicked ? _range : _autoRange(sorted);
        final points = _inRange(sorted, effective);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (points.length >= 2) _ChangeLine(points, widget.currency),
            SizedBox(
              height: 180,
              child: points.length < 2
                  ? Center(
                      child: Text(
                        'Not enough prices for ${effective.label}.',
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : _Chart(points, line, widget.currency),
            ),
            RangeBar(
              value: effective,
              onChanged: (r) => setState(() {
                _range = r;
                _userPicked = true;
              }),
            ),
          ],
        );
      },
    );
  }
}

/// What the window actually did, in words and a percentage.
///
/// The chart shows the shape; this states the fact. On a priced fund the change
/// across the window IS the return, and leaving a reader to estimate it off an
/// axis is leaving them to guess at the only number they came for.
class _ChangeLine extends StatelessWidget {
  const _ChangeLine(this.points, this.currency);
  final List<NavHistory> points;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final first = points.first.price;
    final last = points.last.price;
    if (first <= 0) return const SizedBox.shrink();
    final pct = (last - first) / first * 100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$currency ${last.toStringAsFixed(4)}',
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: c.delta(pct),
              fontFamily: fructaFonts.mono,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'over this window',
            style: TextStyle(color: c.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// The state almost every priced fund in the database is actually in.
///
/// No Kenyan fact sheet reviewed so far prints a numeric unit price, so this is
/// not an edge case, it is the common one. It gets a sentence rather than a
/// blank box, because a page that renders nothing reads as broken while a page
/// that says what is missing reads as honest.
class _Empty extends StatelessWidget {
  const _Empty({required this.hasOne});
  final bool hasOne;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 150,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        hasOne
            ? 'Only one price on record, so there is nothing to draw a line between yet. The next published price completes the chart.'
            : 'No unit price published yet. This fund reports performance as a price per unit, and no numeric price has been printed on a fact sheet we hold.',
        textAlign: TextAlign.center,
        style: TextStyle(color: c.faint, fontSize: 12, height: 1.6),
      ),
    );
  }
}

class _Chart extends StatefulWidget {
  const _Chart(this.points, this.color, this.currency);
  final List<NavHistory> points;
  final Color color;
  final String currency;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> with SingleTickerProviderStateMixin {
  // Built in initState, never lazily: a `late final` controller whose first
  // access could be dispose() runs createTicker on a deactivated context.
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
  void didUpdateWidget(covariant _Chart old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final points = widget.points;
    final color = widget.color;
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].price),
    ];
    final prices = points.map((p) => p.price);
    final lo = prices.reduce((a, b) => a < b ? a : b);
    final hi = prices.reduce((a, b) => a > b ? a : b);
    // Proportional padding, unlike the rate chart's absolute clamp. A unit price
    // can be 12.48 or 1,240.00 depending on the fund, so a fixed 0.15 floor
    // would be invisible on one and dominate the other.
    final pad = ((hi - lo) * 0.25).clamp(hi * 0.002, double.infinity);

    final labelStyle = TextStyle(
      color: c.faint,
      fontSize: 10,
      fontFamily: fructaFonts.mono,
    );

    // No clamp to zero. A price axis has no natural floor, and forcing one on a
    // fund trading near 1,200 would flatten every real movement into a
    // horizontal line at the top of the box.
    final minY = lo - pad;
    final maxY = hi + pad;
    final yStep = ((maxY - minY) / 4).clamp(0.0001, double.infinity);
    final n = points.length;
    final xStep = ((n - 1) / 3).clamp(1.0, (n - 1).toDouble());

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final visible = _reveal(
          spots,
          Curves.easeInOutCubic.transform(_c.value),
        );
        return LineChart(
          LineChartData(
            minX: 0,
            maxX: (n - 1).toDouble(),
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yStep,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: c.line, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              show: true,
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: yStep,
                  reservedSize: 52,
                  getTitlesWidget: (value, meta) {
                    if (value <= minY || value >= maxY) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        value.toStringAsFixed(2),
                        style: labelStyle,
                        textAlign: TextAlign.left,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: xStep,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i >= n) return const SizedBox.shrink();
                    final d = DateTime.tryParse(points[i].asOf);
                    if (d == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${_mon(d.month)} \u2019${d.year % 100}',
                        style: labelStyle,
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => c.s2,
                getTooltipItems: (touched) => touched.map((s) {
                  final p = points[s.x.round().clamp(0, points.length - 1)];
                  return LineTooltipItem(
                    '${p.asOf}\n${widget.currency} ${p.price.toStringAsFixed(4)}',
                    TextStyle(
                      color: c.text,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: visible,
                isCurved: true,
                curveSmoothness: 0.28,
                color: color,
                barWidth: 2.4,
                // Dots on a sparse series. NAV marks are quarterly, so six
                // points can be a fund's whole life and each one is a fact
                // somebody published rather than a sample off a curve.
                dotData: FlDotData(show: points.length <= 8),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.25),
                      color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
          duration: Duration.zero,
        );
      },
    );
  }
}

/// The leading [t] fraction of [spots], with an interpolated tip so the line
/// grows smoothly left to right rather than jumping point to point.
///
/// Duplicated from rate_chart.dart rather than shared. Extracting one series
/// chart that both files use is the right end state and a mechanical change
/// with no visible result, so it is a follow-up rather than something done in
/// the same edit that introduces a whole new basis to the page.
List<FlSpot> _reveal(List<FlSpot> spots, double t) {
  final n = spots.length;
  if (n < 2 || t >= 1) return spots;
  if (t <= 0) return [spots.first, spots.first];
  final k = t * (n - 1);
  final whole = k.floor();
  final out = spots.sublist(0, whole + 1);
  if (whole < n - 1) {
    final f = k - whole;
    final a = spots[whole], b = spots[whole + 1];
    out.add(FlSpot(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f));
  }
  return out;
}

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _mon(int m) => (m >= 1 && m <= 12) ? _monthAbbr[m - 1] : '';

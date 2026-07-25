import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_loader.dart';
import '../../../core/widgets/range_bar.dart';
import '../../../data/models/stock_history.dart';
import '../../../data/providers.dart';

/// The stock price chart. A deliberate mirror of [RateChart], down to the
/// auto-range behaviour and the RangeBar beneath, so a stock reads as the same
/// kind of object as a fund.
///
/// It differs in exactly one honest way: a fund's line is a RATE and a stock's
/// line is a PRICE in shillings, so the right-edge axis carries KES values and
/// the tooltip does not append a percent sign to a number that is not one.
///
/// ── ON THE AUTO RANGE ──────────────────────────────────────────────────────
/// This matters more for stocks than it ever did for funds. Price history began
/// accumulating the day the NSE scraper first ran, so for the first weeks of a
/// stock's life in Fructa there is no 6M or 1Y line to draw. Defaulting to 1Y
/// would open every stock on "Not enough data" while a perfectly good two week
/// line sat one tap away. So: open on the SMALLEST range that holds at least
/// two points, and let a user tap override from then on. The chart shows what
/// it has, and says so plainly when it has nothing.
class StockChart extends ConsumerStatefulWidget {
  const StockChart(this.stockId, {super.key, this.color});

  final String stockId;
  final Color? color;

  @override
  ConsumerState<StockChart> createState() => _StockChartState();
}

class _StockChartState extends ConsumerState<StockChart> {
  ChartRange _range = ChartRange.w1;
  bool _userPicked = false;

  List<StockHistory> _inRange(List<StockHistory> all, ChartRange r) {
    if (all.isEmpty) return all;
    final last = DateTime.parse(all.last.asOf);
    final cutoff = last.subtract(Duration(days: r.days));
    return all.where((p) => !DateTime.parse(p.asOf).isBefore(cutoff)).toList();
  }

  ChartRange _autoRange(List<StockHistory> all) {
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
    final async = ref.watch(stockHistoryProvider(widget.stockId));

    return async.when(
      loading: () => SizedBox(
        height: 180,
        child: Center(child: AppLoader(color: line)),
      ),
      // A failed fetch shows nothing rather than an empty axis. An axis with no
      // line on it reads as "this share is worth nothing", which is a lie.
      error: (e, _) => SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Couldn\u2019t load price history.',
            style: TextStyle(color: c.muted),
          ),
        ),
      ),
      data: (all) {
        final sorted = [...all]..sort((a, b) => a.asOf.compareTo(b.asOf));
        final effective = _userPicked ? _range : _autoRange(sorted);
        final points = _inRange(sorted, effective);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 180,
              child: points.length < 2
                  ? Center(
                      child: Text(
                        sorted.length < 2
                            ? 'No price history yet.'
                            : 'Not enough data for ${effective.label}.',
                        style: TextStyle(color: c.muted),
                      ),
                    )
                  : _Chart(points, line),
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

class _Chart extends StatelessWidget {
  const _Chart(this.points, this.color);
  final List<StockHistory> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].closeKes),
    ];
    final px = points.map((p) => p.closeKes);
    final lo = px.reduce((a, b) => a < b ? a : b);
    final hi = px.reduce((a, b) => a > b ? a : b);

    // Padding is proportional, not a fixed band. A fund rate lives in a narrow
    // 0-30 window, so RateChart could clamp to 0.15-5.0 points. Prices do not:
    // MSC trades at 0.28 and KURV at 1,355. A fixed pad would flatten one and
    // explode the other.
    final span = hi - lo;
    final pad = span > 0 ? span * 0.25 : (hi.abs() * 0.05).clamp(0.01, 50.0);

    final labelStyle = TextStyle(
      color: c.faint,
      fontSize: 10,
      fontFamily: fructaFonts.mono,
    );

    final minY = (lo - pad).clamp(0.0, double.infinity);
    final maxY = hi + pad;
    final yStep = ((maxY - minY) / 4).clamp(0.001, double.infinity);
    final n = points.length;
    final xStep = ((n - 1) / 3).clamp(1.0, (n - 1).toDouble());

    // Sub-shilling counters need two decimals to say anything at all (MSC moves
    // between 0.28 and 0.31). A 1,355 shilling counter does not.
    final dp = maxY < 10 ? 2 : (maxY < 100 ? 1 : 0);

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
          getDrawingHorizontalLine: (_) => FlLine(color: c.line, strokeWidth: 1),
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
              reservedSize: 46,
              getTitlesWidget: (value, meta) {
                if (value <= minY || value >= maxY) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    value.toStringAsFixed(dp),
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
                    '${_mon(d.month)} ${d.day}',
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
                '${p.asOf}\n${p.closeKes.toStringAsFixed(2)} KES',
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
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.28,
            color: color,
            barWidth: 2.4,
            // Dots when the series is short. Right now every stock's history is
            // short, so this is what stops two weeks of data from pretending to
            // be a smooth year-long trend.
            dotData: FlDotData(show: points.length <= 6),
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
    );
  }
}

const _monthAbbr = [
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

String _mon(int m) => (m >= 1 && m <= 12) ? _monthAbbr[m - 1] : '';

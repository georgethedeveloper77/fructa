import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/range_bar.dart';
import '../../../data/models/rate_history.dart';
import '../../../data/providers.dart';

/// v5 `.co-chart` + `.rangebar`. A full-bleed 180px line in the fund's brand
/// [color] (falls back to accent), with faint min/max labels at the right edge
/// and the shared [RangeBar] beneath. Range is owned here; the page just drops
/// in `RateChart(fundId, color: tint)`.
///
/// Until the user picks a range, the chart auto-selects the SMALLEST range
/// that contains at least 2 points  with sparse history (e.g. monthly marks)
/// a fixed 1W default would open on "Not enough data" even though a perfectly
/// good 3M line exists. A user tap always wins from then on.
class RateChart extends ConsumerStatefulWidget {
  const RateChart(this.fundId, {super.key, this.color});

  final String fundId;
  final Color? color;

  @override
  ConsumerState<RateChart> createState() => _RateChartState();
}

class _RateChartState extends ConsumerState<RateChart> {
  ChartRange _range = ChartRange.w1;
  bool _userPicked = false;

  List<RateHistory> _inRange(List<RateHistory> all, ChartRange r) {
    if (all.isEmpty) return all;
    final last = DateTime.parse(all.last.asOf);
    final cutoff = last.subtract(Duration(days: r.days));
    return all.where((p) => !DateTime.parse(p.asOf).isBefore(cutoff)).toList();
  }

  /// Smallest range (by day span) whose window holds >=2 points; falls back
  /// to the widest range when even that can't produce a line.
  ChartRange _autoRange(List<RateHistory> all) {
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
    final async = ref.watch(historyProvider(widget.fundId));

    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator(color: line)),
          ),
          RangeBar(
            value: _range,
            onChanged: (r) => setState(() {
              _range = r;
              _userPicked = true;
            }),
          ),
        ],
      ),
      error: (e, _) => SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Couldn\u2019t load history.',
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
                            ? 'No rate history yet.'
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
  final List<RateHistory> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].rate),
    ];
    final rates = points.map((p) => p.rate);
    final lo = rates.reduce((a, b) => a < b ? a : b);
    final hi = rates.reduce((a, b) => a > b ? a : b);
    final pad = ((hi - lo) * 0.25).clamp(0.15, 5.0);

    final labelStyle = TextStyle(
      color: c.faint,
      fontSize: 10,
      fontFamily: fructaFonts.mono,
    );

    // Minimal v5 aesthetic: no axes, no grid, no border  just the brand line
    // and gradient fill, with min/max pinned to the right edge.
    final minY = (lo - pad).clamp(0.0, double.infinity);
    final maxY = hi + pad;
    // ~5 horizontal rules across the padded range  the "rows" of the grid.
    final yStep = ((maxY - minY) / 4).clamp(0.01, double.infinity);
    // ~4 date ticks along the bottom  the "columns". Spread across the window
    // so a dense series doesn't crowd the axis.
    final n = points.length;
    final xStep = ((n - 1) / 3).clamp(1.0, (n - 1).toDouble());

    // Gridded v5 aesthetic: faint horizontal rules, a right-edge rate axis
    // (promoted from the old pinned min/max), and a bottom date axis  the
    // Stocks-style frame, verticals intentionally omitted to stay calm.
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
          getDrawingHorizontalLine: (_) => FlLine(
            color: c.line,
            strokeWidth: 1,
          ),
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
              reservedSize: 44,
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
                  child: Text('${_mon(d.month)} \u2019${d.year % 100}', style: labelStyle),
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
                '${p.asOf}\n${p.rate.toStringAsFixed(2)}%',
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

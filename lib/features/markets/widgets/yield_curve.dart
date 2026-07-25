import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/snapshot_providers.dart';
import 'market_yield_curve_page.dart';

const _curveLabels = ['91d', '182d', '364d'];

/// The 3-point T-bill curve chart, shared by the inline widget and the detail
/// page so the two cannot drift. Reads the published benchmarks
/// (`benchmark.tbill_91/182/364`), which carry baked fallbacks, so it always
/// renders.
class YieldCurveChart extends ConsumerWidget {
  const YieldCurveChart({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final pts = [cfg.tbill91Pct, cfg.tbill182Pct, cfg.tbill364Pct];
    final lo = pts.reduce((a, b) => a < b ? a : b);
    final hi = pts.reduce((a, b) => a > b ? a : b);
    final pad = ((hi - lo) * 0.6).clamp(0.15, 3.0);

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: -0.15,
          maxX: 2.15,
          minY: (lo - pad).clamp(0, double.infinity),
          maxY: hi + pad,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i > 2) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _curveLabels[i],
                      style: TextStyle(
                        color: c.faint,
                        fontFamily: fructaFonts.mono,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < pts.length; i++)
                  FlSpot(i.toDouble(), pts[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              color: c.accent,
              barWidth: 2.4,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                  radius: 4,
                  color: c.bg,
                  strokeWidth: 2,
                  strokeColor: c.accent,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.accent.withValues(alpha: 0.20),
                    c.accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Government yield curve at the foot of Markets: the 91/182/364-day T-bill as a
/// 3-point line. Government context, not a fund rate the user is hunting for.
/// Tap to open the detail page.
class YieldCurve extends ConsumerWidget {
  const YieldCurve({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final pts = [cfg.tbill91Pct, cfg.tbill182Pct, cfg.tbill364Pct];
    final asOf = cfg.benchmark('benchmark.tbill_91')?.asOf;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MarketYieldCurvePage()),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'GOVERNMENT YIELD CURVE',
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  'Detail',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right, color: c.accent, size: 16),
              ],
            ),
            const SizedBox(height: 16),
            const YieldCurveChart(height: 120),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < pts.length; i++)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _curveLabels[i],
                          style: TextStyle(
                            color: c.faint,
                            fontSize: 9.5,
                            fontFamily: fructaFonts.mono,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${pts[i].toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: c.accent,
                            fontFamily: fructaFonts.mono,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (asOf != null) ...[
              const SizedBox(height: 8),
              Text(
                'Last auction $asOf \u00b7 source: CBK',
                style: TextStyle(color: c.faint, fontSize: 9.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

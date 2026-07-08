import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/series_colors.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/providers.dart';
import '../../../data/snapshot_providers.dart';

/// "Are MMFs beating inflation?" (v6 `.card`)  external eyebrow over a panel
/// card. Three lines over the trailing window: the average retail MMF (from
/// each fund's spark), the 91-day T-bill, and inflation (a flat threshold). A
/// verdict chip states the gap on the honest net comparator; a benchmark row
/// (inflation / CBR / 91-day) anchors the numbers.
///
/// Parked at the foot of Markets: rates first, context second. Hidden when
/// there's no MMF spark to average  never a fabricated trend.
class MarketContextCard extends ConsumerWidget {
  const MarketContextCard({super.key});

  static List<double> _resample(List<double> src, int n) {
    if (src.length == n) return src;
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final idx = (i * (src.length - 1) / (n - 1)).round();
      out.add(src[idx.clamp(0, src.length - 1)]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final funds = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final cfg = ref.watch(remoteConfigProvider);
    final wht = cfg.whtPct;
    final inflation = cfg.inflationPct;

    final mmf = funds
        .where(
          (f) =>
              f.retail &&
              f.fundType == 'mmf' &&
              f.currency == 'KES' &&
              f.currentRate != null &&
              f.spark.length >= 2,
        )
        .toList();
    if (mmf.isEmpty) return const SizedBox.shrink();

    // Index-aligned average over the overlapping tail (cap 12 points).
    final n = mmf
        .map((f) => f.spark.length)
        .reduce((a, b) => a < b ? a : b)
        .clamp(2, 12)
        .toInt();
    final mmfAvg = <double>[];
    for (var i = 0; i < n; i++) {
      var s = 0.0;
      for (final f in mmf) {
        s += f.spark[f.spark.length - n + i];
      }
      mmfAvg.add(s / mmf.length);
    }

    final tb = funds
        .where((f) => f.category == 'tbill' && f.name.contains('91'))
        .toList();
    final tbill = tb.isNotEmpty && tb.first.spark.length >= 2
        ? _resample(tb.first.spark, n)
        : List<double>.filled(n, cfg.tbill91Pct);
    final infl = List<double>.filled(n, inflation);

    // netRate is nullable on the model; the filter guarantees a rate, but
    // whereType keeps the analyzer honest either way.
    final nets = mmf.map((f) => f.netRate(wht)).whereType<double>().toList();
    if (nets.isEmpty) return const SizedBox.shrink();
    final avgNet = nets.reduce((a, b) => a + b) / nets.length;
    final diff = avgNet - inflation;
    final beating = diff >= 0;
    final verdict =
        '${beating ? 'Yes' : 'No'} \u00b7 ${diff >= 0 ? '+' : '\u2212'}${diff.abs().toStringAsFixed(1)}pp avg';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MARKET CONTEXT',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
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
                  children: [
                    Expanded(
                      child: Text(
                        'Are MMFs beating inflation?',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.deltaSoft(diff),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        verdict,
                        style: TextStyle(
                          color: c.delta(diff),
                          fontFamily: fructaFonts.mono,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Average retail MMF net yield vs the 91-day T-bill and '
                  'headline inflation, last $n marks.',
                  style: TextStyle(color: c.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: _MultiLine(
                    mmfAvg: mmfAvg,
                    tbill: tbill,
                    inflation: infl,
                    mmfColor: seriesColor(0),
                    tbColor: seriesColor(1),
                    inflColor: c.down,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Legend(color: seriesColor(0), label: 'MMF avg'),
                    const SizedBox(width: 14),
                    _Legend(color: seriesColor(1), label: 'T-bill 91d'),
                    const SizedBox(width: 14),
                    _Legend(color: c.down, label: 'Inflation'),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: c.line),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Bench(label: 'INFLATION', value: cfg.inflationPct),
                    _Div(),
                    _Bench(label: 'CBR', value: cfg.cbrPct),
                    _Div(),
                    _Bench(
                      label: '91-DAY',
                      value: cfg.tbill91Pct,
                      accent: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Div extends StatelessWidget {
  const _Div();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: context.c.line,
  );
}

class _Bench extends StatelessWidget {
  const _Bench({required this.label, required this.value, this.accent = false});
  final String label;
  final double value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
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
            '${value.toStringAsFixed(2)}%',
            style: TextStyle(
              color: accent ? c.accent : c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: c.muted,
            fontFamily: fructaFonts.mono,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _MultiLine extends StatelessWidget {
  const _MultiLine({
    required this.mmfAvg,
    required this.tbill,
    required this.inflation,
    required this.mmfColor,
    required this.tbColor,
    required this.inflColor,
  });
  final List<double> mmfAvg, tbill, inflation;
  final Color mmfColor, tbColor, inflColor;

  @override
  Widget build(BuildContext context) {
    final all = [...mmfAvg, ...tbill, ...inflation];
    final lo = all.reduce((a, b) => a < b ? a : b);
    final hi = all.reduce((a, b) => a > b ? a : b);
    final pad = ((hi - lo) * 0.25).clamp(0.3, 5.0);

    List<FlSpot> spots(List<double> s) => [
      for (var i = 0; i < s.length; i++) FlSpot(i.toDouble(), s[i]),
    ];
    LineChartBarData bar(List<double> s, Color col) => LineChartBarData(
      spots: spots(s),
      isCurved: true,
      curveSmoothness: 0.28,
      color: col,
      barWidth: 2.2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (mmfAvg.length - 1).toDouble(),
        minY: (lo - pad).clamp(0, double.infinity),
        maxY: hi + pad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          bar(inflation, inflColor),
          bar(tbill, tbColor),
          bar(mmfAvg, mmfColor),
        ],
      ),
    );
  }
}

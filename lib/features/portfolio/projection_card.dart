import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../engine/projection_engine.dart';

/// v5 `.projwrap`  flat "If you keep investing" block: mono projected value,
/// a growth line, a real forward curve (ProjectionEngine.series) and two
/// sliders that inherit the global v5 slider theme. The disclaimer lives at
/// the portfolio level, not here.
class ProjectionCard extends StatefulWidget {
  const ProjectionCard({
    super.key,
    required this.principal,
    required this.grossRate,
    this.currency = 'KES',
  });

  final double principal; // current net worth (consolidated)
  final double grossRate; // blended gross annual yield (%)
  final String currency;

  @override
  State<ProjectionCard> createState() => _ProjectionCardState();
}

class _ProjectionCardState extends State<ProjectionCard> {
  double _topUp = 25000;
  int _horizon = 12;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final projected = ProjectionEngine.project(
      widget.principal,
      widget.grossRate,
      _horizon,
      monthlyTopUp: _topUp,
      net: true,
    );
    final growth = projected - widget.principal;
    final series = ProjectionEngine.series(
      widget.principal,
      widget.grossRate,
      _horizon,
      monthlyTopUp: _topUp,
      net: true,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            money(widget.currency, projected),
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.arrow_drop_up, size: 18, color: c.up),
              Flexible(
                child: Text(
                  '${money(widget.currency, growth < 0 ? 0 : growth)} growth \u00b7 in $_horizon months',
                  style: TextStyle(
                    color: c.up,
                    fontFamily: fructaFonts.mono,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(height: 90, child: _MiniChart(series)),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Monthly top-up',
            value: money(widget.currency, _topUp),
            slider: Slider(
              value: _topUp,
              min: 0,
              max: 100000,
              divisions: 20,
              onChanged: (v) => setState(() => _topUp = v),
            ),
          ),
          _SliderRow(
            label: 'Horizon',
            value: '$_horizon months',
            slider: Slider(
              value: _horizon.toDouble(),
              min: 6,
              max: 60,
              divisions: 9,
              onChanged: (v) => setState(() => _horizon = v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

/// v5 `.srlbl`  label / mono value over a themed slider.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
  });
  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
            Text(
              value,
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 34, child: slider),
      ],
    );
  }
}

class _MiniChart extends StatelessWidget {
  const _MiniChart(this.series);
  final List<double> series;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (series.length < 2) return const SizedBox.shrink();
    final lo = series.reduce((a, b) => a < b ? a : b);
    final hi = series.reduce((a, b) => a > b ? a : b);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (series.length - 1).toDouble(),
        minY: lo,
        maxY: hi + (hi - lo) * 0.05,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < series.length; i++)
                FlSpot(i.toDouble(), series[i]),
            ],
            isCurved: true,
            color: c.accent,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  c.accent.withValues(alpha: 0.18),
                  c.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

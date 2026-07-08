import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/models/rate_history.dart';
import '../../data/providers.dart';

const _lineColors = [
  Color(0xFFE0B34C), // gold
  Color(0xFF6AA6F0), // blue
  Color(0xFF4FD0B5), // teal
  Color(0xFFA99BF5), // purple
];
const _maxFunds = 4;

class ComparePage extends ConsumerStatefulWidget {
  const ComparePage({super.key});
  @override
  ConsumerState<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends ConsumerState<ComparePage> {
  final List<String> _selected = [];

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < _maxFunds) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final funds = ([...(ref.watch(ratesProvider).valueOrNull ?? const <Fund>[])]
      ..sort((a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0)));
    final byId = ref.watch(fundsByIdProvider);

    // pull history for each selected fund (lazy, cached per id)
    final histories = <String, List<RateHistory>>{};
    for (final id in _selected) {
      final data = ref.watch(historyProvider(id)).valueOrNull;
      if (data != null) histories[id] = data;
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Text(
                'Compare',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Overlay rate history · pick up to 4',
                style: TextStyle(color: AppColors.faint, fontSize: 13),
              ),
            ),

            // fund chips
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: funds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final f = funds[i];
                  final idx = _selected.indexOf(f.id);
                  final active = idx >= 0;
                  final color = active
                      ? _lineColors[idx % _lineColors.length]
                      : AppColors.line;
                  return GestureDetector(
                    onTap: () => _toggle(f.id),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active
                            ? color.withOpacity(0.12)
                            : AppColors.panel,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color),
                      ),
                      child: Text(
                        f.name.split(' ').first,
                        style: TextStyle(
                          color: active ? color : AppColors.mute,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            _Card(
              child: SizedBox(
                height: 190,
                child: _Overlay(selected: _selected, histories: histories),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Center(
                child: Text(
                  'Gross effective annual yield · last 12 months',
                  style: TextStyle(color: AppColors.faint, fontSize: 11),
                ),
              ),
            ),

            if (_selected.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 16, 22, 4),
                child: Text(
                  'NET YIELD AFTER 15% TAX',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 12,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ..._selected.asMap().entries.map((e) {
                final f = byId[e.value];
                final color = _lineColors[e.key % _lineColors.length];
                final gross = f?.currentRate;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f?.name ?? e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (gross != null) ...[
                        Text(
                          '${gross.toStringAsFixed(2)}%',
                          style: const TextStyle(
                            color: AppColors.faint,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${(gross * 0.85).toStringAsFixed(2)}%',
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else
                        const Text(
                          '',
                          style: TextStyle(color: AppColors.faint),
                        ),
                    ],
                  ),
                );
              }),
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 6, 22, 8),
                child: Text(
                  'Tap a fund to add or remove it. Net strips the 15% withholding tax.',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    'Pick funds above to compare their yields.',
                    style: TextStyle(color: AppColors.mute),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final List<String> selected;
  final Map<String, List<RateHistory>> histories;
  const _Overlay({required this.selected, required this.histories});

  @override
  Widget build(BuildContext context) {
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final perFund = <String, List<RateHistory>>{};
    for (final id in selected) {
      final pts =
          (histories[id] ?? const <RateHistory>[])
              .where((p) => !DateTime.parse(p.asOf).isBefore(cutoff))
              .toList()
            ..sort((a, b) => a.asOf.compareTo(b.asOf));
      if (pts.length >= 2) perFund[id] = pts;
    }

    if (perFund.isEmpty) {
      return const Center(
        child: Text(
          'History builds as rates update.\nCompare net yields below.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mute, fontSize: 13),
        ),
      );
    }

    DateTime? minD, maxD;
    for (final pts in perFund.values) {
      for (final p in pts) {
        final d = DateTime.parse(p.asOf);
        if (minD == null || d.isBefore(minD!)) minD = d;
        if (maxD == null || d.isAfter(maxD!)) maxD = d;
      }
    }
    double? lo, hi;
    final bars = <LineChartBarData>[];
    perFund.forEach((id, pts) {
      final color = _lineColors[selected.indexOf(id) % _lineColors.length];
      final spots = pts.map((p) {
        final x = DateTime.parse(p.asOf).difference(minD!).inDays.toDouble();
        lo = lo == null ? p.rate : (p.rate < lo! ? p.rate : lo);
        hi = hi == null ? p.rate : (p.rate > hi! ? p.rate : hi);
        return FlSpot(x, p.rate);
      }).toList();
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      );
    });

    final pad = ((hi! - lo!) * 0.2).clamp(0.3, 5.0);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxD!.difference(minD!).inDays.toDouble(),
        minY: (lo! - pad).clamp(0.0, double.infinity),
        maxY: hi! + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}%',
                style: const TextStyle(color: AppColors.faint, fontSize: 10),
              ),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: bars,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.line),
    ),
    child: child,
  );
}

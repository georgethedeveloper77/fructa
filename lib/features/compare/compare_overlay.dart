import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/series_colors.dart';
import '../../core/theme.dart';
import '../../core/widgets/range_bar.dart';
import '../../data/models/fund.dart';
import '../../data/models/rate_history.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import 'compare_controller.dart';

/// Net-of-tax yield for the comparison matrix.
///
/// Takes the rate rather than assuming it. The old top-level version deducted
/// 15% from every fund that was not flagged tax-free, so a fund quoting a rate
/// already net of tax lost another 15% in the one view whose entire purpose is
/// putting funds side by side, and lost a comparison it should have won.
///
/// Fund.netRate does the deciding: it reads net_of and tax_free and returns the
/// rate untouched when there is nothing left to take.
double _net(Fund f, double whtPct) => f.netRate(whtPct) ?? 0;

class CompareOverlay extends ConsumerStatefulWidget {
  const CompareOverlay(this.fundIds, {super.key});
  final List<String> fundIds;

  @override
  ConsumerState<CompareOverlay> createState() => _CompareOverlayState();
}

class _CompareOverlayState extends ConsumerState<CompareOverlay> {
  ChartRange _range = ChartRange.y1; // preserves the previous 12-month view

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final fundIds = widget.fundIds;
    final c = context.c;
    final byId = ref.watch(fundsByIdProvider);
    final whtPct = ref.watch(remoteConfigProvider).whtPct;
    final funds =
        fundIds.map((id) => byId[id]).whereType<Fund>().toList();

    final histories = <String, List<RateHistory>>{};
    for (final id in fundIds) {
      final h = ref.watch(historyProvider(id)).value;
      if (h != null) histories[id] = h;
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        title: Text(t('compare.overlayTitle')),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await ref
                  .read(savedComparisonsProvider.notifier)
                  .save(fundIds);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                    SnackBar(content: Text(t('compare.saveDone'))));
            },
            icon: Icon(Icons.star_border, color: c.accent),
            label: Text(t('compare.saveSet'),
                style: TextStyle(color: c.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 200,
            child: _Overlay(
              fundIds: fundIds,
              histories: histories,
              range: _range,
            ),
          ),
          RangeBar(
            value: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(t('compare.chartCaption'),
                style: TextStyle(color: c.faint, fontSize: 11)),
          ),
          const SizedBox(height: 16),
          _Matrix(funds: funds, whtPct: whtPct),
        ],
      ),
    );
  }
}

// ── Winner-highlighted matrix ──────────────────────────────────────────────
class _Matrix extends StatelessWidget {
  const _Matrix({required this.funds, required this.whtPct});
  final List<Fund> funds;
  final double whtPct;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // winner id per metric (null = lower-is-better handled inline)
    String? maxBy(double Function(Fund) v) {
      Fund? best;
      for (final f in funds) {
        if (f.currentRate == null) continue;
        if (best == null || v(f) > v(best)) best = f;
      }
      return best?.id;
    }

    String? minBy(num? Function(Fund) v) {
      Fund? best;
      for (final f in funds) {
        final x = v(f);
        if (x == null) continue;
        if (best == null || x < (v(best) ?? double.infinity)) best = f;
      }
      return best?.id;
    }

    final grossWin = maxBy((f) => f.currentRate ?? 0);
    final netWin = maxBy((f) => _net(f, whtPct));
    final minWin = minBy((f) => f.minInvest);
    final feeWin = minBy((f) => f.mgmtFee);

    Widget row(String label, String Function(Fund) cell, String? winId,
        {bool divider = true}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border:
              divider ? Border(bottom: BorderSide(color: c.line)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(label,
                  style: TextStyle(color: c.faint, fontSize: 12)),
            ),
            for (final f in funds)
              Expanded(
                child: Text(
                  cell(f),
                  style: TextStyle(
                    color: f.id == winId ? c.up : c.text,
                    fontSize: 13,
                    fontWeight:
                        f.id == winId ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header: fund short names with series dots
          Row(
            children: [
              const SizedBox(width: 84),
              for (var i = 0; i < funds.length; i++)
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                            color: seriesColor(i),
                            shape: BoxShape.circle),
                      ),
                      Expanded(
                        child: Text(funds[i].name.split(' ').first,
                            style: TextStyle(
                                color: c.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Divider(color: c.line, height: 20),
          row(t('compare.gross'),
              (f) => f.currentRate != null
                  ? '${f.currentRate!.toStringAsFixed(2)}%'
                  : t('common.dash'),
              grossWin),
          row(t('compare.net'),
              (f) => f.currentRate != null
                  ? '${_net(f, whtPct).toStringAsFixed(2)}%'
                  : t('common.dash'),
              netWin),
          row(t('compare.minimum'),
              (f) => f.minInvest != null
                  ? withCommas(f.minInvest!)
                  : t('common.dash'),
              minWin),
          row(t('compare.fee'),
              (f) => f.mgmtFee != null
                  ? '${f.mgmtFee!.toStringAsFixed(2)}%'
                  : t('common.dash'),
              feeWin,
              divider: false),
        ],
      ),
    );
  }
}

// ── Multi-line overlay chart (last 12 months) ──────────────────────────────
class _Overlay extends StatelessWidget {
  const _Overlay(
      {required this.fundIds, required this.histories, required this.range});
  final List<String> fundIds;
  final Map<String, List<RateHistory>> histories;
  final ChartRange range;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cutoff = DateTime.now().subtract(Duration(days: range.days));
    final perFund = <String, List<RateHistory>>{};
    for (final id in fundIds) {
      final pts = (histories[id] ?? const <RateHistory>[])
          .where((p) => !DateTime.parse(p.asOf).isBefore(cutoff))
          .toList()
        ..sort((a, b) => a.asOf.compareTo(b.asOf));
      if (pts.length >= 2) perFund[id] = pts;
    }

    if (perFund.isEmpty) {
      return Center(
        child: Text(t('compare.buildingHistory'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 13)),
      );
    }

    DateTime? minD, maxD;
    for (final pts in perFund.values) {
      for (final p in pts) {
        final d = DateTime.parse(p.asOf);
        if (minD == null || d.isBefore(minD)) minD = d;
        if (maxD == null || d.isAfter(maxD)) maxD = d;
      }
    }

    double? lo, hi;
    final bars = <LineChartBarData>[];
    perFund.forEach((id, pts) {
      final color = seriesColor(fundIds.indexOf(id));
      final spots = pts.map((p) {
        final x = DateTime.parse(p.asOf).difference(minD!).inDays.toDouble();
        lo = lo == null ? p.rate : (p.rate < lo! ? p.rate : lo);
        hi = hi == null ? p.rate : (p.rate > hi! ? p.rate : hi);
        return FlSpot(x, p.rate);
      }).toList();
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
      ));
    });

    final pad = ((hi! - lo!) * 0.2).clamp(0.3, 5.0);
    return LineChart(LineChartData(
      minX: 0,
      maxX: maxD!.difference(minD!).inDays.toDouble(),
      minY: (lo! - pad).clamp(0.0, double.infinity),
      maxY: hi! + pad,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: c.line, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}%',
                style: TextStyle(color: c.faint, fontSize: 10)),
          ),
        ),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: bars,
    ));
  }
}

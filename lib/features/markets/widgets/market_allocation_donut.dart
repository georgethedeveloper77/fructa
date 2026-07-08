import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/providers.dart';
import '../../../data/snapshot_providers.dart';

/// "Market by AUM" donut  the authoritative CIS market split by fund type,
/// sourced from the CMA quarterly report via remote config
/// (`market.aum_by_fund_type`) with a baked Q1-2026 fallback, so it always
/// renders.
///
/// This is the *market* (by assets), not the funds fructa happens to track. A
/// count ring made Money Market read as ~95% because most tracked funds are
/// MMFs; by AUM the market is ~52% MMF. SACCOs are a separate (SASRA) market
/// and are intentionally absent from this CIS pie  a coverage line notes how
/// many retail funds the app tracks instead.
const _labels = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

/// Slice colour  the central fund-type palette (MMF gold, FI sky, Equity iris,
/// Balanced ember, Special emerald). No raw hex in the widget.
Color _typeColor(String k) => fundTypeColors[k] ?? const Color(0xFF9AA2B2);

/// Compact KES: 442.2B → "442B", 4.75B → "4.8B", 2.2B → "2.2B".
String _compactKes(double v) {
  if (v >= 1e9) {
    final b = v / 1e9;
    return '${b >= 10 ? b.round() : b.toStringAsFixed(1)}B';
  }
  if (v >= 1e6) return '${(v / 1e6).round()}M';
  return v.round().toString();
}

/// "2026-03-31" → "Q1 '26"; anything unparseable passes through.
String _asOfTag(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  final year = m.group(1)!.substring(2);
  final q = ((int.parse(m.group(2)!) - 1) ~/ 3) + 1;
  return "Q$q '$year";
}

class MarketAllocationDonut extends ConsumerStatefulWidget {
  const MarketAllocationDonut({super.key});

  @override
  ConsumerState<MarketAllocationDonut> createState() =>
      _MarketAllocationDonutState();
}

class _MarketAllocationDonutState extends ConsumerState<MarketAllocationDonut> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);

    final split = cfg.marketFundTypes();
    if (split.isEmpty) return const SizedBox.shrink();

    final totalAum = split.fold<double>(0, (a, b) => a + b.aumKes);
    final tag = cfg.marketAsOf != null ? _asOfTag(cfg.marketAsOf!) : null;

    // Coverage line  how many retail funds the app tracks. Context beneath the
    // pie, not a slice of it.
    final funds = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final tracked = funds.where((f) => f.retail).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MARKET BY AUM',
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'CMA${tag != null ? ' \u00b7 $tag' : ''}',
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          startDegreeOffset: -90,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, resp) {
                              if (!event.isInterestedForInteractions ||
                                  resp?.touchedSection == null) {
                                setState(() => _touched = -1);
                                return;
                              }
                              setState(
                                () => _touched =
                                    resp!.touchedSection!.touchedSectionIndex,
                              );
                            },
                          ),
                          sections: [
                            for (var i = 0; i < split.length; i++)
                              PieChartSectionData(
                                value: split[i].share,
                                color: _typeColor(split[i].type),
                                radius: i == _touched ? 22 : 18,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _compactKes(totalAum),
                            style: TextStyle(
                              color: c.text,
                              fontFamily: fructaFonts.mono,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'KES AUM',
                            style: TextStyle(
                              color: c.faint,
                              fontSize: 8.5,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < split.length; i++)
                        _LegendRow(
                          label: _labels[split[i].type] ?? split[i].type,
                          color: _typeColor(split[i].type),
                          share: split[i].share,
                          aum: split[i].aumKes,
                          highlight: i == _touched,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tracked > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Tracking $tracked retail ${tracked == 1 ? 'fund' : 'funds'}',
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.color,
    required this.share,
    required this.aum,
    required this.highlight,
  });
  final String label;
  final Color color;
  final double share;
  final double aum;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight ? c.text : c.muted,
                fontSize: 12.5,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${share.toStringAsFixed(share < 10 ? 1 : 0)}%',
            style: TextStyle(
              color: highlight ? c.text : c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _compactKes(aum),
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund_composition.dart';

/// "What the fund holds"  a donut of the fund's asset-class split with a
/// legend, plus a provenance line (source + as-of quarter). The caller hides
/// it when there's no composition (compositionProvider returns null), so it
/// never shows an empty or fabricated split.
///
/// Data is quarterly from the CMA CIS report; the centre shows total AUM.
/// Ported to the [FundComposition]/[AssetClass] model (the API that shipped
/// the original was written against a draft `Composition` that never landed).
class CompositionPie extends StatefulWidget {
  const CompositionPie(this.composition, {super.key});
  final FundComposition composition;

  @override
  State<CompositionPie> createState() => _CompositionPieState();
}

class _CompositionPieState extends State<CompositionPie> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final comp = widget.composition;
    if (comp.isEmpty) return const SizedBox.shrink();
    final slices = comp.sorted; // List<MapEntry<AssetClass, double>>, desc

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT IT HOLDS',
            style: TextStyle(
              color: c.faint,
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // donut
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 42,
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
                          for (var i = 0; i < slices.length; i++)
                            PieChartSectionData(
                              value: slices[i].value,
                              color: slices[i].key.color,
                              radius: i == _touched ? 26 : 22,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'AUM',
                          style: TextStyle(
                            color: c.faint,
                            fontSize: 9,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          FundComposition.kesShort(comp.total),
                          style: TextStyle(
                            color: c.text,
                            fontFamily: fructaFonts.mono,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      _LegendRow(
                        cls: slices[i].key,
                        pct: comp.pct(slices[i].key),
                        highlight: i == _touched,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (comp.asOf != null) ...[
            const SizedBox(height: 14),
            Text(
              _provenance(comp.asOf!),
              style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  String _provenance(String asOf) {
    final d = DateTime.tryParse(asOf);
    final period = d != null ? 'Q${((d.month - 1) ~/ 3) + 1} ${d.year}' : asOf;
    return 'Portfolio as of $period \u00b7 source: CMA Collective Investment '
        'Schemes report. Figures are the fund\u2019s own quarterly filing.';
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.cls,
    required this.pct,
    required this.highlight,
  });
  final AssetClass cls;
  final double pct;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: cls.color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              cls.label,
              style: TextStyle(
                color: highlight ? c.text : c.muted,
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${pct.toStringAsFixed(pct < 10 ? 1 : 0)}%',
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

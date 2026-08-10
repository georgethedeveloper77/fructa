import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/quarter_stat.dart';
import '../../../data/models/fund.dart';
import '../../../data/models/remote_config.dart';
import '../../../data/providers.dart';
import '../../../data/snapshot_providers.dart';
import '../market_by_aum_page.dart';

/// "Kenya's fund market": how big the CIS market is, how fast it grew last
/// quarter, and how it splits by fund type. Sourced from the CMA quarterly
/// report via remote config (`market.cis_size` and `market.aum_by_fund_type`),
/// both with baked fallbacks so the card always renders.
///
/// This is the *market* (by assets), not the funds fructa happens to track. A
/// count ring made Money Market read as ~95% because most tracked funds are
/// MMFs; by AUM the market is ~52% MMF. SACCOs are a separate (SASRA) market
/// and are intentionally absent from this CIS pie, so a coverage line notes how
/// many retail funds the app tracks instead.
///
/// GROWTH IS SHOWN AT THE TOTAL ONLY, and that is not a layout compromise. The
/// per-asset-class quarter changes the CMA publishes are wild (listed
/// securities +452.6%, offshore -79.0%) because funds get reclassified between
/// buckets and new umbrella sub-funds start reporting, not because the market
/// moved that way. A green +452.6% chip on a slice reads as a return and it is
/// not one. The total nets all of that out and is safe to show.
///
/// Tapping opens [MarketByAumPage], which carries the interactive donut and the
/// asset-class view.
const _labels = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

/// Slice colour: the central fund-type palette (MMF gold, FI sky, Equity iris,
/// Balanced ember, Special emerald). No raw hex in the widget.
Color _typeColor(String k) => fundTypeColors[k] ?? const Color(0xFF9AA2B2);

/// Draw-on duration, matched to the rate and NAV charts.
const _drawOn = Duration(milliseconds: 900);

class MarketAllocationDonut extends ConsumerStatefulWidget {
  const MarketAllocationDonut({super.key});

  @override
  ConsumerState<MarketAllocationDonut> createState() =>
      _MarketAllocationDonutState();
}

class _MarketAllocationDonutState extends ConsumerState<MarketAllocationDonut> {
  /// Collapsed by default. The ring already carries the shape of the market;
  /// the legend below it is detail, and four of the five rows are detail about
  /// slices the reader can barely see. Money Market alone is over half the
  /// market, so the leading row plus the ring is the honest summary and the
  /// rest is opt-in.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);

    final split = cfg.marketFundTypes();
    if (split.isEmpty) return const SizedBox.shrink();

    final size = cfg.marketSize();
    final ringTotal = split.fold<double>(0, (a, b) => a + b.aumKes);
    final total = size?.totalKes ?? ringTotal;

    // The card is dated by the market size when we have it, since that is the
    // figure the headline numbers come from.
    final asOf = size?.asOf ?? cfg.marketAsOf;
    final source = size?.source ?? cfg.marketSource ?? 'CMA CIS Quarterly Report';

    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
    final tracked = funds.where((f) => f.retail).length;

    void open() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MarketByAumPage()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(c, asOf),
          const SizedBox(height: 12),
          InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _drawOn,
                curve: Curves.easeOutCubic,
                builder: (context, tt, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stats(c, size, total, tt),
                    const SizedBox(height: 4),
                    _ring(c, split, total, tt),
                    const SizedBox(height: 4),
                    _LegendRow(
                      label: _labels[split.first.type] ?? split.first.type,
                      color: _typeColor(split.first.type),
                      share: split.first.share,
                      aum: split.first.aumKes,
                      t: tt,
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _open
                          ? Column(
                              children: [
                                for (final s in split.skip(1))
                                  _LegendRow(
                                    label: _labels[s.type] ?? s.type,
                                    color: _typeColor(s.type),
                                    share: s.share,
                                    aum: s.aumKes,
                                    t: tt,
                                  ),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    if (split.length > 1) _toggle(c, split.length - 1),
                    if (size != null && size.addedKes != null) ...[
                      const SizedBox(height: 10),
                      Container(height: 1, color: c.line),
                      const SizedBox(height: 12),
                      _growthLine(c, size),
                    ],
                    const SizedBox(height: 12),
                    Container(height: 1, color: c.line),
                    const SizedBox(height: 11),
                    _sourceLine(c, source, asOf),
                  ],
                ),
              ),
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

  Widget _eyebrow(fructaColors c, String? asOf) {
    final tag = asOf != null ? monthTag(asOf) : null;
    return Row(
      children: [
        Text(
          "KENYA'S FUND MARKET",
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
          'CMA${tag != null && tag.isNotEmpty ? ' \u00b7 $tag' : ''}',
          style: TextStyle(
            color: c.faint,
            fontFamily: fructaFonts.mono,
            fontSize: 10.5,
          ),
        ),
        const Spacer(),
        Text(
          'Detail',
          style: TextStyle(
            color: c.accentInk,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Icon(Icons.chevron_right, size: 16, color: c.accentInk),
      ],
    );
  }

  /// Three cells: size, quarter move, scheme count. The AUM figure counts up
  /// with the ring so the two read as one gesture.
  Widget _stats(fructaColors c, MarketSize? size, double total, double t) {
    Widget cell(String value, String label, {Color? valueColor}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: c.faint, fontSize: 10, height: 1.35),
            ),
          ],
        ),
      ),
    );

    final change = size?.changePct;

    // No CrossAxisAlignment.stretch here. Inside a Row it has no bounded cross
    // extent and paints with null geometry unless an IntrinsicHeight sits
    // above it. Every cell carries one value line and one label line, so the
    // default alignment already leaves them level.
    return Row(
      children: [
        cell(compactKes(total * t), 'Total AUM, KES'),
        const SizedBox(width: 9),
        if (change != null) ...[
          cell(
            '${change >= 0 ? '+' : '-'}${change.abs().toStringAsFixed(1)}%',
            'This quarter',
            valueColor: c.delta(change),
          ),
          const SizedBox(width: 9),
        ],
        if (size?.schemeCount != null)
          cell('${size!.schemeCount}', 'Schemes')
        else
          cell(compactKes(total, digits: 0), 'Market size'),
      ],
    );
  }

  /// Full-width ring, sweeping from -90 degrees. The sweep is done by scaling
  /// every slice by [t] and padding the remainder with a transparent section,
  /// so the ring draws round rather than merely fading in.
  Widget _ring(
    fructaColors c,
    List<MarketFundType> split,
    double total,
    double t,
  ) {
    final swept = t.clamp(0.0, 1.0);
    final remainder = (1 - swept) * 100;

    return SizedBox(
      height: 212,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 66,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (final s in split)
                  PieChartSectionData(
                    value: s.share * swept,
                    color: _typeColor(s.type),
                    radius: 26,
                    showTitle: false,
                  ),
                if (remainder > 0.01)
                  PieChartSectionData(
                    value: remainder,
                    color: Colors.transparent,
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                compactKes(total * swept, digits: 0),
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'KES AUM',
                style: TextStyle(
                  color: c.faint,
                  fontSize: 9.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Expander for the remaining fund types.
  ///
  /// Its own InkWell so it swallows the tap rather than letting it reach the
  /// card, which navigates to the detail page. A reader opening the legend is
  /// not asking to leave the screen.
  Widget _toggle(fructaColors c, int hidden) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _open ? 'Show less' : 'Show $hidden more',
              style: TextStyle(
                color: c.accentInk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(Icons.expand_more, size: 17, color: c.accentInk),
            ),
          ],
        ),
      ),
    );
  }

  /// The quarter move in shillings. Percentages are abstract at this scale;
  /// ninety five billion of new money in three months is not.
  Widget _growthLine(fructaColors c, MarketSize size) {
    final added = size.addedKes!;
    final sign = added >= 0 ? '+' : '-';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${sign}KES ${compactKes(added.abs())}',
                style: TextStyle(
                  color: c.delta(added),
                  fontFamily: fructaFonts.mono,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                size.priorAsOf != null
                    ? 'Added since ${prettyDate(size.priorAsOf)}'
                    : 'Added over the quarter',
                style: TextStyle(color: c.faint, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceLine(fructaColors c, String source, String? asOf) {
    final dated = asOf != null ? ', as at ${prettyDate(asOf)}' : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 12, color: c.faint),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '$source$dated',
            style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// One fund type: swatch, name, share, AUM, and a fill bar that grows with the
/// ring. Full width now that the donut has its own row, so the bar has room to
/// carry the comparison the old cramped legend could not.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.color,
    required this.share,
    required this.aum,
    required this.t,
  });

  final String label;
  final Color color;
  final double share;
  final double aum;
  final double t;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${share.toStringAsFixed(share < 10 ? 1 : 0)}%',
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text(
                  compactKes(aum),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: c.faint,
                    fontFamily: fructaFonts.mono,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: c.line2,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: ((share / 100) * t).clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

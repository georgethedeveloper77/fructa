import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund.dart';

/// "Performance"  trailing annualised returns (YTD/1Y/3Y/5Y) as a dumbbell
/// chart: fund and benchmark plotted as two connected dots on one shared scale,
/// so the eye lands on the GAP (fund vs bench) rather than on bar length. The
/// scale spans the data's own min/max (not a 0 baseline), which is honest for a
/// position plot and  unlike bars-from-zero  actually separates values that
/// cluster in a tight band. Dots animate out from centre on load; tap a period
/// to highlight it. Plus the best/worst monthly band beneath.
///
/// Same data the manager's fact sheet publishes (0027); hidden when nothing is
/// seeded. Icon-free  drawn dots and mono figures, no glyphs.
class FundPerformance extends StatefulWidget {
  const FundPerformance(this.fund, {super.key, this.tint});

  final Fund fund;
  final Color? tint;

  @override
  State<FundPerformance> createState() => _FundPerformanceState();
}

class _FundPerformanceState extends State<FundPerformance> {
  int _selected = -1;

  static const _months = [
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

  String? _asOf() {
    final iso = widget.fund.returnsAsOf;
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? null : '${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final fund = widget.fund;
    final c = context.c;
    final brand = widget.tint ?? c.accent;

    // (label, fund, benchmark). YTD has no stored benchmark → null.
    final rows = <(String, double?, double?)>[
      if (fund.returnYtd != null) ('YTD', fund.returnYtd, null),
      if (fund.return1y != null) ('1 YEAR', fund.return1y, fund.bench1y),
      if (fund.return3y != null) ('3 YEAR', fund.return3y, fund.bench3y),
      if (fund.return5y != null) ('5 YEAR', fund.return5y, fund.bench5y),
    ];
    final hasBand = fund.bestMonth != null && fund.worstMonth != null;
    if (rows.isEmpty && !hasBand) return const SizedBox.shrink();

    // Shared scale over the data's own range, padded  a position plot, so a
    // non-zero baseline is legitimate and it separates clustered values.
    final vals = <double>[];
    for (final r in rows) {
      if (r.$2 != null) vals.add(r.$2!);
      if (r.$3 != null) vals.add(r.$3!);
    }
    var lo = vals.isEmpty ? 0.0 : vals.reduce(math.min);
    var hi = vals.isEmpty ? 1.0 : vals.reduce(math.max);
    if ((hi - lo).abs() < 0.5) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.18;
    lo -= pad;
    hi += pad;

    final hasBench = rows.any((r) => r.$3 != null);
    final asOf = _asOf();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
          child: Text(
            asOf != null
                ? 'PERFORMANCE \u00b7 AS OF ${asOf.toUpperCase()}'
                : 'PERFORMANCE',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: _Legend(brand: brand, hasBench: hasBench),
                  ),
                  for (var i = 0; i < rows.length; i++)
                    _Dumbbell(
                      label: rows[i].$1,
                      fundV: rows[i].$2!,
                      benchV: rows[i].$3,
                      lo: lo,
                      hi: hi,
                      brand: brand,
                      selected: _selected == i,
                      onTap: () =>
                          setState(() => _selected = _selected == i ? -1 : i),
                    ),
                ],
                if (hasBand) ...[
                  if (rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                      child: Divider(height: 1, color: c.line),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _MonthBand(
                      worst: fund.worstMonth!,
                      best: fund.bestMonth!,
                      tint: brand,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fund (filled brand) vs Benchmark (hollow ring) legend, matching the dots.
class _Legend extends StatelessWidget {
  const _Legend({required this.brand, required this.hasBench});
  final Color brand;
  final bool hasBench;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        _dot(filled: true, color: brand, ring: brand),
        const SizedBox(width: 6),
        Text(
          'Fund',
          style: TextStyle(
            color: c.muted,
            fontFamily: fructaFonts.mono,
            fontSize: 10,
          ),
        ),
        if (hasBench) ...[
          const SizedBox(width: 16),
          _dot(filled: false, color: c.s3, ring: c.muted),
          const SizedBox(width: 6),
          Text(
            'Benchmark',
            style: TextStyle(
              color: c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot({
    required bool filled,
    required Color color,
    required Color ring,
  }) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: filled ? null : Border.all(color: ring, width: 1.5),
    ),
  );
}

/// One period: header (label + delta), then a shared-scale track with a
/// benchmark dot and a fund dot joined by a connector. Dots animate out from
/// centre; selecting the period enlarges and glows them.
class _Dumbbell extends StatelessWidget {
  const _Dumbbell({
    required this.label,
    required this.fundV,
    required this.benchV,
    required this.lo,
    required this.hi,
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double fundV;
  final double? benchV;
  final double lo;
  final double hi;
  final Color brand;
  final bool selected;
  final VoidCallback onTap;

  double _frac(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fundColor = fundV >= 0 ? brand : c.down;
    final delta = benchV != null ? fundV - benchV! : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? c.s2 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.muted,
                    fontFamily: fructaFonts.mono,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (delta != null)
                  Text(
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)} pts vs bench',
                    style: TextStyle(
                      color: c.delta(delta),
                      fontFamily: fructaFonts.mono,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 48,
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  final w = cons.maxWidth;
                  final ff = _frac(fundV);
                  final bf = benchV != null ? _frac(benchV!) : null;
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (ctx, t, _) {
                      final fx = (0.5 + (ff - 0.5) * t) * w;
                      final bx = bf != null ? (0.5 + (bf - 0.5) * t) * w : null;
                      final fundR = selected ? 8.0 : 6.5;
                      final benchR = selected ? 7.0 : 5.5;
                      const cy = 24.0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // baseline
                          Positioned(
                            left: 0,
                            right: 0,
                            top: cy - 1,
                            child: Container(height: 2, color: c.line),
                          ),
                          // connector
                          if (bx != null)
                            Positioned(
                              left: math.min(fx, bx),
                              top: cy - 2,
                              child: Container(
                                width: (fx - bx).abs(),
                                height: 4,
                                decoration: BoxDecoration(
                                  color: c.line2,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          // benchmark value (below)
                          if (bx != null)
                            Positioned(
                              left: (bx - 22).clamp(0.0, w - 44),
                              top: cy + 8,
                              child: SizedBox(
                                width: 44,
                                child: Text(
                                  '${benchV!.toStringAsFixed(2)}%',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: c.muted,
                                    fontFamily: fructaFonts.mono,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // benchmark dot (hollow ring)
                          if (bx != null)
                            Positioned(
                              left: bx - benchR,
                              top: cy - benchR,
                              child: Container(
                                width: benchR * 2,
                                height: benchR * 2,
                                decoration: BoxDecoration(
                                  color: c.s3,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: c.muted,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          // fund value (above)
                          Positioned(
                            left: (fx - 24).clamp(0.0, w - 48),
                            top: 0,
                            child: SizedBox(
                              width: 48,
                              child: Text(
                                '${fundV.toStringAsFixed(2)}%',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: fundColor,
                                  fontFamily: fructaFonts.mono,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // fund dot (filled brand, glow when selected)
                          Positioned(
                            left: fx - fundR,
                            top: cy - fundR,
                            child: Container(
                              width: fundR * 2,
                              height: fundR * 2,
                              decoration: BoxDecoration(
                                color: fundColor,
                                shape: BoxShape.circle,
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: fundColor.withValues(
                                            alpha: 0.45,
                                          ),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthBand extends StatelessWidget {
  const _MonthBand({
    required this.worst,
    required this.best,
    required this.tint,
  });
  final double worst;
  final double best;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MONTHLY RETURN RANGE \u00b7 TRAILING 12 MO',
          style: TextStyle(
            color: c.faint,
            fontFamily: fructaFonts.mono,
            fontSize: 9,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _end(context, 'WORST', worst, c.muted, alignEnd: false),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(colors: [c.s3, tint]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _end(context, 'BEST', best, c.text, alignEnd: true),
          ],
        ),
      ],
    );
  }

  Widget _end(
    BuildContext context,
    String k,
    double v,
    Color valColor, {
    required bool alignEnd,
  }) {
    final c = context.c;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: TextStyle(
            color: c.faint,
            fontFamily: fructaFonts.mono,
            fontSize: 8.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${v.toStringAsFixed(2)}%',
          style: TextStyle(
            color: valColor,
            fontFamily: fructaFonts.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/fund.dart';
import '../../../data/snapshot_providers.dart';

const _typeNames = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

// Human labels for the stated-benchmark key (funds.benchmark_key, 0026).
const _benchLabels = {
  'tbill_91': '91-day T-bill',
  'tbill_182': '182-day T-bill',
  'tbill_364': '364-day T-bill',
  'cbr': 'Central Bank Rate',
};

/// Best-MMF hero (v6 `.hero`), matched to the mockup: brand-washed card with a
/// leading logo, name + type tag, a "Best rate" pill, a 44px count-up rate with
/// `% gross`, the net / real / min triad, and a brand sparkline carrying a
/// dashed reference for the fund's OWN stated benchmark (0026) plus legend and
/// an explicit vs-benchmark delta. Brand hue drives every accent; the rate
/// itself stays `text` for legibility. Deltas use Material chevrons.
class BestFundHero extends ConsumerWidget {
  const BestFundHero(
    this.fund, {
    super.key,
    required this.onTap,
    this.delta,
    this.brandColor,
  });

  final Fund fund;
  final VoidCallback onTap;
  final double? delta;
  final Color? brandColor;

  static String _commas(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final tint = brandColor ?? categoryColor(fund.category);
    final cfg = ref.watch(remoteConfigProvider);
    final wht = cfg.whtPct;
    final logoUrl = ref.watch(logoUrlProvider(fund.id));

    final rate = fund.currentRate ?? 0;
    final net = fund.netRate(wht);
    final real = fund.realRate(cfg.inflationPct);
    final tag =
        '${_typeNames[fund.fundType] ?? fund.category} \u00b7 ${fund.currency}';
    final d = delta;

    // Dark s1 is nearly invisible against bg, so the hero recedes. Lift the
    // base to s2 in dark and carry a soft brand shadow (below) so the featured
    // card clearly floats as the focal point. Light mode keeps s1.
    final base = c.isDark ? c.s2 : c.s1;

    // The fund's OWN stated benchmark (0026), replacing the hardcoded 91-day.
    // Falls back to the 91-day so the reference line always renders (matches
    // the prior behaviour, and every MMF was backfilled to tbill_91 anyway).
    final benchRate =
        cfg.benchmarkRate(fund.benchmarkConfigKey ?? 'benchmark.tbill_91',
            cfg.tbill91Pct);
    final benchLabel =
        _benchLabels[fund.benchmarkKey ?? 'tbill_91'] ?? '91-day T-bill';
    // Explicit gross-vs-benchmark spread (same basis as the fact sheet). Null
    // for non-yielding funds, so the annotation simply doesn't show.
    final benchDelta = (fund.showsYield && fund.currentRate != null)
        ? fund.currentRate! - benchRate
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    tint.withValues(alpha: c.isDark ? 0.20 : 0.08), base),
                Color.alphaBlend(
                    tint.withValues(alpha: c.isDark ? 0.05 : 0.0), base),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: tint.withValues(alpha: c.isDark ? 0.44 : 0.30),
              width: c.isDark ? 1.2 : 1,
            ),
            boxShadow: c.isDark
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.22),
                      blurRadius: 30,
                      spreadRadius: -8,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // ambient brand glow
              Positioned(
                right: -60,
                top: -70,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        tint.withValues(alpha: c.isDark ? 0.34 : 0.26),
                        Colors.transparent
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── top: logo · name+tag · Best rate pill ──────────────
                  Row(
                    children: [
                      FundLogo(
                          domain: fund.logoDomain,
                          logoUrl: logoUrl,
                          seed: fund.manager,
                          size: 34,
                          brandColor: brandColor),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fund.name,
                                style: TextStyle(
                                    color: c.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(tag,
                                style: TextStyle(
                                    color: tint,
                                    fontFamily: fructaFonts.mono,
                                    fontSize: 10.5,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('BEST RATE',
                            style: TextStyle(
                                color: c.onAccent,
                                fontFamily: fructaFonts.mono,
                                fontSize: 9.5,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  // ── rate: 44 count-up · % gross · inline delta ─────────
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: rate),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, _) => Text(
                            v.toStringAsFixed(2),
                            style: TextStyle(
                              color: c.text,
                              fontFamily: fructaFonts.mono,
                              fontSize: 44,
                              height: 1,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text('% gross',
                              style: TextStyle(
                                  color: c.muted,
                                  fontFamily: fructaFonts.mono,
                                  fontSize: 18)),
                        ),
                        if (d != null && d != 0) ...[
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    d > 0
                                        ? Icons.arrow_drop_up
                                        : Icons.arrow_drop_down,
                                    size: 18,
                                    color: c.delta(d)),
                                Text('${d.abs().toStringAsFixed(2)} \u00b7 7d',
                                    style: TextStyle(
                                        color: c.delta(d),
                                        fontFamily: fructaFonts.mono,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // ── triad: net · real · min ────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        _TriadCell(
                          k: 'NET (${wht.toStringAsFixed(0)}% WHT)',
                          v: net != null
                              ? '${net.toStringAsFixed(2)}%'
                              : '\u2014',
                        ),
                        _vline(c),
                        _TriadCell(
                          k: 'REAL VS INFL.',
                          v: real != null
                              ? '${real >= 0 ? '+' : ''}${real.toStringAsFixed(2)}%'
                              : '\u2014',
                          color: real != null ? c.delta(real) : null,
                        ),
                        _vline(c),
                        _TriadCell(
                          k: 'MIN INVEST',
                          v: fund.minInvest != null
                              ? '${fund.currency} ${_commas(fund.minInvest!)}'
                              : '\u2014',
                        ),
                      ],
                    ),
                  ),
                  // ── chart: brand line + dashed benchmark reference ─────
                  if (fund.spark.length >= 2) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 84,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _HeroSpark(
                          fund.spark,
                          tint,
                          benchmark: benchRate,
                          benchColor: c.muted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Lg(color: tint, label: 'Fund rate'),
                        const SizedBox(width: 14),
                        _Lg(color: c.muted, label: benchLabel, dashed: true),
                        if (benchDelta != null) ...[
                          const Spacer(),
                          Text(
                            '${benchDelta >= 0 ? '+' : ''}${benchDelta.toStringAsFixed(2)} pts',
                            style: TextStyle(
                                color: c.delta(benchDelta),
                                fontFamily: fructaFonts.mono,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vline(fructaColors c) => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: c.line,
      );
}

class _TriadCell extends StatelessWidget {
  const _TriadCell({required this.k, required this.v, this.color});
  final String k;
  final String v;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k,
              style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 9.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(v,
              style: TextStyle(
                  color: color ?? c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _Lg extends StatelessWidget {
  const _Lg({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 2,
          child: dashed
              ? CustomPaint(painter: _DashLegend(color))
              : DecoratedBox(
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: c.muted, fontFamily: fructaFonts.mono, fontSize: 10)),
      ],
    );
  }
}

class _DashLegend extends CustomPainter {
  _DashLegend(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 3.0, gap = 3.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, y), Offset((x + dash).clamp(0, size.width), y), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashLegend old) => old.color != color;
}

/// Brand area sparkline with an optional dashed horizontal benchmark line.
/// The y-domain includes the benchmark so the reference always sits in view.
class _HeroSpark extends CustomPainter {
  _HeroSpark(this.pts, this.color, {this.benchmark, this.benchColor});
  final List<double> pts;
  final Color color;
  final double? benchmark;
  final Color? benchColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 2) return;
    var lo = pts.first, hi = pts.first;
    for (final v in pts) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (benchmark != null) {
      if (benchmark! < lo) lo = benchmark!;
      if (benchmark! > hi) hi = benchmark!;
    }
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    double yOf(double v) =>
        size.height - ((v - lo) / span) * (size.height - 6) - 3;

    if (benchmark != null && benchColor != null) {
      final by = yOf(benchmark!);
      final p = Paint()
        ..color = benchColor!.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      const dash = 4.0, gap = 4.0;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, by), Offset((x + dash).clamp(0, size.width), by), p);
        x += dash + gap;
      }
    }

    final line = Path();
    final fill = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = i / (pts.length - 1) * size.width;
      final y = yOf(pts[i]);
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.0)
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HeroSpark old) =>
      old.pts != pts || old.color != color || old.benchmark != benchmark;
}

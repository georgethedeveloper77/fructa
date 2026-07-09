import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_scaffold.dart';
import '../../core/categories.dart';
import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/accrual_engine.dart';
import '../../engine/portfolio_math.dart';
import 'add_holding_page.dart';
import 'manage_holding_sheet.dart';
import 'projection_card.dart';

/// Portfolio — markets-first, consolidated in KES.
///
/// Revamp: the old top bar (Add button + avatar) is gone; adding lives inside
/// the holdings card and the empty state. Hide-balances (the persisted V5 pref,
/// shared with Settings) now sits on the total it protects. Sections read as
/// discrete cards — hero, allocation, holdings — for a calmer, terminal-like
/// hierarchy. Each holding accrues from the date its lot was added (WHT unless
/// tax-free); USD converts at the snapshot's CBK rate; the hero trend is built
/// from the real accrual trajectory, so pre-purchase days read zero.
class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider);
    final byId = ref.watch(fundsByIdProvider);
    final fx = ref.watch(usdKesProvider); // KES per USD, or null if unpublished
    final hidden = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: holdings.isEmpty
            ? const _Empty()
            : _Full(holdings: holdings, byId: byId, fx: fx, hidden: hidden),
      ),
    );
  }
}

class _Full extends ConsumerWidget {
  const _Full({
    required this.holdings,
    required this.byId,
    required this.fx,
    required this.hidden,
  });

  final List<Holding> holdings;
  final Map<String, Fund> byId;
  final double? fx;
  final bool hidden;

  /// Consolidated KES value of the whole book at [d]. A holding counts only
  /// once it's actually held (firstLot <= d), so pre-purchase days read zero.
  double _totalAt(DateTime d) {
    var t = 0.0;
    for (final h in holdings) {
      final f = byId[h.fundId];
      final v = PortfolioMath.value(
        h,
        ratePercent: f?.currentRate,
        taxFree: f?.taxFree ?? false,
        usdKes: fx,
        asOf: d,
      );
      if (v.firstLot.isAfter(d)) continue;
      if (v.valueKes != null) t += v.valueKes!;
    }
    return t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = DateTime.now();

    var totalKes = 0.0;
    var costKes = 0.0;
    var dailyKes = 0.0;
    var wSum = 0.0, w = 0.0;
    var fxMissing = false;
    final byCategory = <String, double>{};
    final values = <String, HoldingValue>{};

    for (final h in holdings) {
      final f = byId[h.fundId];
      final v = PortfolioMath.value(
        h,
        ratePercent: f?.currentRate,
        taxFree: f?.taxFree ?? false,
        usdKes: fx,
        asOf: now,
      );
      values[h.fundId] = v;

      if (v.valueKes != null) {
        totalKes += v.valueKes!;
        costKes += v.principalKes ?? 0;
      } else {
        fxMissing = true;
      }

      final r = f?.currentRate;
      if (f != null && r != null) {
        final dailyOwn = f.taxFree
            ? AccrualEngine.dailyInterest(v.valueNative, r)
            : AccrualEngine.dailyInterestNet(v.valueNative, r);
        dailyKes += v.isUsd ? (fx != null ? dailyOwn * fx! : 0.0) : dailyOwn;
        if (v.valueKes != null) {
          byCategory[f.category] = (byCategory[f.category] ?? 0) + v.valueKes!;
          wSum += r * v.valueKes!;
          w += v.valueKes!;
        }
      }
    }

    final gainKes = totalKes - costKes;
    final monthlyKes = dailyKes * 365 / 12;
    final yearlyKes = dailyKes * 365;
    final blendedGross = w > 0 ? wSum / w : 0.0;
    final providers = holdings
        .map((h) => byId[h.fundId]?.manager)
        .whereType<String>()
        .toSet()
        .length;

    // Hero trend — 31 daily samples of the whole book's accrued KES value.
    final trend = [
      for (var i = 30; i >= 0; i--) _totalAt(now.subtract(Duration(days: i))),
    ];
    final trendVaries =
        trend.isNotEmpty && trend.reduce((a, b) => a > b ? a : b) > 0;

    String bal(String s) => hidden ? '\u2022\u2022\u2022\u2022' : s;

    final allocTotal = byCategory.values.fold<double>(0, (a, b) => a + b);
    final slices =
        (byCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .map(
              (e) => AllocSlice(
                label: categoryLabel(e.key),
                color: categoryColor(e.key),
                weight: e.value,
                valueText: allocTotal > 0
                    ? '${(e.value / allocTotal * 100).round()}%'
                    : '0%',
              ),
            )
            .toList();

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        DisplayHeader(
          title: 'Portfolio',
          sub:
              '${holdings.length} holdings \u00b7 $providers providers \u00b7 consolidated in KES',
        ),
        const SizedBox(height: 6),

        // ── Hero — total (count-up), gain, trend; eye lives here ──────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: _HeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'TOTAL VALUE',
                      style: TextStyle(
                        color: c.muted,
                        fontFamily: fructaFonts.mono,
                        fontSize: 10,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _EyeToggle(hidden: hidden),
                  ],
                ),
                const SizedBox(height: 8),
                hidden
                    ? _bigText(context, 'KES \u2022\u2022\u2022\u2022')
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: totalKes),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) =>
                              _bigText(context, money('KES', v)),
                        ),
                      ),
                const SizedBox(height: 8),
                gainKes >= 1
                    ? Row(
                        children: [
                          Icon(Icons.trending_up_rounded, color: c.up, size: 16),
                          const SizedBox(width: 5),
                          Text(
                            bal('+${money('KES', gainKes.round())}'),
                            style: TextStyle(
                              color: c.up,
                              fontFamily: fructaFonts.mono,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'earned since you added',
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      )
                    : Text(
                        'Tracking your earnings from today',
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                if (fxMissing) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: c.faint, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "USD value unavailable. Today's USD/KES rate isn't set.",
                          style: TextStyle(color: c.faint, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
                if (trendVaries && !hidden) ...[
                  const SizedBox(height: 14),
                  SizedBox(height: 58, child: _TrendChart(trend, c.accent)),
                ],
              ],
            ),
          ),
        ),

        // pf run-rate — forward earning at the current blended net yield
        EarnStrip([
          EarnCell('Earning / day', '+${bal(money('KES', dailyKes.round()))}'),
          EarnCell('/ month', '+${bal(money('KES', monthlyKes.round()))}'),
          EarnCell('/ year', '+${bal(money('KES', yearlyKes.round()))}'),
        ]),

        if (slices.isNotEmpty) ...[
          const SectionHeader(title: 'Allocation'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: _AllocationCard(slices: slices, total: allocTotal),
          ),
        ],

        const SectionHeader(title: 'Holdings', trailing: 'accrued value shown'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: _HoldingsCard(
            children: [
              for (var i = 0; i < holdings.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                _HoldingRow(
                  holding: holdings[i],
                  fund: byId[holdings[i].fundId],
                  value: values[holdings[i].fundId]!,
                  hidden: hidden,
                ),
              ],
              Divider(height: 1, thickness: 1, color: c.line),
              _AddRowInline(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddHoldingPage()),
                ),
              ),
            ],
          ),
        ),

        if (totalKes > 0 && blendedGross > 0) ...[
          const SectionHeader(title: 'If you keep investing'),
          ProjectionCard(
            principal: totalKes,
            grossRate: blendedGross,
            currency: 'KES',
          ),
        ],

        Disclaimer(
          "Values are estimates: each holding grows daily at the fund's net "
          "yield from the date you added it. USD positions earn their own USD "
          "yield and convert at the CBK indicative rate for the total. Not a "
          'promise, and fructa never holds your money.',
        ),
      ],
    );
  }

  Widget _bigText(BuildContext context, String s) => Text(
    s,
    style: TextStyle(
      color: context.c.text,
      fontFamily: fructaFonts.mono,
      fontSize: 42,
      fontWeight: FontWeight.w600,
      letterSpacing: -2,
      height: 1,
    ),
  );
}

// ── Hero card shell — s2 fill + line2 border + faint accent wash ─────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(c.accent.withValues(alpha: 0.06), c.s2),
            c.s2,
          ],
        ),
      ),
      child: child,
    );
  }
}

// ── Eye toggle (hide balances) — the only survivor of the old top bar ───────
class _EyeToggle extends ConsumerWidget {
  const _EyeToggle({required this.hidden});
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => ref
          .read(settingsControllerProvider.notifier)
          .setHideBalances(!hidden),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: c.muted,
          size: 18,
        ),
      ),
    );
  }
}

// ── Holdings card shell ─────────────────────────────────────────────────────
class _HoldingsCard extends StatelessWidget {
  const _HoldingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Column(children: children),
    );
  }
}

// ── Allocation — donut + valued legend, boxed for dark-mode contrast ─────────
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.slices, required this.total});
  final List<AllocSlice> slices;
  final double total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Lift each data colour so it clears the card in either mode.
    final segs = [
      for (final s in slices)
        (weight: s.weight, color: c.brandOnBg(s.color, minContrast: 2.4)),
    ];
    final top = slices.first;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(96),
                  painter: _DonutPainter(
                    segs: segs,
                    stroke: 15,
                    track: c.line,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      top.valueText,
                      style: TextStyle(
                        color: c.text,
                        fontFamily: fructaFonts.mono,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      top.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.faint, fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < slices.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _LegendRow(
                    slice: slices[i],
                    dot: c.brandOnBg(slices[i].color, minContrast: 2.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.dot});
  final AllocSlice slice;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                money('KES', slice.weight.round()),
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          slice.valueText,
          style: TextStyle(
            color: c.text,
            fontFamily: fructaFonts.mono,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segs,
    required this.stroke,
    required this.track,
  });

  final List<({double weight, Color color})> segs;
  final double stroke;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;
    final total = segs.fold<double>(0, (a, s) => a + s.weight);

    // Track ring behind everything.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (total <= 0) return;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // A single slice reads as an unbroken ring (no rounded-cap overlap).
    if (segs.length == 1) {
      ring
        ..color = segs.first.color
        ..strokeCap = StrokeCap.butt;
      canvas.drawCircle(center, radius, ring);
      return;
    }

    ring.strokeCap = StrokeCap.round;
    const gap = 0.05; // radians of breathing room between slices
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2; // 12 o'clock
    for (final s in segs) {
      final frac = s.weight / total;
      final full = frac * 2 * math.pi;
      final sweep = full - gap;
      if (sweep > 0) {
        canvas.drawArc(rect, start + gap / 2, sweep, false, ring..color = s.color);
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segs != segs || old.stroke != stroke || old.track != track;
}

// ── Hero trend chart ────────────────────────────────────────────────────────
class _TrendChart extends StatelessWidget {
  const _TrendChart(this.data, this.color);
  final List<double> data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (data.length < 2) return const SizedBox.shrink();
    final lo = data.reduce((a, b) => a < b ? a : b);
    final hi = data.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1e-6 ? 1.0 : (hi - lo);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: lo - span * 0.08,
        maxY: hi + span * 0.08,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < data.length; i++)
                FlSpot(i.toDouble(), data[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.28,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.20),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Holding tile — real logo + brand accent bar ─────────────────────────────
class _HoldingRow extends ConsumerWidget {
  const _HoldingRow({
    required this.holding,
    required this.fund,
    required this.value,
    required this.hidden,
  });

  final Holding holding;
  final Fund? fund;
  final HoldingValue value;
  final bool hidden;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = fund;
    final name = f?.name ?? holding.fundId;
    final rate = f?.currentRate;
    final ccy = holding.currency;
    final brand =
        ref.watch(brandColorProvider(holding.fundId)) ??
        fundTypeColor(f?.fundType);
    final logoUrl = ref.watch(logoUrlProvider(holding.fundId));
    final since = '${_months[value.firstLot.month - 1]} ${value.firstLot.day}';

    final valNative = ccy == 'USD'
        ? '\$${value.valueNative.toStringAsFixed(2)}'
        : money('KES', value.valueNative);
    final balText = hidden ? '\u2022\u2022\u2022\u2022' : valNative;

    final gain = value.gainNative;
    final showGain = gain >= (ccy == 'USD' ? 0.005 : 1);
    final gainText = ccy == 'USD'
        ? '+\$${gain.toStringAsFixed(2)}'
        : '+${money('KES', gain.round())}';
    final earnLine = rate == null
        ? null
        : (showGain ? '$gainText \u00b7 since $since' : 'Added $since');

    final sub = rate != null
        ? '${rate.toStringAsFixed(2)}% ${f!.taxFree ? 'tax-free' : 'net'}${ccy == 'USD' ? ' \u00b7 USD' : ''}'
        : 'rate unavailable';

    return InkWell(
      onTap: () => showManageHolding(context, holding, f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(
          children: [
            // brand accent bar
            Container(
              width: 3,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: brand,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            FundLogo(
              domain: f?.logoDomain,
              logoUrl: logoUrl,
              brandColor: brand,
              seed: f?.manager ?? name,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: c.faint, fontSize: 10.5)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  balText,
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (earnLine != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hidden ? '\u2022\u2022\u2022\u2022' : earnLine,
                    style: TextStyle(
                      color: showGain ? c.up : c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── In-card add row (replaces the standalone dashed box) ────────────────────
class _AddRowInline extends StatelessWidget {
  const _AddRowInline({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: c.accentInk, size: 18),
            const SizedBox(width: 6),
            Text(
              'Add a holding',
              style: TextStyle(
                color: c.accentInk,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded dashed border box (Flutter has no built-in dashed border).
/// Retained as shared kit even though the portfolio list no longer uses it.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 16,
  });
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashPainter(color, radius), child: child);
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        dashed.addPath(metric.extractPath(d, d + dash), Offset.zero);
        d += dash + gap;
      }
    }
    canvas.drawPath(
      dashed,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Empty state ─────────────────────────────────────────────────────────────
class _Empty extends ConsumerWidget {
  const _Empty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 20),
      children: [
        Center(
          child: Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(Icons.work_outline, color: c.accent, size: 34),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your portfolio is empty',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add what you already hold and Fructa shows your real balance, daily '
          'earnings and projections all in one place.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        CtaFull(
          label: 'Add your first investment',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddHoldingPage())),
        ),
        CtaGhost(
          label: 'Browse top rates',
          onTap: () => ref.read(selectedTabProvider.notifier).state = 0,
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../core/i18n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/rate_basis.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/fund.dart';
import '../../../data/snapshot_providers.dart';
import '../../wrap/wrap_engine.dart';
import '../../wrap/wrap_viewer.dart';

/// One fund in the Markets list.
///
/// Rank, logo, name, a trend line, one rate (gross or net per the app-wide
/// [showNetProvider]) and its 7-day move on the same basis. A tap opens the
/// fund page; in compare mode it selects instead.
///
/// The trend line and the 7-day figure come from two sources (rate history
/// and the latest rate event). When they point in opposite directions the
/// figure is left out rather than shown beside a line that contradicts it.
class FundTile extends ConsumerWidget {
  const FundTile(
    this.fund, {
    super.key,
    required this.onTap,
    this.rank,
    this.selectable = false,
    this.selected = false,
    this.onToggleSelect,
    this.brandColor,
    this.delta,
  });

  final Fund fund;

  /// Opens the fund page.
  final VoidCallback onTap;
  final int? rank;
  final bool selectable;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final Color? brandColor;

  /// Seven-day move in GROSS points, from the fund's rate event.
  final double? delta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = fund;
    final cfg = ref.watch(remoteConfigProvider);
    final wht = cfg.whtPct;
    final showNet = ref.watch(showNetProvider);

    final rate = f.currentRate;
    final hasRate = f.showsYield && rate != null;
    // Net only exists where a deduction is still to come.
    final net = hasRate && f.whtStillDue && !f.taxFree ? f.netRate(wht) : null;
    final useNet = showNet && net != null;

    final headline = f.headlineWith(
      ref.watch(latestPeriodReturnProvider(f.id)),
    );
    final big = switch (headline) {
      YieldHeadline(:final gross) =>
        '${(useNet ? net : gross).toStringAsFixed(2)}%',
      ReturnHeadline(:final pct) =>
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
      NoHeadline() => t('common.dash'),
    };
    final bigColor = switch (headline) {
      ReturnHeadline(:final pct) => c.delta(pct),
      YieldHeadline() => c.text,
      NoHeadline() => c.faint,
    };

    final raw = delta;
    final d = raw == null ? null : (useNet ? raw * (1 - wht / 100) : raw);
    String signed(double v, {int places = 2}) =>
        '${v > 0 ? '+' : ''}${v.toStringAsFixed(places)}';

    // Trend direction of the line actually drawn, for the agreement check.
    final spark = f.showsYield ? f.spark : const <double>[];
    final trend = spark.length >= 2 ? spark.last - spark.first : 0.0;
    final agrees = d == null || trend == 0 || (d > 0) == (trend > 0);

    return Material(
      color: selected ? c.accentSoft : c.bg.withValues(alpha: 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: selectable ? onToggleSelect : onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
                child: Row(
                  children: [
                    if (rank != null)
                      SizedBox(
                        width: 22,
                        child: Text(
                          '$rank',
                          style: fructaFonts.numeric(
                            color: rank! <= 3 ? c.accentInk : c.faint,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    _Logo(
                      fund: f,
                      brandColor: brandColor,
                      checked: selectable && selected,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // A medal from this week's wrap, tap to open its story.
                          if (!selectable)
                            if (ref.watch(weeklyWrapProvider).badges[f.id]
                                case final b?) ...[
                              const SizedBox(height: 5),
                              _Badge(badge: b),
                            ],
                        ],
                      ),
                    ),
                    if (spark.length >= 2) ...[
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 48,
                        height: 26,
                        child: CustomPaint(
                          painter: _Spark(
                            spark,
                            trend == 0 ? c.faint : (trend > 0 ? c.up : c.down),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 62),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StretchSwap(
                            value: useNet,
                            alignment: Alignment.centerRight,
                            child: Glitch(
                              trigger: rate,
                              a: c.accent,
                              b: c.down,
                              child: Text(
                                big,
                                style: fructaFonts.numeric(
                                  color: bigColor,
                                  size: 18,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (headline case ReturnHeadline(:final label))
                            Text(
                              label,
                              style: TextStyle(color: c.faint, fontSize: 10.5),
                            )
                          else if (headline case NoHeadline(:final reason))
                            Text(
                              reason,
                              style: TextStyle(color: c.faint, fontSize: 9.5),
                            )
                          else if (d != null && d != 0 && agrees)
                            Text(
                              signed(d),
                              style: fructaFonts.numeric(
                                color: c.delta(d),
                                size: 11.5,
                                weight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo with the compare check badge.
class _Logo extends ConsumerWidget {
  const _Logo({
    required this.fund,
    required this.brandColor,
    required this.checked,
  });

  final Fund fund;
  final Color? brandColor;
  final bool checked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          FundLogo(
            domain: fund.logoDomain,
            logoUrl: ref.watch(logoUrlProvider(fund.id)),
            seed: fund.manager,
            size: 36,
            brandColor: brandColor,
          ),
          if (checked)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
                child: Icon(Icons.check, size: 10, color: c.onAccent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Trend line: the fund's recent rate series, one colour by direction.
class _Spark extends CustomPainter {
  _Spark(this.points, this.color);

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = points.first, hi = points.first;
    for (final v in points) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = span == 0
          ? size.height / 2
          : size.height - (points[i] - lo) / span * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _Spark old) =>
      old.points != points || old.color != color;
}

/// "Most improved", "Most stable", "Moving up", "Top rate": a fund's place in
/// this week's wrap. Lasts until the next wrap.
class _Badge extends StatelessWidget {
  const _Badge({required this.badge});

  final FundBadge badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = switch (badge.tone) {
      WrapTone.up || WrapTone.tbill => c.up,
      WrapTone.down => c.down,
      WrapTone.info => c.dataInk(fundTypeColor('fixed_income')),
      WrapTone.accent => c.accentInk,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openWeeklyWrap(context, start: badge.slideIndex),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: c.isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_outlined, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              t(badge.labelKey),
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

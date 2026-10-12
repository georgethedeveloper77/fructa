import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/categories.dart';
import '../../../core/i18n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/fund.dart';
import '../../../data/snapshot_providers.dart';

/// One fund in the Markets list: a hairline row, not a card.
///
/// Rank sits at the left for the whole visit. The large figure is what the
/// holder keeps (net of withholding where a deduction is still due), and the
/// gross sits once in the line under the name, so no figure appears twice on
/// the row. A new print for the fund glitches the figure for half a second.
/// Funds that quote no single yield show the reason, never a made-up number.
class FundTile extends ConsumerStatefulWidget {
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
  final VoidCallback onTap;
  final int? rank;
  final bool selectable;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final Color? brandColor;
  final double? delta;

  @override
  ConsumerState<FundTile> createState() => _FundTileState();
}

const _typeNames = {
  'mmf': 'Money Market',
  'fixed_income': 'Fixed Income',
  'equity': 'Equity',
  'balanced': 'Balanced',
  'special': 'Special',
};

String _typeLabel(Fund f) {
  final t = _typeNames[f.fundType];
  if (t != null) return '$t \u00b7 ${f.currency}';
  return categoryLabel(f.category); // legacy: tbill / bond / sacco
}

String _commas(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class _FundTileState extends ConsumerState<FundTile> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = widget.fund;
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final logoUrl = ref.watch(logoUrlProvider(f.id));
    // The 7-day move arrives in GROSS points. When the figure above it is net,
    // the move is shown net too, or -0.19 sits under 9.78% as if it applied
    // to that number.
    final rawDelta = widget.delta;

    final rate = f.currentRate;
    final hasRate = f.showsYield && rate != null;
    // Net only where a deduction is actually still to come. A fund published
    // net of tax has no second, smaller figure to show.
    final net = hasRate && f.whtStillDue && !f.taxFree ? f.netRate(wht) : null;
    final d = rawDelta == null
        ? null
        : (net != null ? rawDelta * (1 - wht / 100) : rawDelta);

    final headline = f.headlineWith(
      ref.watch(latestPeriodReturnProvider(f.id)),
    );

    final big = switch (headline) {
      YieldHeadline(:final gross) => '${(net ?? gross).toStringAsFixed(2)}%',
      ReturnHeadline(:final pct) =>
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
      NoHeadline() => t('common.dash'),
    };
    final bigColor = switch (headline) {
      ReturnHeadline(:final pct) => c.delta(pct),
      YieldHeadline() => c.text,
      NoHeadline() => c.faint,
    };

    // Type and currency once (the old row printed the currency twice), then
    // the gross and the minimum.
    final type = _typeLabel(f);
    final detail = [
      if (net != null)
        t('markets.row.gross', {'rate': '${rate!.toStringAsFixed(2)}%'}),
      if (f.minInvest != null)
        t('markets.row.min', {
          'amount': '${f.currency} ${_commas(f.minInvest!)}',
        }),
    ].join(' \u00b7 ');

    return Material(
      color: widget.selected ? c.accentSoft : c.bg.withValues(alpha: 0),
      child: InkWell(
        onTap: widget.selectable ? widget.onToggleSelect : widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              if (widget.rank != null) ...[
                SizedBox(
                  width: 20,
                  child: Text(
                    '${widget.rank}',
                    style: fructaFonts.numeric(
                      color: widget.rank! <= 3 ? c.accentInk : c.faint,
                      size: 12,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FundLogo(
                      domain: f.logoDomain,
                      logoUrl: logoUrl,
                      seed: f.manager,
                      size: 38,
                      brandColor: widget.brandColor,
                    ),
                    if (widget.selectable && widget.selected)
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
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          type,
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                        if (f.taxFree)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.upSoft,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              t('markets.row.taxFree'),
                              style: TextStyle(
                                color: c.up,
                                fontSize: 9.5,
                                letterSpacing: 0.3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              // Rate series only: never a rate trend beside a period return.
              if (f.showsYield && f.spark.length >= 2) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  height: 24,
                  child: CustomPaint(
                    painter: _TileSpark(
                      f.spark,
                      up: c.up,
                      down: c.down,
                      flat: c.faint,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glitch(
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
                  // The period stays under a return, so a quarter is never read
                  // as a year beside a column of annual yields.
                  if (headline case ReturnHeadline(:final label)) ...[
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: TextStyle(color: c.faint, fontSize: 10.5),
                    ),
                  ],
                  if (headline case NoHeadline(:final reason)) ...[
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 9.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                  if (d != null && d != 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${d > 0 ? '+' : ''}${d.toStringAsFixed(2)}',
                      style: fructaFonts.numeric(
                        color: c.delta(d),
                        size: 11.5,
                        weight: FontWeight.w600,
                      ),
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
}

/// Minimal trailing sparkline: 1.5px polyline, coloured by overall trend
/// (first vs last point). Self-contained so the tile has no dependency on
/// the chart stack.
class _TileSpark extends CustomPainter {
  _TileSpark(
    this.points, {
    required this.up,
    required this.down,
    required this.flat,
  });
  final List<double> points;
  final Color up;
  final Color down;
  final Color flat;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var lo = points.first, hi = points.first;
    for (final v in points) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i / (points.length - 1) * size.width;
      final y = size.height - ((points[i] - lo) / span) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color =
            (points.last == points.first
                    ? flat
                    : points.last > points.first
                    ? up
                    : down)
                .withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TileSpark old) => old.points != points;
}

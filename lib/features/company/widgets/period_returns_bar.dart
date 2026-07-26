import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/models/period_return.dart';

/// The chart a special fund lives on: one bar per CLOSED period, with the
/// average since inception behind them.
///
/// Three rules are enforced here rather than left to the caller, because each
/// one is a way of drawing a true set of numbers into a false picture.
///
/// ONE PERIOD KIND ONLY. [FundReturns.series] hands back the dominant kind and
/// nothing else. A 4.74% quarter and a 20.74% year on one axis is not a
/// comparison, it is two questions answered at different scales in one image.
///
/// NEGATIVE BARS DRAW DOWN, NOT SHORT. The baseline sits at zero wherever zero
/// falls in the range, so a losing period reads as a loss. Clamping it to a
/// stub, which is what a naive height calculation does, turns a bad quarter into
/// a quiet one.
///
/// FOUR PERIODS OR NO CHART. Etica Special Multi Asset has two. A line through
/// two points is not a trend, and a bar chart of two bars invites one to be read
/// off the other. Below the floor this states the record in words instead.
class PeriodReturnsBar extends StatelessWidget {
  const PeriodReturnsBar(this.fund, this.returns, {super.key, this.tint});

  final Fund fund;
  final FundReturns returns;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final series = returns.series;
    if (series.isEmpty) return const SizedBox.shrink();

    final colour = tint ?? c.accent;
    final kind = series.first.period;

    if (series.length < 4) {
      return _ThinRecord(series: series, kind: kind, colour: colour);
    }

    final avg = returns.averagePct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 168,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1300),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) => CustomPaint(
              painter: _BarsPainter(
                series: series,
                average: avg,
                progress: t,
                up: colour,
                down: c.down,
                text: c.text,
                faint: c.faint,
                accent: c.accent,
                grid: c.line,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          avg == null
              ? 'Each bar is one completed ${kind.label.toLowerCase()}.'
              : 'Each bar is one completed ${kind.label.toLowerCase()}. '
                    'The dashed line is the ${avg.toStringAsFixed(2)}% average since inception.',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 4),
        Text(
          'Published ${series.first.netOf.shortLabel}. These are periods that have already closed, not a forecast.',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

/// Under four periods: the numbers, plainly, and why there is no chart.
class _ThinRecord extends StatelessWidget {
  const _ThinRecord({
    required this.series,
    required this.kind,
    required this.colour,
  });

  final List<PeriodReturn> series;
  final ReturnPeriod kind;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final word = kind.label.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in series.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.periodEnd,
                    style: TextStyle(
                      color: c.muted,
                      fontFamily: fructaFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${r.netPct >= 0 ? '+' : ''}${r.netPct.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: c.delta(r.netPct),
                    fontFamily: fructaFonts.mono,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 2),
        Text(
          series.length == 1
              ? 'One completed $word so far. Too short a record to chart, and far too short to draw a trend from.'
              : '${series.length} completed ${word}s so far. Too short a record to chart, and far too short to draw a trend from.',
          style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.series,
    required this.average,
    required this.progress,
    required this.up,
    required this.down,
    required this.text,
    required this.faint,
    required this.accent,
    required this.grid,
  });

  final List<PeriodReturn> series;
  final double? average;
  final double progress;
  final Color up;
  final Color down;
  final Color text;
  final Color faint;
  final Color accent;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    const padTop = 24.0;
    const padBottom = 26.0;
    final plot = size.height - padTop - padBottom;
    if (plot <= 0) return;

    // The range always includes zero, so the baseline is a real position on the
    // axis rather than the bottom of the canvas. Without this a set of positive
    // periods would sit on a floor that silently means "the worst quarter",
    // and the first negative period would have nowhere to go.
    var lo = 0.0;
    var hi = 0.0;
    for (final r in series) {
      if (r.netPct < lo) lo = r.netPct;
      if (r.netPct > hi) hi = r.netPct;
    }
    final a = average;
    if (a != null) {
      if (a < lo) lo = a;
      if (a > hi) hi = a;
    }
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo) * 1.16;
    final top = hi + (hi - lo) * 0.16;
    double y(double v) => padTop + (top - v) / span * plot;

    final slot = size.width / series.length;
    final barW = (slot * 0.54).clamp(6.0, 30.0);
    final zeroY = y(0);

    // Zero line, drawn only when it is inside the plot rather than sitting on
    // an edge, where it would read as a border.
    if (lo < 0) {
      canvas.drawLine(
        Offset(0, zeroY),
        Offset(size.width, zeroY),
        Paint()
          ..color = grid
          ..strokeWidth = 1,
      );
    }

    for (var i = 0; i < series.length; i++) {
      final r = series[i];
      final cx = slot * i + slot / 2;
      final full = y(r.netPct);
      // Bars grow out of the baseline, so the animation reads as accumulation
      // rather than as the whole chart sliding into place.
      final tipY = zeroY + (full - zeroY) * progress;
      final rect = Rect.fromLTRB(
        cx - barW / 2,
        tipY < zeroY ? tipY : zeroY,
        cx + barW / 2,
        tipY < zeroY ? zeroY : tipY,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = (r.netPct < 0 ? down : up).withValues(alpha: 0.92),
      );

      if (progress > 0.75) {
        final o = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
        _label(
          canvas,
          '${r.netPct.toStringAsFixed(2)}%',
          Offset(cx, (r.netPct < 0 ? rect.bottom + 4 : rect.top - 15)),
          text.withValues(alpha: o),
          10,
          FontWeight.w600,
        );
      }
      _label(
        canvas,
        _shortDate(r.periodEnd, r.period),
        Offset(cx, size.height - 15),
        faint,
        9,
        FontWeight.w400,
      );
    }

    if (a != null) {
      final ay = y(a);
      final dash = Paint()
        ..color = accent.withValues(alpha: 0.85 * progress)
        ..strokeWidth = 1.4;
      for (var x = 0.0; x < size.width; x += 11) {
        canvas.drawLine(Offset(x, ay), Offset(x + 6, ay), dash);
      }
    }
  }

  /// 'Q1 26', 'Jun 26', '2025'. Short enough that eight of them fit a phone
  /// without any of them being cut, which is why the label is rebuilt here
  /// rather than reusing the fund's long-form period label.
  static String _shortDate(String iso, ReturnPeriod p) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return switch (p) {
      ReturnPeriod.quarter => 'Q${((d.month - 1) ~/ 3) + 1} $yy',
      ReturnPeriod.year => '${d.year}',
      ReturnPeriod.half => 'H${d.month <= 6 ? 1 : 2} $yy',
      _ => '${const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][d.month - 1]} $yy',
    };
  }

  void _label(
    Canvas canvas,
    String s,
    Offset at,
    Color colour,
    double size,
    FontWeight weight,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: colour,
          fontFamily: fructaFonts.mono,
          fontSize: size,
          fontWeight: weight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress || old.series != series;
}

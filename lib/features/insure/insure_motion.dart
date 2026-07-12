import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// V8 motion primitives, shared by the insure surfaces.
///
/// Everything here is a plain implicit animation over a real value. Nothing
/// animates decoratively: an arc that fills is showing you where a grade sits
/// on a scale, and a bar that grows is showing you a share. If the datum is
/// absent the widget is absent, not zeroed.

// ── animated ring ─────────────────────────────────────────────────────────
/// A ring that sweeps to [fraction] of a full circle. Used for the GCR grade
/// and for the combined ratio, where "how far along a scale" is the message.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.fraction,
    required this.color,
    this.size = 88,
    this.stroke = 7,
    this.child,
    this.delay = const Duration(milliseconds: 140),
  });

  final double fraction; // 0..1
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                frac: v,
                color: color,
                track: c.line2,
                stroke: stroke,
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.frac,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double frac;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (frac <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * frac,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.frac != frac || o.color != color || o.track != track;
}

// ── grade scale ───────────────────────────────────────────────────────────
/// The seven-step national-scale ladder under a rating. Turns "AA+(KE)" from a
/// string into a position, which is the whole point: a retail buyer has never
/// seen a GCR grade and cannot rank it unaided.
class GradeScale extends StatelessWidget {
  const GradeScale({super.key, required this.filled, this.steps = 7, this.color});

  final int filled;
  final int steps;
  final Color? color;

  /// Maps a GCR national-scale grade to a rung. Anything unrecognised returns
  /// null and the scale simply does not render, rather than guessing a rung.
  static int? rungFor(String? grade) {
    if (grade == null) return null;
    final g = grade.toUpperCase().replaceAll('(KE)', '').trim();
    return switch (g) {
      'AAA' => 7,
      'AA+' => 7,
      'AA' => 6,
      'AA-' => 6,
      'A+' => 5,
      'A' => 5,
      'A-' => 4,
      'BBB+' => 3,
      'BBB' => 3,
      'BBB-' => 2,
      'BB+' || 'BB' || 'BB-' => 2,
      'B+' || 'B' || 'B-' => 1,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = color ?? c.up;
    return Row(
      children: [
        for (var i = 0; i < steps; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == steps - 1 ? 0 : 2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: i < filled ? 1 : 0),
                duration: Duration(milliseconds: 260 + i * 60),
                curve: Curves.easeOut,
                builder: (_, v, __) => Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Color.lerp(c.s3, tint, v),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── horizontal bar chart ──────────────────────────────────────────────────
class BarDatum {
  const BarDatum({
    required this.label,
    required this.value,
    required this.display,
    this.color,
    this.highlight = false,
    this.hatched = false,
  });

  final String label;
  final double value; // 0..1 of the track
  final String display;
  final Color? color;
  final bool highlight; // this row is the subject
  final bool hatched; // an aggregate bucket, not a single entity
}

/// A row of growing bars. [hatched] rows render striped, which is how the
/// "Others (29)" bucket says out loud that it is not one company.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.title,
    required this.bars,
    this.subtitle,
    this.foot,
    this.labelWidth = 82,
  });

  final String title;
  final String? subtitle;
  final List<BarDatum> bars;
  final String? foot;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (bars.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.4),
            ),
          ],
          const SizedBox(height: 15),
          for (var i = 0; i < bars.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == bars.length - 1 ? 0 : 11),
              child: _Bar(
                datum: bars[i],
                index: i,
                labelWidth: labelWidth,
              ),
            ),
          if (foot != null) ...[
            const SizedBox(height: 14),
            Text(
              foot!,
              style: TextStyle(
                color: c.faint,
                fontSize: 9.5,
                height: 1.6,
                fontFamily: fructaFonts.mono,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.datum,
    required this.index,
    required this.labelWidth,
  });

  final BarDatum datum;
  final int index;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = datum;
    final tint = d.color ?? (d.highlight ? c.accent : c.line2);

    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            d.label,
            style: TextStyle(
              color: d.highlight ? c.text : c.muted,
              fontSize: 11,
              fontWeight: d.highlight ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 9,
              color: c.s3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: d.value.clamp(0.0, 1.0)),
                  duration: Duration(milliseconds: 900 + index * 70),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => FractionallySizedBox(
                    widthFactor: v,
                    child: d.hatched
                        ? CustomPaint(
                            painter: _HatchPainter(base: c.s3, stripe: c.line2),
                            child: const SizedBox(height: 9),
                          )
                        : Container(
                            height: 9,
                            decoration: BoxDecoration(
                              color: tint,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          child: Text(
            d.display,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: d.highlight ? c.text : c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Diagonal stripes. Reserved for aggregate buckets, so a reader can see at a
/// glance that the bar is not one company.
class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.base, required this.stripe});
  final Color base;
  final Color stripe;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(5),
    );
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final p = Paint()
      ..color = stripe
      ..strokeWidth = 3;
    for (var x = -size.height; x < size.width + size.height; x += 8) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter o) => o.base != base || o.stripe != stripe;
}

// ── sliding segmented control ─────────────────────────────────────────────
/// The indicator travels rather than snapping, so class and cover read as one
/// dimension you move along. Disabled segments stay visible: hiding a cover
/// type would imply it does not exist, when the truth is that nobody publishes
/// a price for it.
class SlidingSegments<T> extends StatelessWidget {
  const SlidingSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onTap,
    this.enabledOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final bool Function(T)? enabledOf;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (values.isEmpty) return const SizedBox.shrink();
    final n = values.length;
    var idx = values.indexOf(selected);
    if (idx < 0) idx = 0;

    return LayoutBuilder(
      builder: (_, box) {
        final inner = box.maxWidth - 8; // 4px padding each side
        final w = inner / n;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: c.line),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: idx * w,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.text,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    SizedBox(
                      width: w,
                      child: _Seg(
                        label: labelOf(v),
                        active: v == selected,
                        enabled: enabledOf?.call(v) ?? true,
                        onTap: () => onTap(v),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = !enabled
        ? c.faint.withValues(alpha: 0.45)
        : active
            ? c.bg
            : c.muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(
            color: fg,
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

// ── staggered entrance ────────────────────────────────────────────────────
/// Fade and rise, offset by [index]. Motion that carries order, not decoration.
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + (index.clamp(0, 8)) * 45),
      curve: Curves.easeOutCubic,
      builder: (_, v, ch) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: ch),
      ),
      child: child,
    );
  }
}

// ── KPI strip ─────────────────────────────────────────────────────────────
class KpiCell {
  const KpiCell({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;
}

class KpiStrip extends StatelessWidget {
  const KpiStrip(this.cells, {super.key});
  final List<KpiCell> cells;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (cells.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cells[i].label.toUpperCase(),
                      style: TextStyle(
                        color: c.faint,
                        fontSize: 8.5,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      cells[i].value,
                      style: TextStyle(
                        color: cells[i].color ?? c.text,
                        fontFamily: fructaFonts.mono,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

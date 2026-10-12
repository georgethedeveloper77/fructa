import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Signature for building a dismissible card; call [snap] to dissolve it.
typedef ThanosBuilder = Widget Function(BuildContext context, VoidCallback snap);

/// Dissolves its child into dust, left to right, then closes the gap.
///
/// On [snap] the child is rasterised once, sampled into grains that carry the
/// child's real pixel colours, and the grains drift up and right while a mask
/// sweeps the card away behind them. [onDismissed] fires when the space has
/// closed; the caller removes the widget and persists the dismissal there.
///
/// With reduced motion the card fades out in 150 ms instead.
class ThanosDismiss extends StatefulWidget {
  const ThanosDismiss({
    super.key,
    required this.builder,
    required this.onDismissed,
    this.grain = 4,
    this.duration = const Duration(milliseconds: 1400),
  });

  final ThanosBuilder builder;
  final VoidCallback onDismissed;

  /// Grain size in logical px. Smaller is finer dust and more work per frame.
  final double grain;

  final Duration duration;

  @override
  State<ThanosDismiss> createState() => _ThanosDismissState();
}

/// One grain: where it starts, where it drifts, its colour and its delay.
class _Grain {
  const _Grain(this.origin, this.drift, this.spin, this.color, this.delay);

  final Offset origin;
  final Offset drift;
  final double spin;
  final Color color;

  /// Fraction of the dust phase before this grain lifts off.
  final double delay;
}

class _ThanosDismissState extends State<ThanosDismiss>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  List<_Grain>? _grains;
  bool _running = false;

  /// Share of the run spent on dust; the rest collapses the gap.
  static const _dustShare = 0.82;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _snap() async {
    if (_running) return;
    _running = true;
    if (reduceMotion(context)) {
      _c.duration = const Duration(milliseconds: 150);
      setState(() => _grains = const []);
      await _c.forward();
      if (mounted) widget.onDismissed();
      return;
    }
    final grains = await _sample();
    if (!mounted) return;
    setState(() => _grains = grains);
    await _c.forward();
    if (mounted) widget.onDismissed();
  }

  /// Rasterises the card and turns it into grains coloured by its pixels.
  Future<List<_Grain>> _sample() async {
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return const [];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final ui.Image image = await box.toImage(pixelRatio: dpr);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final w = image.width;
    final h = image.height;
    image.dispose();
    if (data == null) return const [];

    final size = box.size;
    final g = widget.grain;
    final rnd = math.Random(size.width.toInt() * 31 + size.height.toInt());
    final out = <_Grain>[];
    for (var y = 0.0; y < size.height; y += g) {
      for (var x = 0.0; x < size.width; x += g) {
        final px = ((x + g / 2) * dpr).clamp(0, w - 1).toInt();
        final py = ((y + g / 2) * dpr).clamp(0, h - 1).toInt();
        final o = (py * w + px) * 4;
        final a = data.getUint8(o + 3);
        if (a < 8) continue; // transparent corners leave no dust
        final color = Color.fromARGB(
          a,
          data.getUint8(o),
          data.getUint8(o + 1),
          data.getUint8(o + 2),
        );
        final r1 = rnd.nextDouble();
        final r2 = rnd.nextDouble();
        out.add(
          _Grain(
            Offset(x, y),
            Offset(30 + r1 * 90, -50 - r2 * 70),
            (r2 - 0.5) * 2.8,
            color,
            // Left to right, with a little scatter so the edge is ragged.
            (x / size.width) * 0.62 + r1 * 0.14,
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      key: _boundary,
      child: widget.builder(context, _snap),
    );
    final grains = _grains;
    if (grains == null) return card;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final dust = (t / _dustShare).clamp(0.0, 1.0);
        final close = ((t - _dustShare) / (1 - _dustShare)).clamp(0.0, 1.0);
        final shown = grains.isEmpty
            ? Opacity(opacity: 1 - dust, child: card)
            : ShaderMask(
                // A soft edge that sweeps left to right ahead of the grains.
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  final edge = dust * 1.3 - 0.15;
                  return LinearGradient(
                    colors: const [Color(0x00000000), Color(0xFF000000)],
                    stops: [
                      edge.clamp(0.0, 1.0),
                      (edge + 0.15).clamp(0.0, 1.0),
                    ],
                  ).createShader(rect);
                },
                child: card,
              );
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - Curves.easeInOutCubic.transform(close),
            child: CustomPaint(
              foregroundPainter: grains.isEmpty
                  ? null
                  : _DustPainter(grains, dust, widget.grain),
              child: IgnorePointer(child: shown),
            ),
          ),
        );
      },
    );
  }
}

/// Paints every grain at its point along its drift for progress [t].
class _DustPainter extends CustomPainter {
  _DustPainter(this.grains, this.t, this.grain);

  final List<_Grain> grains;
  final double t;
  final double grain;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final half = grain / 2;
    for (final g in grains) {
      final local = ((t - g.delay) / (1 - g.delay)).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final e = Curves.easeIn.transform(local);
      final pos = g.origin + g.drift * e;
      final s = grain * (1 - 0.6 * e);
      paint.color = g.color.withValues(alpha: g.color.a * (1 - e));
      canvas.save();
      canvas.translate(pos.dx + half, pos.dy + half);
      canvas.rotate(g.spin * e);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => old.t != t;
}

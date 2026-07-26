import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The launch splash: a market line draws itself across the screen, dipping and
/// recovering the way a yield line does, then settling on an upward rise. The
/// wordmark lifts in once the line lands. It plays while the snapshot loads in
/// the background, so it covers that time rather than blocking on it, then hands
/// off to the router. A tap skips it.
///
/// Pure animation, no data dependency, so it renders the instant the app's first
/// frame is ready.
class RealSplash extends StatefulWidget {
  const RealSplash({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<RealSplash> createState() => _RealSplashState();
}

class _RealSplashState extends State<RealSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _hold;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    // Hold a beat after the draw and wordmark, then hand off.
    _hold = Timer(const Duration(milliseconds: 2800), _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _hold?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 244,
                height: 150,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: _SplashLine(
                      Curves.easeInOutCubic.transform(_c.value),
                      line: c.accent,
                      tip: c.up,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final o = ((_c.value - 0.78) / 0.22).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: o,
                    child: Transform.translate(
                      offset: Offset(0, (1 - o) * 6),
                      child: Column(
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Fructa',
                                  style: TextStyle(
                                    color: c.text,
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Kenya\u2019s money market yields',
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 13,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws the leading [t] fraction of a smooth market line (Catmull-Rom through a
/// fixed set of normalized points), with a live dot at the drawing tip.
class _SplashLine extends CustomPainter {
  _SplashLine(this.t, {required this.line, required this.tip});

  final double t;
  final Color line;
  final Color tip;

  // Normalized points: x left to right, y where 0 is top. Dips and recovers,
  // ending high on the right.
  static const _pts = <Offset>[
    Offset(0.00, 0.78),
    Offset(0.15, 0.60),
    Offset(0.30, 0.80),
    Offset(0.45, 0.54),
    Offset(0.60, 0.68),
    Offset(0.76, 0.36),
    Offset(0.90, 0.48),
    Offset(1.00, 0.14),
  ];

  Path _buildPath(Size size) {
    Offset sc(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    final p = _pts.map(sc).toList();
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = p[i == 0 ? 0 : i - 1];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = p[i + 2 >= p.length ? p.length - 1 : i + 2];
      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final drawn = Path();
    for (final m in metrics) {
      drawn.addPath(m.extractPath(0, m.length * t), Offset.zero);
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (t > 0.02) {
      final tan = metrics.first.getTangentForOffset(metrics.first.length * t);
      if (tan != null) {
        canvas.drawCircle(tan.position, 5, Paint()..color = tip);
      }
    }
  }

  @override
  bool shouldRepaint(_SplashLine old) =>
      old.t != t || old.line != line || old.tip != tip;
}

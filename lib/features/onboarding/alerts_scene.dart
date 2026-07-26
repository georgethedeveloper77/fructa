import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/snapshot_providers.dart';
import 'notification_permission.dart';

/// Final onboarding scene: "We watch the rates so you do not." The signature is
/// a live line chart, a rate series that draws on, then keeps a pulsing tip
/// going, the same never-still quality as the ECharts charts on the landing
/// page. It says "we are watching, right now" without a word.
///
/// Primary CTA requests OS notification permission, then shows the confirmation
/// sheet and completes. "Maybe later" completes without prompting.
///
/// Two controllers: a one-shot draw and a repeating pulse. Both are disposed,
/// and this scene lives under AnimatedSwitcher, not an IndexedStack, so there is
/// no TickerMode toggling to trigger the deactivated-ticker crash. The repeat is
/// safe on this route.
class AlertsScene extends ConsumerStatefulWidget {
  const AlertsScene({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<AlertsScene> createState() => _AlertsSceneState();
}

class _AlertsSceneState extends ConsumerState<AlertsScene>
    with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  late final Animation<double> _drawC = CurvedAnimation(
    parent: _draw,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _draw.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final request = ref.read(notificationPermissionProvider);
    final granted = await request();
    if (!context.mounted) return;
    await _showAlertsOnSheet(context, granted: granted);
    if (context.mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider); // admin-controlled copy

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Rail(step: 2),
              const SizedBox(height: 22),
              Text(
                'ALERTS',
                style: TextStyle(
                  color: c.faint,
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                cfg.string(
                  'onboarding.headline',
                  'We watch the rates\nso you do not',
                ),
                style: TextStyle(
                  fontFamily: fructaFonts.mono,
                  fontSize: 28,
                  height: 1.14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                cfg.string(
                  'onboarding.body',
                  'Get a nudge when a money market rate moves, a T-bill auction '
                      'prints, or a saved comparison flips its leader.',
                ),
                style: TextStyle(fontSize: 14.5, height: 1.5, color: c.muted),
              ),

              // The live line. Draws on once, then the tip keeps pulsing.
              const SizedBox(height: 24),
              SizedBox(
                height: 170,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_draw, _pulse]),
                  builder: (_, _) => CustomPaint(
                    painter: _AlertChartPainter(
                      drawP: _drawC.value,
                      pulseT: _pulse.value,
                      line: c.accent,
                      fill: c.accent,
                      tip: c.up,
                      grid: c.line,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _turnOn(context, ref),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(cfg.string('onboarding.cta', 'Turn on alerts')),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: widget.onComplete,
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: Text(cfg.string('onboarding.later', 'Maybe later')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rising rate series that draws on, with a dashed alert level and a pulsing
/// live tip. The tip pulse is the never-still part: a radar ping that says the
/// line is being watched in real time.
class _AlertChartPainter extends CustomPainter {
  _AlertChartPainter({
    required this.drawP,
    required this.pulseT,
    required this.line,
    required this.fill,
    required this.tip,
    required this.grid,
  });

  final double drawP; // 0..1 line draw progress
  final double pulseT; // 0..1 radar ping phase
  final Color line;
  final Color fill;
  final Color tip;
  final Color grid;

  // A rate series, higher value nearer the top (smaller y fraction).
  static const _pts = <double>[
    0.74,
    0.70,
    0.76,
    0.60,
    0.63,
    0.48,
    0.52,
    0.40,
    0.34,
    0.27,
    0.20,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = _pts.length;
    Offset pt(int i) => Offset(w * i / (n - 1), h * _pts[i]);

    final full = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < n; i++) {
      full.lineTo(pt(i).dx, pt(i).dy);
    }

    final metric = full.computeMetrics().first;
    final len = metric.length * drawP.clamp(0.0, 1.0);
    final drawn = len > 0 ? metric.extractPath(0, len) : Path();
    final tipPos = len > 0
        ? (metric.getTangentForOffset(len)?.position ?? pt(0))
        : pt(0);

    // Dashed alert level.
    final ty = h * 0.5;
    final dash = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var x = 0.0; x < w; x += 10) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 5, w), ty), dash);
    }

    // Area under the drawn portion.
    if (len > 0) {
      final area = Path.from(drawn)
        ..lineTo(tipPos.dx, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [fill.withValues(alpha: 0.22), fill.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }

    // The line.
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Live pulsing tip, once the line has mostly arrived.
    if (drawP > 0.55) {
      final appear = ((drawP - 0.55) / 0.45).clamp(0.0, 1.0);
      canvas.drawCircle(
        tipPos,
        4 + pulseT * 12,
        Paint()..color = tip.withValues(alpha: (1 - pulseT) * 0.35 * appear),
      );
      canvas.drawCircle(
        tipPos,
        4,
        Paint()..color = tip.withValues(alpha: appear),
      );
    }
  }

  @override
  bool shouldRepaint(_AlertChartPainter old) =>
      old.drawP != drawP ||
      old.pulseT != pulseT ||
      old.line != line ||
      old.tip != tip ||
      old.fill != fill;
}

Future<void> _showAlertsOnSheet(BuildContext context, {required bool granted}) {
  final c = context.c;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.s1,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: c.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 44,
              color: granted ? c.up : c.muted,
            ),
            const SizedBox(height: 16),
            Text(
              granted ? 'Alerts are on' : 'No problem',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              granted
                  ? 'You will hear from us only when something meaningful '
                        'moves. Fine-tune everything in Settings.'
                  : 'You can switch alerts on any time from Settings, under '
                        'Notifications.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: c.muted),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('See the markets'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Three-segment progress rail. [step] is the 0-based active index.
class _Rail extends StatelessWidget {
  const _Rail({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i <= step ? c.accent : c.s3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

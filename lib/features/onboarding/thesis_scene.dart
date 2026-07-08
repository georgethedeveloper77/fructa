import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import 'anim.dart';

/// Onboarding opener — the product's thesis, not a logo splash. The current
/// top money-market yield counts up while its curve draws in; accent-tinted, so
/// it already reflects the app's look. [onNext] advances; [onSkip] is the
/// power-user path straight past setup.
class ThesisScene extends ConsumerStatefulWidget {
  const ThesisScene({super.key, required this.onNext, required this.onSkip});
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  ConsumerState<ThesisScene> createState() => _ThesisSceneState();
}

class _ThesisSceneState extends ConsumerState<ThesisScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  late final Animation<double> _num = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.0, 0.78, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _draw = CurvedAnimation(
    parent: _ctrl,
    curve: const Interval(0.1, 1.0, curve: Curves.easeInOutCubic),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double? _topRate(List<Fund> funds) {
    double? m;
    for (final f in funds) {
      final r = f.currentRate;
      if (f.retail && f.showsYield && r != null) {
        if (m == null || r > m) m = r;
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final funds = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final top = _topRate(funds);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Row(
                children: [
                  const LottieHero(
                    asset: 'assets/lottie/coin.json',
                    size: 50,
                    fallback: _Coin(size: 50),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Welcome to Fructa',
                    style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: c.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.up,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'LIVE · TODAY',
                    style: TextStyle(
                      color: c.up,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (top != null)
                AnimatedBuilder(
                  animation: _num,
                  builder: (_, __) => Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: (top * _num.value).toStringAsFixed(2)),
                        TextSpan(
                          text: '%',
                          style: TextStyle(fontSize: 34, color: c.muted),
                        ),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      fontSize: 74,
                      height: 0.98,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -3,
                      color: c.text,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                cfg.string(
                  'onboarding.thesis',
                  "Kenya's top money-market rate, right now. fructa puts every "
                      'yield  MMFs, T-bills, bonds, SACCOs in one place.',
                ),
                style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 118,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (_, __) => CustomPaint(
                    painter: _CurvePainter(
                      progress: _draw.value,
                      color: c.accent,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(cfg.string('onboarding.start', 'Get started')),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(foregroundColor: c.faint),
                  child: Text(
                    cfg.string('onboarding.skip', 'I just want the rates'),
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A minted KES coin — drawn, never an emoji.
class _Coin extends StatelessWidget {
  const _Coin({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFFF6D66E), Color(0xFFC99A2E)],
        ),
      ),
      child: Text(
        'KES',
        style: TextStyle(
          fontFamily: fructaFonts.mono,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF5A3F0E),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.86)
      ..cubicTo(w * 0.18, h * 0.80, w * 0.30, h * 0.66, w * 0.44, h * 0.52)
      ..cubicTo(w * 0.58, h * 0.38, w * 0.68, h * 0.22, w * 0.84, h * 0.14)
      ..lineTo(w, h * 0.05);

    final metric = path.computeMetrics().first;
    final len = metric.length * progress.clamp(0.0, 1.0);
    if (len <= 0) return;
    final line = metric.extractPath(0, len);
    final tan = metric.getTangentForOffset(len);
    final endX = tan?.position.dx ?? 0;

    final fill = Path.from(line)
      ..lineTo(endX, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.progress != progress || old.color != color;
}

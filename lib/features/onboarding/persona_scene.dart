import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/snapshot_providers.dart';

/// Onboarding stage 2, the fork. Not a setting: it decides where the user lands
/// and the closing tone. [onPick] receives 'rates' or 'learn'.
///
/// The signature is a forking yield curve drawn in the app's own idiom rather
/// than two stacked cards. A trunk rises and splits at a node into two
/// branches: gold climbs steeply (the user who wants the rates now), sky climbs
/// in a gentle rise (the user being taught). Pressing a choice row lights its
/// branch and dims the other, so the pairing of choice to direction reads
/// without a word of explanation. The whole thing recolors with the accent
/// because it paints from `c.accent`, so nothing here is a baked colour.
///
/// SingleTickerProviderStateMixin is deliberate and safe here: this is a
/// one-shot forward() that completes before the user ever navigates away, and
/// the scene is not inside a TickerMode-toggling ancestor (no IndexedStack).
/// That is the exact condition the insurance-strip ticker crash needs, and it
/// is absent on this route.
class PersonaScene extends ConsumerStatefulWidget {
  const PersonaScene({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  ConsumerState<PersonaScene> createState() => _PersonaSceneState();
}

class _PersonaSceneState extends ConsumerState<PersonaScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  // Draw-on stagger: trunk first, then both branches, then the node and the
  // endpoint dots fade up.
  late final Animation<double> _trunk = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _branch = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.35, 0.82, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _dots = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.80, 1.0, curve: Curves.easeOut),
  );

  // Which branch is currently pressed: 'rates' | 'learn' | null.
  String? _hi;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _press(String? kind) => setState(() => _hi = kind);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final sky = fructaAccent.sky.color;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Rail(step: 0),
              const SizedBox(height: 22),
              Text(
                'A QUICK FORK',
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
                  'onboarding.forkTitle',
                  'Where should\nwe start you?',
                ),
                style: TextStyle(
                  fontFamily: fructaFonts.mono,
                  fontSize: 30,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                cfg.string(
                  'onboarding.forkSub',
                  "This only changes where you land. Everything stays open to you either way.",
                ),
                style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
              ),

              // The forking curve. This is the one animated element on the
              // scene; the header and rows stay still.
              const SizedBox(height: 14),
              SizedBox(
                height: 200,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (_, __) => CustomPaint(
                    painter: _ForkPainter(
                      trunkP: _trunk.value,
                      branchP: _branch.value,
                      dotsP: _dots.value,
                      highlight: _hi,
                      gold: c.accent,
                      sky: sky,
                      grid: c.line,
                      trunkColor: c.muted,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              _Choice(
                kind: 'rates',
                color: c.accent,
                title: cfg.string(
                  'onboarding.ratesTitle',
                  'Straight to the rates',
                ),
                body: cfg.string(
                  'onboarding.ratesBody',
                  'I know my way around. Open the live market.',
                ),
                pressed: _hi == 'rates',
                onPress: _press,
                onPick: widget.onPick,
              ),
              const SizedBox(height: 10),
              _Choice(
                kind: 'learn',
                color: sky,
                badge: 'new here',
                title: cfg.string(
                  'onboarding.learnTitle',
                  'Explain it as I go',
                ),
                body: cfg.string(
                  'onboarding.learnBody',
                  'A quick 2 minute intro to money market funds.',
                ),
                pressed: _hi == 'learn',
                onPress: _press,
                onPick: widget.onPick,
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet, hairline choice row. Pressing it reports the press up (so the curve
/// can light the matching branch) and commits the pick on release.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.kind,
    required this.color,
    required this.title,
    required this.body,
    required this.pressed,
    required this.onPress,
    required this.onPick,
    this.badge,
  });

  final String kind; // 'rates' | 'learn'
  final Color color;
  final String title;
  final String body;
  final bool pressed;
  final ValueChanged<String?> onPress;
  final ValueChanged<String> onPick;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTapDown: (_) => onPress(kind),
      onTapCancel: () => onPress(null),
      onTapUp: (_) {
        onPress(null);
        onPick(kind);
      },
      child: AnimatedScale(
        scale: pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: pressed ? c.s2 : c.s1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: pressed ? color.withValues(alpha: 0.5) : c.line,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  // Branch node: echoes the curve endpoint colour.
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 14),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.14),
                          blurRadius: 0,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: color.withValues(alpha: 0.8),
                  ),
                ],
              ),
              if (badge != null)
                Positioned(
                  top: -3,
                  right: 30,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w700,
                      ),
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

/// Paints the forking yield curve with a draw-on progress per segment and a
/// press highlight. All geometry is normalised to the canvas, so it scales with
/// whatever height the scene gives it.
class _ForkPainter extends CustomPainter {
  _ForkPainter({
    required this.trunkP,
    required this.branchP,
    required this.dotsP,
    required this.highlight,
    required this.gold,
    required this.sky,
    required this.grid,
    required this.trunkColor,
  });

  final double trunkP;
  final double branchP;
  final double dotsP;
  final String? highlight; // 'rates' | 'learn' | null
  final Color gold;
  final Color sky;
  final Color grid;
  final Color trunkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Faint chart grid.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final fy in const [0.28, 0.54, 0.80]) {
      canvas.drawLine(Offset(0, h * fy), Offset(w, h * fy), gridPaint);
    }

    final fork = Offset(w * 0.44, h * 0.64);

    final trunk = Path()
      ..moveTo(w * 0.02, h * 0.9)
      ..cubicTo(w * 0.18, h * 0.86, w * 0.30, h * 0.80, fork.dx, fork.dy);

    // Gold branch: steep, ambitious.
    final goldPath = Path()
      ..moveTo(fork.dx, fork.dy)
      ..cubicTo(w * 0.60, h * 0.55, w * 0.72, h * 0.36, w * 0.96, h * 0.12);

    // Sky branch: a gentle, guided rise.
    final skyPath = Path()
      ..moveTo(fork.dx, fork.dy)
      ..cubicTo(w * 0.62, h * 0.62, w * 0.74, h * 0.60, w * 0.96, h * 0.55);

    _drawPartial(
      canvas,
      trunk,
      trunkP,
      Paint()
        ..color = trunkColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final goldAlpha = highlight == 'learn' ? 0.28 : 1.0;
    final skyAlpha = highlight == 'rates' ? 0.28 : 1.0;
    final goldWidth = highlight == 'rates' ? 3.6 : 2.5;
    final skyWidth = highlight == 'learn' ? 3.6 : 2.5;

    _drawPartial(
      canvas,
      skyPath,
      branchP,
      Paint()
        ..color = sky.withValues(alpha: skyAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = skyWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    _drawPartial(
      canvas,
      goldPath,
      branchP,
      Paint()
        ..color = gold.withValues(alpha: goldAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = goldWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Node + endpoints fade in last.
    if (dotsP > 0) {
      final da = dotsP.clamp(0.0, 1.0);
      canvas.drawCircle(
        fork,
        4.5,
        Paint()..color = trunkColor.withValues(alpha: 0.9 * da),
      );
      canvas.drawCircle(
        _endpoint(goldPath),
        5,
        Paint()..color = gold.withValues(alpha: goldAlpha * da),
      );
      canvas.drawCircle(
        _endpoint(skyPath),
        5,
        Paint()..color = sky.withValues(alpha: skyAlpha * da),
      );
    }
  }

  void _drawPartial(Canvas canvas, Path path, double t, Paint paint) {
    final tt = t.clamp(0.0, 1.0);
    if (tt <= 0) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * tt), paint);
    }
  }

  Offset _endpoint(Path path) {
    final m = path.computeMetrics().last;
    return m.getTangentForOffset(m.length)!.position;
  }

  @override
  bool shouldRepaint(_ForkPainter old) =>
      old.trunkP != trunkP ||
      old.branchP != branchP ||
      old.dotsP != dotsP ||
      old.highlight != highlight ||
      old.gold != gold ||
      old.sky != sky;
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

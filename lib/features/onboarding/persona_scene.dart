import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/snapshot_providers.dart';

/// Onboarding stage 2 — the fork. Not a setting: it decides where the user
/// lands and the closing tone. [onPick] receives 'rates' or 'learn'.
///
/// The two paths carry distinct colour identities (gold = rates, sky = learn)
/// so the choice reads at a glance; header and cards rise in on a short stagger.
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
    duration: const Duration(milliseconds: 720),
  )..forward();

  Animation<double> _at(double b, double e) => CurvedAnimation(
      parent: _intro, curve: Interval(b, e, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _rise(Animation<double> a, Widget child) => AnimatedBuilder(
        animation: a,
        builder: (_, __) => Opacity(
          opacity: a.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - a.value) * 18),
            child: child,
          ),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final sky = fructaAccent.sky;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Rail(step: 0),
              const Spacer(flex: 2),
              _rise(
                _at(0.0, 0.55),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A QUICK FORK',
                        style: TextStyle(
                            color: c.faint,
                            fontSize: 11,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(
                      cfg.string(
                          'onboarding.forkTitle', 'Where should we\nstart you?'),
                      style: TextStyle(
                          fontFamily: fructaFonts.mono,
                          fontSize: 30,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: c.text),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      cfg.string('onboarding.forkSub',
                          "This only changes where you land — everything's open to you either way."),
                      style:
                          TextStyle(color: c.muted, fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _rise(
                _at(0.2, 0.8),
                _PathCard(
                  icon: Icons.insights_rounded,
                  accent: c.accent,
                  ink: c.onAccent,
                  title: cfg.string(
                      'onboarding.ratesTitle', 'Straight to the rates'),
                  body: cfg.string('onboarding.ratesBody',
                      'I know my way around. Open the live market, ranked by yield.'),
                  onTap: () => widget.onPick('rates'),
                ),
              ),
              const SizedBox(height: 14),
              _rise(
                _at(0.35, 1.0),
                _PathCard(
                  icon: Icons.school_rounded,
                  accent: sky.color,
                  ink: sky.onColor,
                  badge: 'NEW HERE?',
                  title:
                      cfg.string('onboarding.learnTitle', 'Explain it as I go'),
                  body: cfg.string('onboarding.learnBody',
                      "We'll start you with a 2-minute lesson, then you can tap any rate to see what it means."),
                  onTap: () => widget.onPick('learn'),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathCard extends StatefulWidget {
  const _PathCard({
    required this.icon,
    required this.accent,
    required this.ink,
    required this.title,
    required this.body,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final Color accent;
  final Color ink;
  final String title;
  final String body;
  final VoidCallback onTap;
  final String? badge;

  @override
  State<_PathCard> createState() => _PathCardState();
}

class _PathCardState extends State<_PathCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = widget.accent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.12), c.s2],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent, accent.withValues(alpha: 0.72)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                            color: accent.withValues(alpha: 0.28),
                            blurRadius: 16,
                            spreadRadius: -2)
                      ],
                    ),
                    child: Icon(widget.icon, color: widget.ink, size: 27),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: TextStyle(
                                color: c.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(widget.body,
                            style: TextStyle(
                                color: c.muted, fontSize: 13.5, height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 15, color: accent.withValues(alpha: 0.8)),
                ],
              ),
              if (widget.badge != null)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(widget.badge!,
                        style: TextStyle(
                            color: accent,
                            fontSize: 9.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

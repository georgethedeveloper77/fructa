import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/snapshot_providers.dart';
import 'anim.dart';

/// Onboarding stage 2 — the fork. Not a setting: it decides where the user
/// lands and the closing tone. [onPick] receives 'rates' or 'learn'.
class PersonaScene extends ConsumerWidget {
  const PersonaScene({super.key, required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Rail(step: 0),
              const SizedBox(height: 16),
              Center(
                child: LottieHero(
                  asset: 'assets/lottie/welcome.json',
                  size: 96,
                  fallback: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.auto_awesome_rounded,
                        color: c.accent, size: 42),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('A QUICK FORK',
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                cfg.string('onboarding.forkTitle', 'Where should we\nstart you?'),
                style: TextStyle(
                    fontFamily: fructaFonts.mono,
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: c.text),
              ),
              const SizedBox(height: 8),
              Text(
                cfg.string('onboarding.forkSub',
                    "This only changes where you land — everything's open to you either way."),
                style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 24),
              _PersonaCard(
                icon: Icons.trending_up_rounded,
                title:
                    cfg.string('onboarding.ratesTitle', 'Straight to the rates'),
                body: cfg.string('onboarding.ratesBody',
                    'I know my way around. Open the live market, ranked by yield.'),
                onTap: () => onPick('rates'),
              ),
              const SizedBox(height: 13),
              _PersonaCard(
                icon: Icons.school_outlined,
                title:
                    cfg.string('onboarding.learnTitle', 'Explain it as I go'),
                body: cfg.string('onboarding.learnBody',
                    "New to this? We'll start you with a 2-minute lesson, then you can tap any rate to see what it means."),
                onTap: () => onPick('learn'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.s3,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: c.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(body,
                      style:
                          TextStyle(color: c.muted, fontSize: 13, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded, size: 15, color: c.faint),
          ],
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

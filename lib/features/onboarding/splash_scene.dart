import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';

/// Opening splash: the market as a live leaderboard. The top money-market funds
/// race in as bars the moment the snapshot lands, then it hands off to the first
/// onboarding screen. A brand moment that is also information, so a new user
/// knows what to expect before touching anything.
///
/// It auto-advances a beat after the bars settle; a tap anywhere advances
/// immediately. If rates are slow to arrive it still moves on after a short
/// ceiling, into the gap scene, which shows its own loading state. Nothing here
/// is fabricated: with no funds yet it shows a quiet spinner, never invented
/// bars.
class SplashScene extends ConsumerStatefulWidget {
  const SplashScene({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<SplashScene> createState() => _SplashSceneState();
}

class _SplashSceneState extends ConsumerState<SplashScene>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily: a late-initialized controller whose first
  // access is dispose() would run createTicker (and its TickerMode ancestor
  // lookup) on a deactivated context, which is the 'deactivated widget's
  // ancestor' crash. Building it in initState keeps that lookup on an active
  // element.
  late final AnimationController _race;

  // One timer: the splash shows for this long, then hands off. A tap advances
  // sooner. Five seconds so the leaderboard is readable, not a flash.
  Timer? _timer;
  bool _raced = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _race = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _timer = Timer(const Duration(milliseconds: 5000), _finish);
  }

  void _startRace() {
    if (_raced || !mounted) return;
    _raced = true;
    _race.forward();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _race.dispose();
    super.dispose();
  }

  List<Fund> _top(List<Fund> funds) {
    final mmf =
        funds
            .where(
              (f) =>
                  f.retail &&
                  f.showsYield &&
                  f.fundType == 'mmf' &&
                  f.currentRate != null,
            )
            .toList()
          ..sort(
            (a, b) => (b.currentRate ?? 0).compareTo(a.currentRate ?? 0),
          );
    return mmf.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
    final top = _top(funds);

    // Kick the race once, the frame after real data first appears.
    if (top.isNotEmpty && !_raced) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startRace());
    }

    final maxRate = top.isEmpty ? 1.0 : (top.first.currentRate ?? 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      'LIVE RATES \u00B7 TODAY',
                      style: TextStyle(
                        color: c.up,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Today\u2019s top\nmoney market rates',
                  style: TextStyle(
                    fontFamily: fructaFonts.mono,
                    fontSize: 28,
                    height: 1.12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The market, live. Here is what is leading.',
                  style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: top.isEmpty
                      ? Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: c.muted,
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _race,
                          builder: (_, __) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < top.length; i++) ...[
                                _SplashBar(
                                  rank: i + 1,
                                  name: top[i].name.split(' ').first,
                                  rate: top[i].currentRate ?? 0,
                                  factor:
                                      ((top[i].currentRate ?? 0) / maxRate)
                                          .clamp(0.0, 1.0) *
                                      Curves.easeOutCubic.transform(
                                        (_race.value - i * 0.08).clamp(0.0, 1.0),
                                      ),
                                  bright: i < 2,
                                ),
                                if (i < top.length - 1)
                                  const SizedBox(height: 14),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One leaderboard bar: rank, a name-over-fill track, and the rate. Brighter
/// accent for the leaders, a step down for the rest.
class _SplashBar extends StatelessWidget {
  const _SplashBar({
    required this.rank,
    required this.name,
    required this.rate,
    required this.factor,
    required this.bright,
  });

  final int rank;
  final String name;
  final double rate;
  final double factor;
  final bool bright;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            '$rank',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              color: c.faint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 30,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: c.s1,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: factor.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: bright
                              ? c.accent
                              : c.accent.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        name,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${rate.toStringAsFixed(2)}%',
          style: TextStyle(
            fontFamily: fructaFonts.mono,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: c.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

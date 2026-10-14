import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_scaffold.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart' show settingsBoxProvider;
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// What the whole book earns in a day, in basis points of its value.
///
/// Worked out from each holding's current rate (net where tax is withheld)
/// weighted by its value, so it is meaningful on the day a holding is added,
/// unlike a since-added change that reads +0.00% until interest accrues.
/// Basis points never reveal an amount, keeping Today free of balances.
final bookDailyBpsProvider = Provider<double?>((ref) {
  final holdings = ref.watch(holdingsProvider);
  if (holdings.isEmpty) return null;
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final fx = ref.watch(usdKesProvider);
  var weight = 0.0;
  var rateSum = 0.0;
  for (final h in holdings) {
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    final r = s?.ratePercent;
    if (r == null || h.balance <= 0) continue;
    final net = s!.taxFree ? r : r * (1 - wht / 100);
    // Weight in KES so a USD holding counts at its shilling size.
    final w = h.currency == 'USD' ? h.balance * (fx ?? 0) : h.balance;
    weight += w;
    rateSum += net * w;
  }
  if (weight <= 0) return null;
  // percent a year → basis points a day.
  return rateSum / weight / 365 * 100;
});

/// A small bubble docked bottom right on Today that waits to be popped.
///
/// It floats with a gentle bob. A tap bursts it into sparks and shows one
/// line, "Your portfolio, today: +2.5 bps", which opens Portfolio. Once
/// popped it stays away until tomorrow. Nothing moves when the system asks
/// for reduced motion; the bubble simply sits there.
class PortfolioBubble extends ConsumerStatefulWidget {
  const PortfolioBubble({super.key});

  @override
  ConsumerState<PortfolioBubble> createState() => _PortfolioBubbleState();
}

class _PortfolioBubbleState extends ConsumerState<PortfolioBubble>
    with TickerProviderStateMixin {
  static const _key = 'bubble_popped_on';

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _popped = false;
  bool _showLine = false;

  String get _today {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  void initState() {
    super.initState();
    _popped = ref.read(settingsBoxProvider).get(_key) == _today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _pop() async {
    HapticFeedback.lightImpact();
    await ref.read(settingsBoxProvider).put(_key, _today);
    setState(() {
      _popped = true;
      _showLine = true;
    });
    _burst.forward(from: 0);
    // The line clears itself; the user can also tap it or swipe on.
    Future.delayed(const Duration(seconds: 7), () {
      if (mounted) setState(() => _showLine = false);
    });
  }

  void _openPortfolio() {
    setState(() => _showLine = false);
    ref.read(selectedTabProvider.notifier).state = AppTab.portfolio;
  }

  @override
  Widget build(BuildContext context) {
    final bps = ref.watch(bookDailyBpsProvider);
    if (bps == null) return const SizedBox.shrink();
    final c = context.c;
    final label = '+${bps.toStringAsFixed(1)} bps';
    final n = ref.watch(holdingsProvider).length;

    // A fixed-height band: Today places this with left, right and bottom
    // only, which leaves its height unbounded, and a Stack of only positioned
    // children cannot size itself to an infinite height. Without this the
    // bubble never laid out and Flutter's semantics pass met it still dirty.
    return SizedBox(
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_showLine)
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: _Line(
                label: label,
                holdings: n,
                onTap: _openPortfolio,
                onClose: () => setState(() => _showLine = false),
              ),
            ),
          // Sparks from where the bubble was.
          Positioned(
            right: 18,
            bottom: 0,
            width: 74,
            height: 74,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _burst,
                  builder: (_, _) => _burst.value == 0 || _burst.value == 1
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          painter: _Sparks(_burst.value, c.up, c.accent),
                        ),
                ),
              ),
            ),
          ),
          if (!_popped)
            Positioned(
              right: 18,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _bob,
                builder: (_, child) => Transform.translate(
                  offset: Offset(
                    0,
                    -5 * Curves.easeInOut.transform(_bob.value),
                  ),
                  child: child,
                ),
                child: Semantics(
                  button: true,
                  label: t('today.bubble.a11y', {'v': label}),
                  child: GestureDetector(
                    onTap: _pop,
                    child: Container(
                      width: 74,
                      height: 74,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.36, -0.44),
                          colors: [
                            c.text.withValues(alpha: c.isDark ? 0.45 : 0.0),
                            c.up.withValues(alpha: c.isDark ? 0.32 : 0.22),
                            c.up.withValues(alpha: c.isDark ? 0.55 : 0.40),
                          ],
                          stops: const [0, 0.58, 1],
                        ),
                        border: Border.all(
                          color: c.up.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: c.up.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            label,
                            style: fructaFonts.numeric(
                              color: c.text,
                              size: 15,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.holdings,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final int holdings;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.s1,
      elevation: 8,
      shadowColor: c.bg.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('today.bubble.title'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t(
                        holdings == 1
                            ? 'today.bubble.subOne'
                            : 'today.bubble.subMany',
                        {'v': label, 'n': '$holdings'},
                      ),
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t('common.close'),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 18, color: c.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Twelve sparks flying out and fading.
class _Sparks extends CustomPainter {
  _Sparks(this.t, this.a, this.b);

  final double t;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final e = Curves.easeOut.transform(t);
    for (var i = 0; i < 12; i++) {
      final ang = i / 12 * math.pi * 2;
      final r = (36 + (i % 3) * 14) * e;
      final p = center + Offset(math.cos(ang) * r, math.sin(ang) * r);
      canvas.drawCircle(
        p,
        (3 + (i % 3)) * (1 - e * 0.6),
        Paint()..color = (i.isEven ? a : b).withValues(alpha: 1 - e),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Sparks old) => old.t != t;
}

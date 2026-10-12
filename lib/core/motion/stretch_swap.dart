import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Plays a squash-and-spring whenever [value] changes.
///
/// The child is scaled wide and short, overshoots tall, then settles, which
/// reads as the new number landing rather than the old one being repainted.
/// Use for values the user changed themselves; market-driven changes use
/// [Glitch] instead so the two causes look different.
class StretchSwap extends StatefulWidget {
  const StretchSwap({
    super.key,
    required this.value,
    required this.child,
    this.alignment = Alignment.bottomLeft,
    this.duration = const Duration(milliseconds: 600),
    this.playOnMount = false,
  });

  /// Identity of what is shown. A different value replays the effect.
  final Object? value;

  final Widget child;

  /// Anchor of the scale, so a left-aligned headline stretches from its
  /// baseline instead of drifting.
  final Alignment alignment;

  final Duration duration;

  /// Play once on first build as well (for totals revealed on screen entry).
  final bool playOnMount;

  @override
  State<StretchSwap> createState() => _StretchSwapState();
}

class _StretchSwapState extends State<StretchSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  // Squash wide, overshoot tall, settle.
  static final _sx = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.32, end: 0.95), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 45),
  ]);
  static final _sy = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.07), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 45),
  ]);
  static final _op = Tween<double>(begin: 0.25, end: 1.0)
      .chain(CurveTween(curve: const Interval(0, 0.55)));

  @override
  void initState() {
    super.initState();
    if (widget.playOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void didUpdateWidget(covariant StretchSwap old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _play();
  }

  void _play() {
    if (!mounted || reduceMotion(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: _op.transform(t),
          child: Transform(
            alignment: widget.alignment,
            transform: Matrix4.diagonal3Values(
              _sx.transform(t),
              _sy.transform(t),
              1,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

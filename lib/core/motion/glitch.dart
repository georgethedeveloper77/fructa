import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Splits [child] into two colour channels for a moment whenever [trigger]
/// changes, then settles.
///
/// Meant for values the market changed (a new rate print), so a live update is
/// noticed without a toast. Four hard frames, no easing: a glitch that eases
/// reads as a wobble. [a] and [b] are the channel colours; pass the accent and
/// `c.down` from the theme so the effect follows light and dark.
class Glitch extends StatefulWidget {
  const Glitch({
    super.key,
    required this.trigger,
    required this.child,
    required this.a,
    required this.b,
    this.duration = const Duration(milliseconds: 520),
  });

  /// A new value replays the effect. The first build never glitches.
  final Object? trigger;

  final Widget child;
  final Color a;
  final Color b;
  final Duration duration;

  @override
  State<Glitch> createState() => _GlitchState();
}

/// One frame of the glitch: channel offsets and the band that tears.
class _Frame {
  const _Frame(this.shift, this.dx, this.top, this.bottom);

  /// Horizontal split between the two colour channels, logical px.
  final double shift;

  /// Offset of the torn band.
  final double dx;

  /// Band edges as fractions of height.
  final double top;
  final double bottom;
}

const _frames = <_Frame>[
  _Frame(3, 1, 0.0, 0.55),
  _Frame(-4, -2, 0.40, 0.92),
  _Frame(2, 2, 0.12, 0.70),
  _Frame(-1, 0, 0.0, 1.0),
];

class _GlitchState extends State<Glitch> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant Glitch old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !reduceMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _tinted(Widget child, Color color) => ColorFiltered(
    colorFilter: ColorFilter.mode(
      color.withValues(alpha: 0.85),
      BlendMode.srcIn,
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        // Settled: render the child untouched, no extra layers.
        if (_c.value >= 1 || _c.value <= 0) return child!;
        // The last ~45% of the run is the clean landing.
        final i = (_c.value / 0.55 * _frames.length).floor();
        if (i >= _frames.length) return child!;
        final f = _frames[i];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: Offset(f.shift, 0),
              child: _tinted(child!, widget.a),
            ),
            Transform.translate(
              offset: Offset(-f.shift, 0),
              child: _tinted(child, widget.b),
            ),
            ClipRect(
              clipper: _BandClipper(f.top, f.bottom),
              child: Transform.translate(offset: Offset(f.dx, 0), child: child),
            ),
          ],
        );
      },
    );
  }
}

/// Clips to a horizontal band between [top] and [bottom] (fractions).
class _BandClipper extends CustomClipper<Rect> {
  const _BandClipper(this.top, this.bottom);

  final double top;
  final double bottom;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -8,
    size.height * top,
    size.width + 8,
    size.height * bottom,
  );

  @override
  bool shouldReclip(covariant _BandClipper old) =>
      old.top != top || old.bottom != bottom;
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The page shell every insure screen was missing.
///
/// The V8 mockup has no Material app bar. It has a translucent nav that the
/// content scrolls UNDER, and a head block inside the scroll view: a kicker
/// with a live node, a 29px display title, and one line of subtitle. That head
/// block is the first 120px of every frame and it is the loudest thing on it.
///
/// The pages were opening with a 16px AppBar title instead, which is why they
/// read as a Material app rather than as the design: where the mockup shouts
/// the subject of the screen, the app whispered it in chrome.
///
/// The nav title is the fallback, not the headline. It fades in only once the
/// real headline has scrolled away, so the screen is never without a name and
/// never has two.

// ── live node ─────────────────────────────────────────────────────────────

/// The pulsing node in a kicker. It means the figure beside it is live, so it
/// only ever appears where the figure actually is: a count of published rates
/// moves, a register year does not.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color, this.pulse = true});

  final Color? color;
  final bool pulse;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant LiveDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? context.c.up;

    // The ring blooms 7px past the dot, so the box is sized for the bloom and
    // not for the dot. Sizing it 5x5 would let the ring paint outside its own
    // bounds, where any clipping ancestor is free to shear it.
    return SizedBox(
      width: 16,
      height: 16,
      child: widget.pulse
          ? AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) =>
                  CustomPaint(painter: _PulsePainter(t: _ctrl.value, color: tint)),
            )
          : CustomPaint(painter: _PulsePainter(t: 1, color: tint)),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.t, required this.color});

  final double t; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);

    // The CSS keyframe: the ring spreads to 7px over the first 70% of the
    // cycle, fading as it goes, then the last 30% is dead time before it
    // starts again. A ring that pulsed continuously would read as a spinner.
    final phase = (t / 0.7).clamp(0.0, 1.0);
    if (phase < 1) {
      canvas.drawCircle(
        centre,
        2.5 + 7 * phase,
        Paint()..color = color.withValues(alpha: 0.5 * (1 - phase)),
      );
    }
    canvas.drawCircle(centre, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.t != t || o.color != color;
}

// ── head block ────────────────────────────────────────────────────────────

/// Kicker, display title, subtitle. The mockup `.hd`.
///
///   .kicker  10px, w750, tracked 1.1, uppercase, accent, optional live node
///   h1       29px, w760, tracking -1.1, line-height 1.05
///   .h1s     12.5px muted
///
/// The title wraps naturally rather than being hard-broken as the mockup does
/// it ("Licensed<br/>insurers"): a forced break is a decision about a width we
/// do not control, and a Kikuyu or Swahili string would break in the wrong
/// place.
class InsureHead extends StatelessWidget {
  const InsureHead({
    super.key,
    required this.title,
    this.kicker,
    this.sub,
    this.live = true,
  });

  final String title;
  final String? kicker;
  final String? sub;

  /// Whether the kicker node pulses. False for a static fact (a register year),
  /// true for a figure that moves (a count of published rates).
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (kicker != null) ...[
            Row(
              children: [
                LiveDot(color: live ? c.up : c.accent, pulse: live),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    kicker!.toUpperCase(),
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 10,
                      height: 1.3,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
          ],
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 29,
              height: 1.05,
              letterSpacing: -1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 7),
            Text(
              sub!,
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ── glass nav ─────────────────────────────────────────────────────────────

/// The nav button: a 34px rounded square on s1, not a bare Material icon.
class NavButton extends StatelessWidget {
  const NavButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: c.line),
        ),
        child: Icon(icon, size: 17, color: c.text),
      ),
    );
  }
}

class _GlassNav extends StatelessWidget implements PreferredSizeWidget {
  const _GlassNav({
    required this.title,
    required this.showTitle,
    this.actions,
  });

  final String title;
  final bool showTitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          decoration: BoxDecoration(
            color: c.bg.withValues(alpha: 0.72),
            border: Border(
              // The hairline appears only once content is passing under the
              // nav. Drawn at zero alpha rather than with a null border, so the
              // container never changes height as it fades in.
              bottom: BorderSide(
                color: showTitle ? c.line : c.line.withValues(alpha: 0),
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    NavButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedOpacity(
                        opacity: showTitle ? 1 : 0,
                        duration: const Duration(milliseconds: 260),
                        child: Text(
                          title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 14,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (actions != null) ...actions!,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A scaffold whose content scrolls under a translucent nav.
///
/// [children] are laid into a single ListView, head block included, so the
/// headline scrolls away and the nav title takes over. Splitting the head out
/// of the scroll view (the Column + Expanded shape the directory used) pins it
/// forever and costs a third of the viewport on a small phone.
class InsureScaffold extends StatefulWidget {
  const InsureScaffold({
    super.key,
    required this.navTitle,
    required this.children,
    this.bottomBar,
    this.actions,
    this.bottomPadding = 40,
  });

  final String navTitle;
  final List<Widget> children;
  final Widget? bottomBar;
  final List<Widget>? actions;
  final double bottomPadding;

  @override
  State<InsureScaffold> createState() => _InsureScaffoldState();
}

class _InsureScaffoldState extends State<InsureScaffold> {
  bool _scrolled = false;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final s = n.metrics.pixels > 42;
    if (s != _scrolled) setState(() => _scrolled = s);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // extendBodyBehindAppBar means the list starts at y=0, under the nav, so
    // the top padding has to reproduce what the Scaffold would otherwise have
    // inset: the status bar plus the toolbar.
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      appBar: _GlassNav(
        title: widget.navTitle,
        showTitle: _scrolled,
        actions: widget.actions,
      ),
      bottomNavigationBar: widget.bottomBar,
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => FocusScope.of(context).unfocus(),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView(
            padding: EdgeInsets.only(top: top, bottom: widget.bottomPadding),
            children: widget.children,
          ),
        ),
      ),
    );
  }
}

// ── filter pills ──────────────────────────────────────────────────────────

/// One pill. [count] is the point of the control: "Flagged 3" tells a reader
/// there is something to look at before they tap, which "Flagged" alone does
/// not. A count of zero still renders, because zero flagged insurers is a
/// fact worth reading.
class PillDatum<T> {
  const PillDatum({
    required this.value,
    required this.label,
    this.count,
    this.danger = false,
  });

  final T value;
  final String label;
  final int? count;

  /// The pill fills red rather than white when selected. Reserved for the
  /// flagged filter, which is the one nobody else in Kenya shows a retail
  /// buyer.
  final bool danger;
}

/// Horizontally scrolling filter pills.
///
/// Not [SlidingSegments]: that control divides a fixed width between a known
/// number of equal choices, which is right for class and cover and wrong for
/// five filters carrying counts on a 360px phone. Segments cannot carry a
/// count, and five of them are unreadable.
class FilterPills<T> extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.pills,
    required this.selected,
    required this.onTap,
  });

  final List<PillDatum<T>> pills;
  final T selected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (pills.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          for (var i = 0; i < pills.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Pill<T>(
              datum: pills[i],
              active: pills[i].value == selected,
              onTap: () => onTap(pills[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pill<T> extends StatelessWidget {
  const _Pill({
    required this.datum,
    required this.active,
    required this.onTap,
  });

  final PillDatum<T> datum;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final fill = !active
        ? c.s1
        : datum.danger
            ? c.down
            : c.text;
    final edge = !active
        ? c.line
        : datum.danger
            ? c.down
            : c.text;
    // inkOn picks near-black or white off the fill's own luminance, so the
    // label stays legible on gold, on white and on red without any of the
    // three being written down here as a hex.
    final ink = active ? c.inkOn(fill) : c.muted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              datum.label,
              style: TextStyle(
                color: ink,
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (datum.count != null) ...[
              const SizedBox(width: 6),
              Text(
                '${datum.count}',
                style: TextStyle(
                  color: ink.withValues(alpha: 0.6),
                  fontFamily: fructaFonts.mono,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

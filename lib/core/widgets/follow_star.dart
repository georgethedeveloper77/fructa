import 'package:flutter/material.dart';

import '../i18n.dart';
import '../push.dart';
import '../theme.dart';

/// App-bar follow control. A watchlist star that fills with the subject's brand
/// [tint] when following and outlines when not, with a spring "pop" on every
/// toggle so the state change reads.
///
/// Following is a SUBSCRIPTION, not a bookmark: it drives push. That is why the
/// tooltip says Follow / Following rather than Save.
///
/// This was private to company_page.dart. It is shared now because the stock
/// page needs exactly the same control, and a second copy would have drifted:
/// the star is the only thing standing between a user and a push notification,
/// and two implementations of that is one too many.
///
/// The star also OWNS the delivery promise. Filling it used to write a tag and
/// nothing else, which on a device with no notification permission, or with the
/// push subscription opted out from "All alerts off", meant the app cheerfully
/// showed a followed fund that could never notify anyone. The promise was made
/// in the UI and broken silently three layers down.
///
/// So: turning a follow ON prompts for permission if it is missing, re-opts the
/// subscription in, and if the user still declines, keeps the follow (they do
/// want to watch this fund) while telling them plainly that alerts are off and
/// where to change it. The one thing it never does again is fail quietly.
class FollowStar extends StatefulWidget {
  const FollowStar({
    super.key,
    required this.following,
    required this.tint,
    required this.onToggle,
  });

  final bool following;
  final Color tint;

  /// Fires on every tap. May be async: the widget upcasts, so an existing
  /// `() => ref.read(subscriptionsProvider.notifier).toggle(id)` call site keeps
  /// compiling untouched even though `toggle` now returns a Future.
  final VoidCallback onToggle;

  @override
  State<FollowStar> createState() => _FollowStarState();
}

class _FollowStarState extends State<FollowStar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.35,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 38,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.35,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 62,
    ),
  ]).animate(_ctrl);

  /// Guards against a double tap racing the permission dialog.
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_busy) return;

    final turningOn = !widget.following;

    // Optimistic: the star pops and the state flips immediately. Making the user
    // wait on a round trip to OneSignal to see their own tap land would be worse
    // than the bug this is fixing.
    widget.onToggle();
    _ctrl.forward(from: 0);

    if (!turningOn) return;

    _busy = true;
    try {
      final deliverable = await Push.ensureDeliverable();
      if (!mounted || deliverable) return;
      _sayAlertsAreOff();
    } finally {
      _busy = false;
    }
  }

  /// The follow stands. The notification does not. Say so.
  void _sayAlertsAreOff() {
    final c = context.c;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: c.s3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            t('follow.alertsOff'),
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
          action: SnackBarAction(
            label: t('follow.alertsOffAction'),
            textColor: c.accent,
            onPressed: () {
              // Re-raises the OS dialog. If the user has already hard-denied,
              // the OS declines to show it again and this is a no-op, which is
              // why the Settings panel also offers a route to system settings.
              Push.promptPermission();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = widget.following;
    // Lifted for legibility so a dark brand (a navy tint) still reads on the
    // bar; the star and pill both take it.
    final tint = c.brandOnBg(widget.tint);

    return Tooltip(
      message: on ? t('company.following') : t('company.follow'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          // Not following: an outlined "Follow" pill. Following: the pill tightens
          // to a tinted circle holding just the star.
          padding: on
              ? const EdgeInsets.all(8)
              : const EdgeInsets.fromLTRB(11, 7, 14, 7),
          decoration: BoxDecoration(
            color: on ? tint.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: on ? null : Border.all(color: tint, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _pop,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    on ? Icons.star_rounded : Icons.star_border_rounded,
                    key: ValueKey(on),
                    color: tint,
                    size: 20,
                  ),
                ),
              ),
              // The label collapses to nothing when following, so the control
              // reads as "Follow" then settles to a lone star.
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: on
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          t('company.follow'),
                          style: TextStyle(
                            color: tint,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_root.dart';
import '../../core/theme_controller.dart';
import 'alerts_scene.dart';
import 'appearance_scene.dart';
import 'gap_scene.dart';
import 'persona_scene.dart';

/// First-launch sequence:
///   gap -> persona -> appearance -> alerts -> done.
///
/// The persona ('rates' | 'learn') is persisted so Markets can pin the Learn
/// primer for a 'learn' user once Phase 4 ships. "I just want the rates" skips
/// straight to the alerts opt-in. Completing flips the persisted `onboarded`
/// flag, which rebuilds AppRoot into the main scaffold.
///
/// Navigation is internal (a stage enum, not the Navigator), so Android back
/// has nothing to pop and would close the app. A [PopScope] plus a small stage
/// history fixes that: back walks the stages in reverse, and only the opening
/// stage lets the OS close the app. The history also makes the skip path pop
/// correctly, going gap -> alerts on skip, then alerts -> gap on back, never
/// surfacing the appearance stage the user skipped.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Stage { gap, persona, appearance, alerts }

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  _Stage _stage = _Stage.gap;

  // Stages the user has already passed through, most recent last. Back pops
  // this; when it is empty we are on the opening stage and the OS may close.
  final List<_Stage> _history = [];

  void _setPersona(String p) =>
      ref.read(settingsBoxProvider).put('onboarding_persona', p);

  void _complete() => ref.read(onboardedProvider.notifier).complete();

  /// Advance to [next], remembering where we came from for back.
  void _advance(_Stage next) {
    setState(() {
      _history.add(_stage);
      _stage = next;
    });
  }

  /// Step back one stage. Returns false when there is nowhere left to go, which
  /// tells [PopScope] to let the system handle the back (close the app).
  bool _back() {
    if (_history.isEmpty) return false;
    setState(() => _stage = _history.removeLast());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _back();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: switch (_stage) {
          _Stage.gap => GapScene(
            key: const ValueKey('gap'),
            onNext: () => _advance(_Stage.persona),
            onSkip: () {
              _setPersona('rates');
              _advance(_Stage.alerts);
            },
          ),
          _Stage.persona => PersonaScene(
            key: const ValueKey('persona'),
            onPick: (p) {
              _setPersona(p);
              _advance(_Stage.appearance);
            },
          ),
          _Stage.appearance => AppearanceScene(
            key: const ValueKey('appearance'),
            onNext: () => _advance(_Stage.alerts),
          ),
          _Stage.alerts => AlertsScene(
            key: const ValueKey('alerts'),
            onComplete: _complete,
          ),
        },
      ),
    );
  }
}

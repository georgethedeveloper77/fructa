import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_root.dart';
import '../../core/theme_controller.dart';
import 'alerts_scene.dart';
import 'appearance_scene.dart';
import 'persona_scene.dart';
import 'thesis_scene.dart';

/// First-launch sequence:
///   thesis → persona → appearance → alerts → done.
///
/// The persona ('rates' | 'learn') is persisted so Markets can pin the Learn
/// primer for a 'learn' user once Phase 4 ships. "I just want the rates" skips
/// straight to the alerts opt-in. Completing flips the persisted `onboarded`
/// flag, which rebuilds AppRoot into the main scaffold.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

enum _Stage { thesis, persona, appearance, alerts }

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  _Stage _stage = _Stage.thesis;

  void _setPersona(String p) =>
      ref.read(settingsBoxProvider).put('onboarding_persona', p);

  void _complete() => ref.read(onboardedProvider.notifier).complete();

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: switch (_stage) {
        _Stage.thesis => ThesisScene(
            key: const ValueKey('thesis'),
            onNext: () => setState(() => _stage = _Stage.persona),
            onSkip: () {
              _setPersona('rates');
              setState(() => _stage = _Stage.alerts);
            },
          ),
        _Stage.persona => PersonaScene(
            key: const ValueKey('persona'),
            onPick: (p) {
              _setPersona(p);
              setState(() => _stage = _Stage.appearance);
            },
          ),
        _Stage.appearance => AppearanceScene(
            key: const ValueKey('appearance'),
            onNext: () => setState(() => _stage = _Stage.alerts),
          ),
        _Stage.alerts => AlertsScene(
            key: const ValueKey('alerts'),
            onComplete: _complete,
          ),
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme_controller.dart';
import '../features/onboarding/onboarding_flow.dart';
import 'main_scaffold.dart';
import 'real_splash.dart';

/// Persisted "has the user finished onboarding" flag. Lives in the same Hive
/// `settings` box opened in main(). Completing onboarding flips it and the
/// gate rebuilds into the main scaffold.
class OnboardedController extends Notifier<bool> {
  static const _key = 'onboarded';

  @override
  bool build() =>
      ref.read(settingsBoxProvider).get(_key, defaultValue: false) as bool;

  void complete() {
    ref.read(settingsBoxProvider).put(_key, true);
    state = true;
  }

  /// Dev helper  reset onboarding (e.g. from a debug menu).
  void reset() {
    ref.read(settingsBoxProvider).put(_key, false);
    state = false;
  }
}

final onboardedProvider = NotifierProvider<OnboardedController, bool>(
  OnboardedController.new,
);

/// The persona chosen during onboarding ('rates' | 'learn'), persisted in the
/// settings box. Phase 4 (Learn) reads this to pin a primer at the top of
/// Markets for a 'learn' user; defaults to 'rates'.
final onboardingPersonaProvider = Provider<String>(
  (ref) =>
      ref
              .read(settingsBoxProvider)
              .get('onboarding_persona', defaultValue: 'rates')
          as String,
);

/// Root gate. Point `MaterialApp.home` at this. The launch splash plays first
/// (covering the snapshot load), then it routes to onboarding or the scaffold.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final onboarded = ref.watch(onboardedProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: !_splashDone
          ? RealSplash(
              key: const ValueKey('splash'),
              onDone: () => setState(() => _splashDone = true),
            )
          : (onboarded
                ? const MainScaffold(key: ValueKey('scaffold'))
                : const OnboardingFlow(key: ValueKey('onboarding'))),
    );
  }
}

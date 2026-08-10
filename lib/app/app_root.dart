import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme_controller.dart';
import '../data/providers.dart';
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

  /// Dev helper, reset onboarding (e.g. from a debug menu).
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

/// True once the app actually holds funds to render.
///
/// This is the splash's hand-off signal, and reading it here is what starts the
/// work. `ratesProvider` is lazy, so before this the provider was not built
/// until onboarding or Markets first watched it, which is to say AFTER the
/// splash had already finished. The splash was not covering the load; it was
/// idling for 2.8 seconds and the load began when it ended.
///
/// `hasValue` alone is the wrong test. `cachedOrBundled()` resolves to an empty
/// list on a first install with nothing cached, which would report ready while
/// the top-rate scene has no number to show. Non-empty is the honest signal.
final ratesReadyProvider = Provider<bool>(
  (ref) => ref.watch(
    ratesProvider.select((s) => s.value?.isNotEmpty ?? false),
  ),
);

/// Root gate. Point `MaterialApp.home` at this. The launch splash plays while
/// the snapshot loads, then it routes to onboarding or the scaffold.
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

    // Watching this on the very first build is what kicks the snapshot read and
    // the background refresh off at t=0, so the splash animation and the load
    // now overlap instead of running back to back.
    final ready = ref.watch(ratesReadyProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: !_splashDone
          ? RealSplash(
              key: const ValueKey('splash'),
              dataReady: ready,
              onDone: () => setState(() => _splashDone = true),
            )
          : (onboarded
                ? const MainScaffold(key: ValueKey('scaffold'))
                : const OnboardingFlow(key: ValueKey('onboarding'))),
    );
  }
}

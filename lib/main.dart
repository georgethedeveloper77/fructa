import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app_root.dart';
import 'app/deep_link.dart';
import 'app/lock_gate.dart';
import 'core/i18n.dart';
import 'core/local_notify.dart';
import 'core/push.dart';
import 'core/settings_prefs.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('rates'); // cached snapshot + etag
  await Hive.openBox('holdings'); // on-device portfolio
  final settings = await Hive.openBox('settings'); // app lock, prefs, theme
  await Hive.openBox('alerts'); // rate-change feed
  await L10n.load();

  await Push.init();
  await LocalNotify.init();

  // Both paths route identically. A tap on a server push and a tap on the local
  // fallback should land the user on the same screen, and if these two ever
  // diverge one of them is a dead end.
  Push.onOpenTarget = handlePushTarget;
  LocalNotify.onOpenTarget = handlePushTarget;

  // Fire and forget on cold start. Reconcile hits the network, and blocking
  // first paint on it would trade one bug for a worse one.
  unawaitedReconcile(settings);

  runApp(
    ProviderScope(
      // Hand the opened box to the theme controller (and settings prefs).
      overrides: [settingsBoxProvider.overrideWithValue(settings)],
      child: const FructaApp(),
    ),
  );
}

/// Bring OneSignal's tags into line with what this device believes it follows.
///
/// This replaces the old `Push.sync(subs)` call, which only ever ADDED tags and
/// only ever ran once at cold start. That left two holes:
///
///   - a follow whose tag write never reached OneSignal stayed broken forever,
///     because the next launch re-queued the same write into the same hole and
///     nothing ever checked whether it had landed;
///   - an unfollow performed offline never reached OneSignal at all, so the user
///     kept getting alerts for a fund they had dropped.
///
/// Reconcile reads the tags OneSignal actually holds, and writes only the
/// difference. Running it on resume as well as launch means a device self-heals
/// within one app open rather than never.
void unawaitedReconcile(Box settings) {
  final funds =
      ((settings.get('subs', defaultValue: <String>[]) as List).cast<String>())
          .toSet();
  final stocks =
      ((settings.get('stockSubs', defaultValue: <String>[]) as List)
              .cast<String>())
          .toSet();

  // The mute set is derived by SettingsPrefs.muteTagsFrom so main() never
  // hand-rolls the tag key names. main() runs before the ProviderScope exists,
  // so it cannot read settingsControllerProvider and has to go to the box
  // directly, but there is still exactly one definition of what a mute tag is.
  Push.reconcile(
    funds: funds,
    stocks: stocks,
    digest: settings.get('pref_weeklyDigest', defaultValue: true) as bool,
    mutes: SettingsPrefs.muteTagsFrom(settings),
  );
}

class FructaApp extends ConsumerStatefulWidget {
  const FructaApp({super.key});

  @override
  ConsumerState<FructaApp> createState() => _FructaAppState();
}

class _FructaAppState extends ConsumerState<FructaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Resume is the one moment we know the user is present, the process is
    // alive, and the network is probably up. It is the cheapest place to notice
    // that a tag never landed and fix it. It also catches the case that matters
    // most: the user went to system settings, turned notifications ON, and came
    // back. Without this the app would not know until the next cold start.
    if (state == AppLifecycleState.resumed) {
      unawaitedReconcile(Hive.box('settings'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(themeControllerProvider);
    return MaterialApp(
      title: 'Fructa',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey, // notification taps push onto this
      themeMode: t.mode, // System / Light / Dark from Settings
      theme: buildfructaTheme(brightness: Brightness.light, accent: t.accent),
      darkTheme: buildfructaTheme(
        brightness: Brightness.dark,
        accent: t.accent,
      ),
      // Global font-size setting: clamp the OS scale to the user's choice so
      // layouts stay predictable regardless of device accessibility settings.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: t.textScale,
        maxScaleFactor: t.textScale,
        child: child ?? const SizedBox.shrink(),
      ),
      // LockGate (biometric) wraps everything; AppRoot runs onboarding on
      // first launch, then the 3-tab scaffold.
      home: const LockGate(child: AppRoot()),
    );
  }
}

import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../firebase_options.dart';
import 'push.dart';

/// Firebase Analytics, wrapped so the rest of the app never touches the SDK.
///
/// `firebase_analytics` and `firebase_core` were already in pubspec but nothing
/// ever called `Firebase.initializeApp`, so the SDK was inert and the app has
/// been shipping with zero analytics. This is the missing initialisation plus a
/// small typed event surface.
///
/// Three rules hold everywhere in this file:
///
///   1. **Nothing here can throw into a caller.** Every public method swallows
///      its own failures. A telemetry outage must never take a screen with it.
///   2. **Nothing here blocks.** Every logging call is fire and forget. Callers
///      do not await, and none of these methods return a Future the UI waits on.
///   3. **Nothing here runs before first paint.** [init] is called from the
///      post-runApp block in main(), alongside Push.init, and is time-boxed
///      there. `first_open` is emitted by the SDK on first launch after init,
///      so a few hundred milliseconds of delay costs nothing and keeps a
///      platform channel off the boot path.
///
/// Event names are snake_case and deliberately few. Five events answered
/// honestly are worth more than fifty that nobody reads, and Firebase caps
/// custom event names at 500 per project anyway.
class Analytics {
  Analytics._();

  static FirebaseAnalytics? _fa;

  /// Whether Firebase came up. False means every method below is a no-op, which
  /// is the correct behaviour rather than an error state to handle at call
  /// sites.
  static bool get ready => _fa != null;

  /// Navigator observer that turns named route pushes into `screen_view`.
  ///
  /// Deliberately NOT `FirebaseAnalyticsObserver`. That class takes a
  /// `FirebaseAnalytics` at construction, and `FirebaseAnalytics.instance`
  /// throws `[core/no-app]` until `Firebase.initializeApp` has run. MaterialApp
  /// reads `navigatorObservers` during the first build, while [init] runs after
  /// `runApp` on purpose, so the eager version could only ever throw. Moving
  /// init earlier would put a platform channel back on the boot path, which is
  /// the thing that froze the splash and read as an ANR.
  ///
  /// This observer holds no SDK reference. It routes through [screen], which
  /// no-ops while `_fa` is null and starts working the moment init lands.
  ///
  /// Routes pushed without a [RouteSettings] name produce nothing, which is most
  /// of this app's `MaterialPageRoute` calls today. The explicit [screen] and
  /// [viewFund] calls cover the screens that matter without renaming every push
  /// site.
  static final NavigatorObserver observer = _ScreenObserver();

  /// Bring Firebase up and take the analytics handle.
  ///
  /// Safe to call twice: a duplicate-app error is caught and the existing
  /// instance is used.
  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // A hot restart or a second call raises duplicate-app. That is not a
      // failure, the app is already there, so fall through and take the handle.
      if (Firebase.apps.isEmpty) {
        debugPrint('[fructa] Firebase.initializeApp failed: $e');
        return;
      }
    }

    try {
      _fa = FirebaseAnalytics.instance;
      await _fa!.setAnalyticsCollectionEnabled(true);
      await _linkPushIdentity();
    } catch (e) {
      debugPrint('[fructa] Analytics init failed: $e');
      _fa = null;
    }
  }

  /// Stitch the two device identities together.
  ///
  /// OneSignal assigns this device a subscription id and Firebase assigns it an
  /// app instance id. Left alone they are two unrelated views of one person, so
  /// a question like "did the users we pushed on Tuesday come back" cannot be
  /// answered from either side. Writing each id into the other system costs one
  /// call and makes that join possible later.
  ///
  /// The OneSignal id is not available immediately at launch, so this is best
  /// effort. It reruns on every cold start, which is enough.
  static Future<void> _linkPushIdentity() async {
    final fa = _fa;
    if (fa == null) return;
    try {
      final subId = Push.subscriptionId;
      if (subId != null && subId.isNotEmpty) {
        await fa.setUserProperty(name: 'onesignal_id', value: subId);
      }
      final instanceId = await fa.appInstanceId;
      if (instanceId != null && instanceId.isNotEmpty) {
        Push.setFirebaseInstanceId(instanceId);
      }
    } catch (e) {
      debugPrint('[fructa] identity link skipped: $e');
    }
  }

  // ── Events ─────────────────────────────────────────────────────────────────

  /// A fund detail page opened. The single most useful engagement signal in the
  /// app: it is the moment a browser becomes a reader.
  /// [fundType] is nullable because `Fund.fundType` is: `category` is the
  /// legacy column and `fund_type` was added later, so a row that predates the
  /// migration carries null. Omitting the parameter is better than substituting
  /// 'unknown', which would show up in reports as a real segment.
  static void viewFund({
    required String fundId,
    required String currency,
    String? fundType,
    double? grossRate,
  }) => _log('view_fund', {
    'fund_id': fundId,
    'currency': currency,
    'fund_type': ?fundType,
    'gross_rate': ?grossRate,
  });

  /// A holding was saved. This is the conversion event.
  ///
  /// Not the amount. A balance is the most sensitive number the app holds, it
  /// is the whole point of the on-device privacy promise on the landing page
  /// and in Play frame 05, and shipping it to Google would quietly break that
  /// promise. The fund and the currency are enough to optimise on.
  static void addHolding({
    required String fundId,
    required String currency,
    required String kind,
  }) => _log('add_holding', {
    'fund_id': fundId,
    'currency': currency,
    'holding_kind': kind,
  });

  /// A fund was followed or unfollowed.
  static void followFund({required String fundId, required bool following}) =>
      _log('follow_fund', {'fund_id': fundId, 'following': following ? 1 : 0});

  /// A comparison was saved. Higher intent than a fund view: the user is
  /// choosing between named options rather than browsing.
  static void saveComparison({
    required int fundCount,
    required String? leaderId,
  }) => _log('save_comparison', {
    'fund_count': fundCount,
    'leader_id': ?leaderId,
  });

  /// Bottom tab changed. Cheap, and it answers whether anyone reaches Portfolio.
  static void selectTab(String tab) => _log('select_tab', {'tab': tab});

  /// An onboarding scene was reached. [step] is the stage name from
  /// OnboardingFlow, so the funnel reads topRate, gap, persona, appearance,
  /// alerts, complete.
  static void onboardingStep(String step) =>
      _log('onboarding_step', {'step': step});

  /// A screen the navigator observer cannot name for itself.
  static void screen(String name) {
    final fa = _fa;
    if (fa == null) return;
    unawaited(
      fa
          .logScreenView(screenName: name)
          .catchError((Object e) => debugPrint('[fructa] screen: $e')),
    );
  }

  // ── User properties ────────────────────────────────────────────────────────

  /// How many holdings this device has, bucketed.
  ///
  /// Bucketed rather than exact because a raw count is a step towards
  /// identifying a person, and the only question worth asking is whether they
  /// have none, one, or several.
  static void setHoldingsBucket(int count) => _prop(
    'holdings_bucket',
    count == 0
        ? 'none'
        : count == 1
        ? 'one'
        : count <= 4
        ? 'few'
        : 'many',
  );

  /// The persona chosen during onboarding, 'rates' or 'learn'.
  static void setPersona(String persona) => _prop('persona', persona);

  // ── Plumbing ───────────────────────────────────────────────────────────────

  static void _log(String name, Map<String, Object> params) {
    final fa = _fa;
    if (fa == null) return;
    unawaited(
      fa
          .logEvent(name: name, parameters: params)
          .catchError((Object e) => debugPrint('[fructa] event $name: $e')),
    );
  }

  static void _prop(String name, String value) {
    final fa = _fa;
    if (fa == null) return;
    unawaited(
      fa
          .setUserProperty(name: name, value: value)
          .catchError((Object e) => debugPrint('[fructa] prop $name: $e')),
    );
  }
}

/// Reports named route transitions to [Analytics.screen].
///
/// Separate from [Analytics] so it carries no static Firebase reference of its
/// own: constructing it must stay safe before `Firebase.initializeApp`.
class _ScreenObserver extends NavigatorObserver {
  void _send(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    Analytics.screen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _send(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _send(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _send(newRoute);
}

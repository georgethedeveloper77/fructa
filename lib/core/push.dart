import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// A read of the four things that have to ALL be true for a push to arrive.
/// Any one of them false and the user gets silence with no error anywhere in
/// the stack, which is the entire reason notifications felt random.
class PushDiagnostics {
  const PushDiagnostics({
    required this.permitted,
    required this.optedIn,
    required this.subscriptionId,
    required this.onesignalId,
    required this.remoteTags,
    this.error,
  });

  /// The OS notification permission. False on Android 13+ until the user has
  /// been asked and said yes. Every push is dropped silently while it is false.
  final bool permitted;

  /// The OneSignal push subscription's own opt-in flag, which "All alerts off"
  /// in Settings sets. Persists on the device. Tags still write while it is
  /// false, filters still match, and OneSignal still declines to deliver.
  final bool optedIn;

  /// Null until OneSignal has registered the device and got a token back. Tags
  /// written before this exists are queued, not lost, but nothing can be
  /// delivered to a device that has no subscription.
  final String? subscriptionId;

  final String? onesignalId;

  /// The tags OneSignal actually holds for this device, which is the only
  /// version that matters. The local Hive `subs` set is what we INTENDED.
  final Map<String, String> remoteTags;

  final String? error;

  int get followTagCount =>
      remoteTags.keys.where((k) => k.startsWith('follow_')).length;

  /// True only when a server-side tag push to this device would actually land.
  bool get deliverable =>
      permitted && optedIn && (subscriptionId ?? '').isNotEmpty;

  static const unknown = PushDiagnostics(
    permitted: false,
    optedIn: false,
    subscriptionId: null,
    onesignalId: null,
    remoteTags: {},
  );
}

// Thin wrapper over OneSignal. Follows are mirrored to per-fund tags so the
// backend can push a rate-change to exactly the users who follow that fund.
// Broadcast opt-ins (weekly digest, market alerts) are mirrored the same way,
// so the server can segment without knowing anything about the user.
class Push {
  static const appId = '85bb4c7a-70df-44d3-99b4-e0bfa8574713';

  /// Set by main() to route a notification tap to the right screen. Kept as a
  /// plain callback so this file has no dependency on the app/router layer.
  static void Function(String target)? onOpenTarget;

  /// Fired when a push arrives while the app is in the foreground, so the
  /// in-app alerts feed can mirror it. Set by main().
  static void Function(String title, String body, String? target)? onForeground;

  static String _slug(String id) => id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  // Must match the backend's tagKey() exactly.
  static String tagKey(String fundId) => 'follow_${_slug(fundId)}';

  /// Stock follows live in their OWN namespace.
  ///
  /// Fund ids and stock ids are both slugs, so `follow_<id>` could in principle
  /// collide across the two tables and a fund follow would silently subscribe
  /// you to a stock. Prefixing removes the possibility entirely. It also means
  /// the existing fund tags on every installed device keep working untouched:
  /// nothing here renames a tag that is already out in the world.
  static String stockTagKey(String stockId) => 'follow_stock_${_slug(stockId)}';

  /// Initialize OneSignal and wire the listeners. Does NOT request permission
  /// here: the prompt is raised at the onboarding "Turn on alerts" moment, from
  /// Settings, and now also inline the first time a user taps a follow star, so
  /// first launch never cold-prompts.
  static Future<void> init() async {
    if (kDebugMode) OneSignal.Debug.setLogLevel(OSLogLevel.warn);

    OneSignal.initialize(appId);

    OneSignal.Notifications.addClickListener((event) {
      final target = event.notification.additionalData?['target'];
      if (target is String && target.isNotEmpty) onOpenTarget?.call(target);
    });

    // Without an explicit foreground listener the SDK's own default decides
    // whether a push that lands while the app is open reaches the drawer, and
    // we get no visibility into it either way. preventDefault + display() puts
    // that decision here, and lets the in-app feed mirror what arrived.
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.preventDefault();
      event.notification.display();
      onForeground?.call(
        event.notification.title ?? '',
        event.notification.body ?? '',
        event.notification.additionalData?['target'] as String?,
      );
    });
  }

  /// Raise the OS notification-permission prompt (the system dialog). Safe to
  /// call more than once: the OS only shows it once, then this reflects the
  /// current grant. Returns whether notifications are permitted.
  static Future<bool> promptPermission() async {
    try {
      return await OneSignal.Notifications.requestPermission(true);
    } catch (_) {
      return false;
    }
  }

  static bool get permitted => OneSignal.Notifications.permission;

  static bool get optedIn => OneSignal.User.pushSubscription.optedIn == true;

  static String? get subscriptionId => OneSignal.User.pushSubscription.id;

  /// Make this device capable of receiving a push, prompting if it has to.
  ///
  /// Call this at the moment the user asks for something that depends on push,
  /// which is the follow star. Following a fund on a device with no permission
  /// grant is a promise the app cannot keep, and the old code made it silently.
  ///
  /// Returns whether a push to this device would now land.
  static Future<bool> ensureDeliverable() async {
    // "All alerts off" in Settings calls optOut(), and it persists. A follow on
    // an opted-out subscription writes a tag that matches a filter that is then
    // declined at the delivery step. Re-opt in: the user just asked for alerts
    // on this fund, which is unambiguous consent.
    OneSignal.User.pushSubscription.optIn();

    if (permitted) return true;
    return promptPermission();
  }

  /// Master switch: opts the device's push subscription in/out at OneSignal,
  /// so "All alerts off" actually stops delivery (the pref alone doesn't).
  static void setEnabled(bool on) {
    if (on) {
      OneSignal.User.pushSubscription.optIn();
    } else {
      OneSignal.User.pushSubscription.optOut();
    }
  }

  static Future<void> follow(String fundId) async {
    OneSignal.User.pushSubscription.optIn();
    OneSignal.User.addTags({tagKey(fundId): 'true'});
  }

  static Future<void> unfollow(String fundId) async {
    OneSignal.User.removeTag(tagKey(fundId));
  }

  static Future<void> followStock(String stockId) async {
    OneSignal.User.pushSubscription.optIn();
    OneSignal.User.addTags({stockTagKey(stockId): 'true'});
  }

  static Future<void> unfollowStock(String stockId) async {
    OneSignal.User.removeTag(stockTagKey(stockId));
  }

  /// Weekly-digest opt-in: mirrors the Settings toggle to the server segment.
  /// This one is an opt-IN because the digest is a broadcast: the server has no
  /// per-user hook to hang it on, so a device has to raise its hand.
  static void setDigest(bool on) => on
      ? OneSignal.User.addTags({'digest_weekly': 'true'})
      : OneSignal.User.removeTag('digest_weekly');

  // MUTES --------------------------------------------------------------------
  //
  // The notification sub-toggles in Settings used to write to Hive and stop
  // there. Nothing mirrored them to OneSignal, and the server targets funds by
  // `follow_<id>` and knows nothing about a user's preferences. So a user who
  // turned "Rate moves" OFF kept getting rate-move pushes, forever, with no way
  // to make it stop short of killing every alert.
  //
  // These are opt-OUT tags, deliberately. An opt-IN tag (`rate_moves: true`)
  // would require every device already in the wild to write it before the server
  // could filter on it, and until they did, the filter would match nobody and
  // ship total silence to the entire user base. A mute tag is only ever written
  // when a user actively turns something off, so a device that has never touched
  // the setting carries no tag, and `NOT EXISTS` on the server matches it. There
  // is no migration window and nothing already installed breaks.

  static const muteRateMoves = 'mute_rate_moves';
  static const muteSaved = 'mute_saved';
  static const muteCoupons = 'mute_coupons';

  static const _muteKeys = {muteRateMoves, muteSaved, muteCoupons};

  /// [muted] true writes the tag, false removes it. Mirrors one Settings toggle.
  static void setMuted(String key, bool muted) {
    if (muted) {
      OneSignal.User.addTags({key: 'true'});
    } else {
      OneSignal.User.removeTag(key);
    }
  }

  /// Bring OneSignal's tags into line with what this device believes it follows.
  ///
  /// This replaces the old fire-and-forget `sync()`, which only ever ADDED and
  /// only ever ran on cold start. Two things go wrong without a reconcile:
  ///
  ///   - a tag write queued at the moment the process died can arrive late or
  ///     not at all, leaving a filled star in the UI and no tag at OneSignal,
  ///     so the fund is silently dead to that user with nothing to indicate it;
  ///   - a tag removed while offline stays on the device forever, so the user
  ///     keeps getting alerts for a fund they unfollowed months ago.
  ///
  /// Run it on cold start and on every app resume. It is cheap: one read, and
  /// writes only for the difference.
  ///
  /// [digest] mirrors the persisted weekly-digest pref. [mutes] is the set of
  /// mute keys currently ON (see [muteRateMoves] and friends): every mute key
  /// NOT in the set is removed, which is what makes un-muting stick.
  ///
  /// Between them, `follow_*`, `digest_weekly` and `mute_*` are the entire tag
  /// namespace this app owns, so reconcile can safely delete anything in those
  /// namespaces that the device does not currently want. It touches nothing else.
  static Future<PushDiagnostics> reconcile({
    required Set<String> funds,
    required Set<String> stocks,
    required bool digest,
    required Set<String> mutes,
  }) async {
    final want = <String, String>{
      for (final id in funds) tagKey(id): 'true',
      for (final id in stocks) stockTagKey(id): 'true',
      if (digest) 'digest_weekly': 'true',
      for (final k in mutes) k: 'true',
    };

    Map<String, String> remote = const {};
    String? err;
    try {
      remote = await OneSignal.User.getTags();
    } catch (e) {
      // getTags failing (no subscription yet on a fresh install, no network)
      // leaves `remote` empty, which makes every wanted tag look missing and
      // triggers a blind re-add. That is exactly the right fallback.
      err = e.toString();
    }

    final missing = <String, String>{};
    want.forEach((k, v) {
      if (remote[k] != v) missing[k] = v;
    });
    if (missing.isNotEmpty) OneSignal.User.addTags(missing);

    // Stale tags. Scoped hard to the three namespaces this app owns, so a tag
    // written by anything else is never touched.
    for (final k in remote.keys) {
      if (want.containsKey(k)) continue;
      final ours = k.startsWith('follow_') ||
          k == 'digest_weekly' ||
          _muteKeys.contains(k);
      if (ours) OneSignal.User.removeTag(k);
    }

    return diagnostics(seedError: err);
  }

  /// Read the delivery state of this device. Everything the Settings panel needs
  /// to turn "notifications are flaky" into a fact you can point at.
  static Future<PushDiagnostics> diagnostics({String? seedError}) async {
    var err = seedError;
    var tags = const <String, String>{};
    String? oid;

    try {
      tags = await OneSignal.User.getTags();
      oid = await OneSignal.User.getOnesignalId();
    } catch (e) {
      err ??= e.toString();
    }

    return PushDiagnostics(
      permitted: OneSignal.Notifications.permission,
      optedIn: OneSignal.User.pushSubscription.optedIn == true,
      subscriptionId: OneSignal.User.pushSubscription.id,
      onesignalId: oid,
      remoteTags: tags,
      error: err,
    );
  }
}

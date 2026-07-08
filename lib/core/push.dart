import 'package:onesignal_flutter/onesignal_flutter.dart';

// Thin wrapper over OneSignal. Follows are mirrored to per-fund tags so the
// backend can push a rate-change to exactly the users who follow that fund.
// Broadcast opt-ins (weekly digest, market alerts) are mirrored the same way,
// so the server can segment without knowing anything about the user.
class Push {
  static const appId = '85bb4c7a-70df-44d3-99b4-e0bfa8574713';

  /// Set by main() to route a notification tap to the right screen. Kept as a
  /// plain callback so this file has no dependency on the app/router layer.
  static void Function(String target)? onOpenTarget;

  // Must match the backend's tagKey() exactly.
  static String tagKey(String fundId) =>
      'follow_${fundId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

  /// Initialize OneSignal and wire the tap handler. Does NOT request
  /// permission here  the prompt is raised at the onboarding "Turn on alerts"
  /// moment (and from Settings), so first launch never cold-prompts.
  static Future<void> init() async {
    OneSignal.initialize(appId);
    OneSignal.Notifications.addClickListener((event) {
      final target = event.notification.additionalData?['target'];
      if (target is String && target.isNotEmpty) onOpenTarget?.call(target);
    });
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

  static void follow(String fundId) =>
      OneSignal.User.addTags({tagKey(fundId): 'true'});
  static void unfollow(String fundId) =>
      OneSignal.User.removeTag(tagKey(fundId));

  // Re-apply all followed tags on launch (device may have been reset).
  static void sync(Set<String> fundIds) {
    if (fundIds.isEmpty) return;
    OneSignal.User.addTags({for (final id in fundIds) tagKey(id): 'true'});
  }

  /// Weekly-digest opt-in  mirrors the Settings toggle to the server segment.
  static void setDigest(bool on) => on
      ? OneSignal.User.addTags({'digest_weekly': 'true'})
      : OneSignal.User.removeTag('digest_weekly');

  /// Market-wide broadcast opt-in  mirrors the Settings toggle.
  static void setMarketAlerts(bool on) => on
      ? OneSignal.User.addTags({'market_alerts': 'true'})
      : OneSignal.User.removeTag('market_alerts');
}

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';

/// Drawer notifications the app raises itself, with no server and no OneSignal
/// in the path.
///
/// Why this exists at all, given there is already a push pipeline:
///
/// `RatesNotifier._detectAlerts` already compares the freshly fetched snapshot
/// against the previous one and finds every followed fund whose rate moved. That
/// detection is local, deterministic, and has never failed. Until now it only
/// wrote to the in-app alerts feed, which the user has to open the app to see.
///
/// So the app was in the absurd position of KNOWING a followed fund had moved
/// and saying nothing, while a much longer and much more fragile chain (tag
/// reaches OneSignal, filter matches, FCM delivers, Doze does not eat it) was
/// the only thing that could put it in the drawer.
///
/// This closes that gap. Push remains the way a user hears about a rate move
/// without opening the app. This is the guarantee that once they DO open it,
/// what they followed demonstrably works.
///
/// Both paths land on the same Android channel, so the user gets one "Rate
/// alerts" switch in system settings rather than two.
class LocalNotify {
  /// Must match ANDROID_CHANNEL_ID in supabase/functions/_shared/onesignal.ts.
  static const channelId = 'fructa_rates';
  static const channelName = 'Rate alerts';
  static const channelDescription =
      'Rate moves on the funds, SACCOs and stocks you follow.';

  /// Fructa gold. This is an OS-level notification tint applied outside the
  /// widget tree, where there is no BuildContext and therefore no `context.c`
  /// to read the token from. It is the one place a literal is unavoidable.
  static const _accent = Color(0xFFE7B24C);

  /// Monochrome silhouette. Android renders a full-colour launcher icon as a
  /// solid white blob in the status bar, so the small icon must be its own
  /// asset. Lives in android/app/src/main/res/drawable-*/.
  static const _androidIcon = 'ic_stat_fructa';

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Set by main(), same contract as Push.onOpenTarget, so a tap on a local
  /// notification routes exactly like a tap on a push.
  static void Function(String target)? onOpenTarget;

  static bool _ready = false;

  static Future<void> init() async {
    const android = AndroidInitializationSettings(_androidIcon);

    // All three false on purpose. OneSignal already owns the iOS permission
    // prompt, and both plugins sit on the same UNUserNotificationCenter grant.
    // Asking twice would show the user two dialogs for one permission.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // v22 moved initialize() and show() to all-named parameters. Both are
    // silently source-breaking in the sense that the OLD positional call is a
    // hard compile error, which is at least honest.
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onOpenTarget?.call(payload);
      },
    );

    // Creating the channel here, rather than letting the first notification
    // create it implicitly, is what lets the server push reuse it by name via
    // `existing_android_channel_id`.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.high,
          ),
        );

    _ready = true;
  }

  static NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _androidIcon,
          color: _accent,
        ),
        iOS: DarwinNotificationDetails(),
      );

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? target,
  }) async {
    if (!_ready) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
      payload: target,
    );
  }

  /// A notification the user can raise on demand from Settings. The single
  /// fastest way to answer "is the drawer path working on this handset", because
  /// it exercises permission, channel and icon while cutting the server, the
  /// tags and FCM entirely out of the picture.
  static Future<void> test() => show(
        id: 424242,
        title: 'Fructa alerts are working',
        body: 'This is what a rate alert will look like on this phone.',
        target: 'alerts',
      );

  // ---------------------------------------------------------------------------
  // Rate changes
  // ---------------------------------------------------------------------------

  static Box get _box => Hive.box('settings');

  /// Fire-once guard. `_detectAlerts` runs on every snapshot refresh, and the
  /// same move can be re-detected across a cold start (cached snapshot vs fresh
  /// fetch). Keyed on fund plus the resulting rate, so a genuine second move on
  /// the same fund still notifies.
  static bool _claim(String key) {
    final seen =
        ((_box.get('notifiedKeys', defaultValue: <String>[]) as List)
                .cast<String>())
            .toList();
    if (seen.contains(key)) return false;
    seen.add(key);
    if (seen.length > 300) seen.removeRange(0, seen.length - 300);
    _box.put('notifiedKeys', seen);
    return true;
  }

  static String _pct(double v) => '${v.toStringAsFixed(2)}%';

  static Future<void> rateChange({
    required String fundId,
    required String name,
    required double oldRate,
    required double newRate,
  }) async {
    final key = '$fundId|${newRate.toStringAsFixed(4)}';
    if (!_claim(key)) return;

    final rose = newRate > oldRate;
    await show(
      id: key.hashCode & 0x7fffffff,
      title: name,
      body: rose
          ? 'Rate rose to ${_pct(newRate)}, was ${_pct(oldRate)}'
          : 'Rate fell to ${_pct(newRate)}, was ${_pct(oldRate)}',
      target: 'fund/$fundId',
    );
  }

  /// Four or more followed funds moved in one refresh. Four separate buzzes is
  /// how an app gets its notifications turned off permanently, so collapse.
  static Future<void> rateChangeSummary(int count) async {
    final key = 'summary|${DateTime.now().toIso8601String().substring(0, 13)}';
    if (!_claim(key)) return;

    await show(
      id: key.hashCode & 0x7fffffff,
      title: 'Rates moved',
      body: '$count funds you follow changed their rate.',
      target: 'alerts',
    );
  }
}

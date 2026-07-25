import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/theme.dart';
import 'learn_progress.dart';

/// Daily learn reminder. On by default so a new learner is nudged from day one;
/// they can turn it off or move the time. Prefs live in the shared `settings`
/// Hive box (like subscriptions and app-lock), so no new box or main() change.
class LearnReminderPrefs {
  const LearnReminderPrefs({
    this.enabled = true,
    this.hour = 19,
    this.minute = 0,
  });

  final bool enabled;
  final int hour;
  final int minute;

  TimeOfDay get time => TimeOfDay(hour: hour, minute: minute);

  LearnReminderPrefs copyWith({bool? enabled, int? hour, int? minute}) =>
      LearnReminderPrefs(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

final learnReminderProvider =
    NotifierProvider<LearnReminderController, LearnReminderPrefs>(
      LearnReminderController.new,
    );

class LearnReminderController extends Notifier<LearnReminderPrefs> {
  Box get _box => Hive.box('settings');

  @override
  LearnReminderPrefs build() => LearnReminderPrefs(
    enabled: _box.get('learn_reminder_on', defaultValue: true) as bool,
    hour: _box.get('learn_reminder_hour', defaultValue: 19) as int,
    minute: _box.get('learn_reminder_min', defaultValue: 0) as int,
  );

  Future<void> setEnabled(bool on, {required int streak}) async {
    await _box.put('learn_reminder_on', on);
    state = state.copyWith(enabled: on);
    await LearnReminder.instance.apply(state, streak: streak);
  }

  Future<void> setTime(int hour, int minute, {required int streak}) async {
    await _box.put('learn_reminder_hour', hour);
    await _box.put('learn_reminder_min', minute);
    state = state.copyWith(hour: hour, minute: minute);
    await LearnReminder.instance.apply(state, streak: streak);
  }

  /// Re-apply on open so the scheduled body carries the live streak, and so the
  /// default-on schedules itself the first time a learner arrives.
  Future<void> refresh({required int streak}) =>
      LearnReminder.instance.apply(state, streak: streak);

  /// Whether the one-time Learn-tab card has been shown. After it has, the
  /// controls live only in Settings > Notifications.
  bool get seen => _box.get('learn_reminder_seen', defaultValue: false) as bool;

  Future<void> markSeen() => _box.put('learn_reminder_seen', true);
}

/// Wraps flutter_local_notifications for the single daily learn reminder. Lazily
/// initialised, so it needs no main() change. Every call is guarded: a
/// scheduling hiccup must never crash the Learn screen.
class LearnReminder {
  LearnReminder._();
  static final LearnReminder instance = LearnReminder._();

  static const _id = 4200;
  static const _channelId = 'learn_reminders';
  static const _channelName = 'Learn reminders';
  static const _channelDesc =
      'A daily nudge to keep your learning streak going.';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _ensureInit() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // Kenya-only app; anchor the daily time to East Africa Time.
    tz.setLocalLocation(tz.getLocation('Africa/Nairobi'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.defaultImportance,
          ),
        );

    _ready = true;
  }

  Future<void> _ensurePermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
      return;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Schedule or cancel the daily reminder to match [prefs], with copy that
  /// reflects the current [streak].
  Future<void> apply(LearnReminderPrefs prefs, {required int streak}) async {
    try {
      await _ensureInit();
      await _plugin.cancel(id: _id);
      if (!prefs.enabled) return;
      await _ensurePermission();

      final body = streak > 0
          ? 'A 2-minute lesson keeps your $streak-day streak going.'
          : 'Two minutes today starts your streak. Pick up a lesson.';

      await _plugin.zonedSchedule(
        id: _id,
        title: 'Keep your streak alive',
        body: body,
        scheduledDate: _nextInstance(prefs.hour, prefs.minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact avoids the exact-alarm permission on Android 12+; a learning
        // nudge does not need to fire to the second.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Never let a scheduling hiccup take down the Learn screen.
    }
  }

  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }
}

/// Opt-in card for the Learn home: a toggle and a daily time. Reschedules on
/// first frame so the copy carries the live streak and the default-on takes
/// effect for a first-time learner.
class LearnReminderCard extends ConsumerStatefulWidget {
  const LearnReminderCard({super.key});

  @override
  ConsumerState<LearnReminderCard> createState() => _LearnReminderCardState();
}

class _LearnReminderCardState extends ConsumerState<LearnReminderCard> {
  // The card is a one-time nudge in Learn: it shows on the first visit, marks
  // itself seen, and thereafter lives only in Settings > Notifications. The
  // reschedule still runs every open so the streak copy stays fresh.
  bool _firstRun = false;

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(learnReminderProvider.notifier);
    _firstRun = !ctrl.seen;
    if (_firstRun) ctrl.markSeen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final streak = ref.read(learnProgressProvider).streak;
      ctrl.refresh(streak: streak);
    });
  }

  Future<void> _pickTime(LearnReminderPrefs prefs, int streak) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: prefs.time,
    );
    if (picked == null || !mounted) return;
    await ref
        .read(learnReminderProvider.notifier)
        .setTime(picked.hour, picked.minute, streak: streak);
  }

  String _fmt(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstRun) return const SizedBox.shrink();
    final c = context.c;
    final prefs = ref.watch(learnReminderProvider);
    final streak = ref.watch(learnProgressProvider).streak;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                _tile(c.accent, Icons.local_fire_department_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily reminder',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'A nudge to keep your streak going',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _Toggle(
                  value: prefs.enabled,
                  onChanged: (v) => ref
                      .read(learnReminderProvider.notifier)
                      .setEnabled(v, streak: streak),
                ),
              ],
            ),
          ),
          if (prefs.enabled)
            InkWell(
              onTap: () => _pickTime(prefs, streak),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    _tile(c.muted, Icons.schedule, faint: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remind me at',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      _fmt(prefs.time),
                      style: TextStyle(
                        color: c.accent,
                        fontFamily: fructaFonts.mono,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.faint, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tile(Color tint, IconData icon, {bool faint = false}) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: faint ? context.c.s3 : tint.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: tint),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 24,
        decoration: BoxDecoration(
          color: value ? c.accent : c.line2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: c.text, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

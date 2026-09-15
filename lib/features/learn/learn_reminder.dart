import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/local_notify.dart';
import '../../core/theme.dart';
import '../../data/models/learn.dart';
import '../../data/snapshot_providers.dart';
import 'learn_path.dart';
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

  Future<void> setEnabled(
    bool on, {
    LearnContent? content,
    LearnProgress? progress,
  }) async {
    await _box.put('learn_reminder_on', on);
    state = state.copyWith(enabled: on);
    await _apply(content, progress);
  }

  Future<void> setTime(
    int hour,
    int minute, {
    LearnContent? content,
    LearnProgress? progress,
  }) async {
    await _box.put('learn_reminder_hour', hour);
    await _box.put('learn_reminder_min', minute);
    state = state.copyWith(hour: hour, minute: minute);
    await _apply(content, progress);
  }

  /// Live state when the caller has it, the persisted ladder otherwise.
  ///
  /// Settings can reach both providers, so it passes them: a learner who
  /// switches the reminder on from Settings before ever opening Learn has no
  /// cached ladder, and falling back there would arm nothing but the evergreen
  /// tail two weeks out.
  Future<void> _apply(LearnContent? content, LearnProgress? progress) async {
    if (content != null && progress != null) {
      await syncLearnReminders(
        content: content,
        progress: progress,
        prefs: state,
      );
      return;
    }
    await LearnReminder.instance.rearm(state);
  }

  /// Whether the one-time Learn-tab card has been shown. After it has, the
  /// controls live only in Settings > Notifications.
  bool get seen => _box.get('learn_reminder_seen', defaultValue: false) as bool;

  Future<void> markSeen() => _box.put('learn_reminder_seen', true);
}

// ---------------------------------------------------------------------------
// Ladder input
// ---------------------------------------------------------------------------

/// Everything the ladder needs to write true copy, in one flat value that can
/// be persisted.
///
/// It is persisted because the ladder must be rebuildable on a cold start
/// without mounting the Learn screen. A learner who installs, does two lessons,
/// then only ever opens Markets would otherwise keep the reminders scheduled on
/// the day they last opened Learn, and those go stale the moment the day rolls.
class LearnLadderInput {
  const LearnLadderInput({
    this.streak = 0,
    this.best = 0,
    this.lastDay,
    this.nextLessonTitle,
    this.unitTitle,
    this.unitDone = 0,
    this.unitTotal = 0,
    this.nextUnitTitle,
    this.daysActive7 = 0,
    this.hook,
  });

  final int streak;
  final int best;

  /// yyyy-mm-dd of the last completion. Stored rather than a "did they study
  /// today" boolean: the boolean is only true for a few hours and a cached one
  /// is a lie by morning.
  final String? lastDay;

  final String? nextLessonTitle;
  final String? unitTitle;
  final int unitDone;
  final int unitTotal;
  final String? nextUnitTitle;
  final int daysActive7;

  /// A single market line for the dormant rung, for example
  /// "91 day T-bill moved to 8.42%". Null falls back to lesson copy.
  final String? hook;

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get completedToday => lastDay != null && lastDay == _day(DateTime.now());

  /// The streak as it stands right now, not as it stood when this input was
  /// written. A cached streak of 6 whose last day was a week ago is a streak of
  /// zero, and a notification that claims otherwise is the exact failure this
  /// whole rewrite exists to remove.
  int get liveStreak {
    if (lastDay == null) return 0;
    final now = DateTime.now();
    final yesterday = _day(now.subtract(const Duration(days: 1)));
    if (lastDay == _day(now) || lastDay == yesterday) return streak;
    return 0;
  }

  Map<String, dynamic> toMap() => {
        'streak': streak,
        'best': best,
        'lastDay': lastDay,
        'next': nextLessonTitle,
        'unit': unitTitle,
        'unitDone': unitDone,
        'unitTotal': unitTotal,
        'nextUnit': nextUnitTitle,
        'days7': daysActive7,
        'hook': hook,
      };

  static LearnLadderInput fromMap(Map<dynamic, dynamic> m) => LearnLadderInput(
        streak: (m['streak'] as num?)?.toInt() ?? 0,
        best: (m['best'] as num?)?.toInt() ?? 0,
        lastDay: m['lastDay'] as String?,
        nextLessonTitle: m['next'] as String?,
        unitTitle: m['unit'] as String?,
        unitDone: (m['unitDone'] as num?)?.toInt() ?? 0,
        unitTotal: (m['unitTotal'] as num?)?.toInt() ?? 0,
        nextUnitTitle: m['nextUnit'] as String?,
        daysActive7: (m['days7'] as num?)?.toInt() ?? 0,
        hook: m['hook'] as String?,
      );
}

class _Rung {
  const _Rung(this.id, this.when, this.title, this.body, {this.repeatDaily = false});
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final bool repeatDaily;
}

// ---------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------

/// Schedules the learn reminders as a ladder of dated one-shots keyed on how
/// long it has been since the last completed lesson.
///
/// The previous implementation scheduled a single notification with
/// `DateTimeComponents.time`, which repeats daily carrying the body it was
/// built with. That body named a streak length, so it kept announcing a number
/// that had since changed, and it fired at the reminder hour even on days the
/// learner had already done a lesson. Neither is fixable with better copy: a
/// repeating notification cannot know anything that happened after it was
/// scheduled. So nothing that carries a number, a name or a date repeats. Every
/// rung is dated, the whole set is cancelled and rebuilt on each resync, and
/// the one rung allowed to repeat says nothing that can go stale.
class LearnReminder {
  LearnReminder._();
  static final LearnReminder instance = LearnReminder._();

  static const _idNudge = 4200; // also the legacy id, so old builds get cleared
  static const _idAtRisk = 4201;
  static const _idResume = 4202;
  static const _idReset = 4203;
  static const _idRecap = 4204;
  static const _idDormant = 4205;
  static const _idTail = 4206;

  static const _allIds = [
    _idNudge,
    _idAtRisk,
    _idResume,
    _idReset,
    _idRecap,
    _idDormant,
    _idTail,
  ];

  static const _target = 'learn';

  Box get _box => Hive.box('settings');

  /// Rebuild the whole ladder. Called on lesson complete, on opening Learn, and
  /// from main() on cold start.
  Future<void> resync(LearnReminderPrefs prefs, LearnLadderInput input) async {
    await _box.put('learn_ladder', input.toMap());
    await LocalNotify.cancelIds(_allIds);
    if (!prefs.enabled) return;

    for (final rung in _build(prefs, input)) {
      await LocalNotify.schedule(
        id: rung.id,
        title: rung.title,
        body: rung.body,
        when: rung.when,
        target: _target,
        learn: true,
        repeatDaily: rung.repeatDaily,
      );
    }
  }

  /// Rebuild from the last persisted input. Safe to call from main() after
  /// `LocalNotify.init()`, and it is what keeps the ladder honest for a learner
  /// who opens the app without opening Learn.
  Future<void> rearm(LearnReminderPrefs prefs) async {
    final cached = _box.get('learn_ladder');
    if (cached is! Map) {
      await LocalNotify.cancelIds(_allIds);
      return;
    }
    await resync(prefs, LearnLadderInput.fromMap(cached));
  }

  List<_Rung> _build(LearnReminderPrefs prefs, LearnLadderInput input) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime at(int addDays, int hour, int minute) => DateTime(
          today.year,
          today.month,
          today.day + addDays,
          hour,
          minute,
        );

    final streak = input.liveStreak;
    final next = input.nextLessonTitle;
    final hasPath = next != null && next.isNotEmpty;
    final partway = input.unitTotal > 0 && input.unitDone > 0;

    final candidates = <_Rung?>[
      // Tier 1. Tonight, only if today is still empty and the hour has not
      // already passed.
      if (hasPath && !input.completedToday)
        _Rung(
          _idNudge,
          at(0, prefs.hour, prefs.minute),
          streak > 0 ? 'Keep the $streak day streak' : 'Two minutes on money',
          streak > 0
              ? 'One lesson holds it. Next up: $next.'
              : 'Start a streak with $next.',
        ),

      // Tier 2. The only rung allowed to use a deadline, and only when there is
      // something real to lose. A one day streak is not worth alarming anyone
      // about.
      if (hasPath && streak >= 2)
        _Rung(
          _idAtRisk,
          at(1, prefs.hour, prefs.minute),
          'Your streak ends tonight',
          '$streak days. One lesson before midnight keeps it.',
        ),

      // Tier 3. Mid-unit resume. Skipped rather than filled when the unit was
      // not started, because a generic line in this slot teaches the learner
      // that the whole channel is noise.
      if (hasPath && partway)
        _Rung(
          _idResume,
          at(1, 9, 0),
          '${input.unitDone} of ${input.unitTotal} through ${input.unitTitle}',
          '${input.unitTotal - input.unitDone} lessons left. Pick up at $next.',
        ),

      // Tier 4. Factual, no guilt. The record is a target, not a scolding.
      if (streak >= 3)
        _Rung(
          _idReset,
          at(2, 9, 0),
          'Streak reset to 0',
          'Your best was ${input.best} days. One lesson today starts the next one.',
        ),

      // Recap. Only ever sent on a week with something in it. A zero week
      // recap is a report card nobody asked for.
      if (input.daysActive7 >= 1)
        _Rung(
          _idRecap,
          _nextSunday(today, 18, 0),
          'You studied ${input.daysActive7} of the last 7 days',
          hasPath
              ? 'Streak at $streak. Next up: $next.'
              : 'You have finished every published lesson.',
        ),

      // Dormant. Streak language has stopped working by now, so switch to the
      // market. This is the rung no general learning app can send.
      _Rung(
        _idDormant,
        at(7, prefs.hour, prefs.minute),
        input.hook ?? 'Rates moved while you were away',
        input.hook != null
            ? 'A two minute lesson explains what moves it.'
            : hasPath
                ? 'Two minutes on $next while you are here.'
                : 'Open Fructa to see where yields landed this week.',
      ),

      // Evergreen tail. The only repeating rung, and the reason it may repeat
      // is that it contains no number, no lesson name and no date, so it cannot
      // go stale no matter how long it runs.
      _Rung(
        _idTail,
        at(14, prefs.hour, prefs.minute),
        'Two minutes on money',
        'A short lesson is waiting in Fructa.',
        repeatDaily: true,
      ),
    ];

    // One notification per calendar day, first claim wins. The list above is
    // already in priority order, so the more specific rung takes the day and
    // the vaguer one is dropped rather than stacked on top of it.
    final claimed = <String>{};
    final out = <_Rung>[];
    for (final r in candidates) {
      if (r == null) continue;
      if (!r.when.isAfter(now)) continue;
      final key = '${r.when.year}-${r.when.month}-${r.when.day}';
      if (!claimed.add(key)) continue;
      out.add(r);
    }
    return out;
  }

  DateTime _nextSunday(DateTime today, int hour, int minute) {
    // DateTime.sunday is 7, so the offset is 7 minus the current weekday, and a
    // Sunday resolves to seven days out rather than today.
    final delta = 7 - today.weekday;
    return DateTime(
      today.year,
      today.month,
      today.day + (delta == 0 ? 7 : delta),
      hour,
      minute,
    );
  }
}

/// Build the ladder input from live state and reschedule. This is the single
/// entry point every caller should use.
Future<void> syncLearnReminders({
  required LearnContent content,
  required LearnProgress progress,
  required LearnReminderPrefs prefs,
  String? hook,
}) async {
  final path = LearnPath(content, progress);
  await LearnReminder.instance.resync(
    prefs,
    LearnLadderInput(
      streak: progress.streak,
      best: progress.best,
      lastDay: progress.lastDay,
      nextLessonTitle: path.nextLesson?.title,
      unitTitle: path.currentUnit?.title,
      unitDone: path.unitDone,
      unitTotal: path.unitTotal,
      nextUnitTitle: path.nextLockedUnit?.title,
      daysActive7: progress.daysActiveLast7,
      hook: hook,
    ),
  );
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

/// Opt-in card for the Learn home: a toggle and a daily time. Reschedules on
/// first frame so the ladder is rebuilt against today's progress every time the
/// learner arrives.
class LearnReminderCard extends ConsumerStatefulWidget {
  const LearnReminderCard({super.key});

  @override
  ConsumerState<LearnReminderCard> createState() => _LearnReminderCardState();
}

class _LearnReminderCardState extends ConsumerState<LearnReminderCard> {
  // The card is a one-time nudge in Learn: it shows on the first visit, marks
  // itself seen, and thereafter lives only in Settings > Notifications. The
  // reschedule still runs every open, whether or not the card renders.
  bool _firstRun = false;

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(learnReminderProvider.notifier);
    _firstRun = !ctrl.seen;
    if (_firstRun) ctrl.markSeen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncLearnReminders(
        content: ref.read(learnProvider),
        progress: ref.read(learnProgressProvider),
        prefs: ref.read(learnReminderProvider),
      );
    });
  }

  Future<void> _pickTime(LearnReminderPrefs prefs) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: prefs.time,
    );
    if (picked == null || !mounted) return;
    await ref
        .read(learnReminderProvider.notifier)
        .setTime(
          picked.hour,
          picked.minute,
          content: ref.read(learnProvider),
          progress: ref.read(learnProgressProvider),
        );
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
                  onChanged: (v) =>
                      ref.read(learnReminderProvider.notifier).setEnabled(
                            v,
                            content: ref.read(learnProvider),
                            progress: ref.read(learnProgressProvider),
                          ),
                ),
              ],
            ),
          ),
          if (prefs.enabled)
            InkWell(
              onTap: () => _pickTime(prefs),
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

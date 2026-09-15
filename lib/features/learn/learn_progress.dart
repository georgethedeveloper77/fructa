import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// On-device learn progress. Stored in the already-open `settings` box (like
/// subscriptions/app-lock), so no new box or main() change. Nothing here is
/// tied to a user or synced. It is this device's XP, streak and completions.
class LearnProgress {
  final Set<String> completed; // lesson ids
  final int xp;
  final int streak;
  final String? lastDay; // yyyy-mm-dd of the last completion

  /// Highest streak ever reached on this device. Kept so the reset notice can
  /// state what was lost as a target rather than a scolding.
  final int best;

  /// yyyy-mm-dd of every day a lesson was completed, most recent last, capped
  /// at 60 entries. Days rather than lesson counts: the questions worth asking
  /// are "did they show up" and "how many of the last seven", and a day list
  /// answers both at a fraction of the storage.
  final List<String> activeDays;

  const LearnProgress({
    this.completed = const {},
    this.xp = 0,
    this.streak = 0,
    this.lastDay,
    this.best = 0,
    this.activeDays = const [],
  });

  bool isDone(String lessonId) => completed.contains(lessonId);

  bool get completedToday => lastDay != null && lastDay == _dayStr(DateTime.now());

  /// How many of the last seven calendar days, today included, had a
  /// completion.
  int get daysActiveLast7 {
    final now = DateTime.now();
    final window = <String>{
      for (var i = 0; i < 7; i++) _dayStr(now.subtract(Duration(days: i))),
    };
    return activeDays.where(window.contains).length;
  }

  /// What the streak becomes if a new lesson is completed right now. Mirrors
  /// [LearnProgressController.completeLesson] exactly.
  ///
  /// The win screen used to show `streak + 1`, which overstated by one for the
  /// second and every later lesson on the same day: six days of work rendered
  /// as seven, and then the reminder that evening said six. Two surfaces
  /// disagreeing about a number the learner is emotionally invested in is the
  /// fastest way to lose their trust in every other number in the app.
  int get streakIfCompletedNow {
    final now = DateTime.now();
    final today = _dayStr(now);
    final yesterday = _dayStr(now.subtract(const Duration(days: 1)));

    if (lastDay == null) return 1;
    if (lastDay == today) return streak == 0 ? 1 : streak;
    if (lastDay == yesterday) return streak + 1;
    return 1;
  }
}

String _dayStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class LearnProgressController extends Notifier<LearnProgress> {
  Box get _box => Hive.box('settings');

  @override
  LearnProgress build() {
    final completed =
        ((_box.get('learn_completed', defaultValue: <String>[]) as List)
                .cast<String>())
            .toSet();
    final streak = _box.get('learn_streak', defaultValue: 0) as int;
    return LearnProgress(
      completed: completed,
      xp: _box.get('learn_xp', defaultValue: 0) as int,
      streak: streak,
      lastDay: _box.get('learn_last_day') as String?,
      // Seeded from the live streak so a device upgrading into this build does
      // not report a best of zero against a streak it has already earned.
      best: _box.get('learn_best', defaultValue: streak) as int,
      activeDays:
          ((_box.get('learn_days', defaultValue: <String>[]) as List)
                  .cast<String>())
              .toList(),
    );
  }

  /// Mark a lesson done once. Idempotent, so replaying a lesson never re-awards
  /// XP. Advances the streak: same day keeps it, yesterday +1, a gap resets.
  Future<void> completeLesson(String lessonId, int xpGain) async {
    if (state.completed.contains(lessonId)) return;

    final now = DateTime.now();
    final today = _dayStr(now);
    final streak = state.streakIfCompletedNow;

    final completed = {...state.completed, lessonId};
    final xp = state.xp + xpGain;
    final best = streak > state.best ? streak : state.best;

    final days = [...state.activeDays];
    if (days.isEmpty || days.last != today) days.add(today);
    if (days.length > 60) days.removeRange(0, days.length - 60);

    await _box.put('learn_completed', completed.toList());
    await _box.put('learn_xp', xp);
    await _box.put('learn_streak', streak);
    await _box.put('learn_last_day', today);
    await _box.put('learn_best', best);
    await _box.put('learn_days', days);

    state = LearnProgress(
      completed: completed,
      xp: xp,
      streak: streak,
      lastDay: today,
      best: best,
      activeDays: days,
    );
  }
}

final learnProgressProvider =
    NotifierProvider<LearnProgressController, LearnProgress>(
      LearnProgressController.new,
    );

/// Where inside a lesson the learner stopped.
///
/// This is deliberately not part of [LearnProgress]. Progress is a record of
/// what was earned and survives forever; a resume point is a hint that expires,
/// applies to exactly one lesson, and is thrown away the moment that lesson is
/// finished. Folding it into the progress state would put a volatile field
/// inside a value that half the Learn UI rebuilds on.
///
/// It matters because the reminder ladder now says things like "4 of 7 through
/// Money market funds, pick up at Withholding tax on interest". Dropping that
/// learner at step one of a lesson they were most of the way through makes the
/// notification a small lie.
class LearnResume {
  LearnResume._();

  static const _key = 'learn_resume';

  /// Past this, restarting beats resuming. Coming back to the middle of an
  /// explanation you last read three weeks ago is worse than reading it again.
  static const maxAge = Duration(hours: 48);

  static Box get _box => Hive.box('settings');

  static Future<void> save(String lessonId, int step) => _box.put(_key, {
        'lesson': lessonId,
        'step': step,
        'at': DateTime.now().toIso8601String(),
      });

  static Future<void> clear() => _box.delete(_key);

  /// The step to open [lessonId] at, or null to start from the beginning.
  ///
  /// Every stored value is re-validated rather than trusted. Lesson content is
  /// admin-authored and republished, so a saved index can outlive the steps it
  /// pointed at: a lesson edited from nine steps down to four would otherwise
  /// resume at step seven and throw on a range error.
  static int? stepFor(String lessonId, int stepCount) {
    final raw = _box.get(_key);
    if (raw is! Map) return null;
    if (raw['lesson'] != lessonId) return null;

    final at = DateTime.tryParse((raw['at'] as String?) ?? '');
    if (at == null || DateTime.now().difference(at) > maxAge) return null;

    final step = (raw['step'] as num?)?.toInt();
    if (step == null || step <= 0 || step >= stepCount) return null;

    return step;
  }
}

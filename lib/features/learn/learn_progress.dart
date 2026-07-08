import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

/// On-device learn progress. Stored in the already-open `settings` box (like
/// subscriptions/app-lock), so no new box or main() change. Nothing here is
/// tied to a user or synced  it's this device's XP, streak and completions.
class LearnProgress {
  final Set<String> completed; // lesson ids
  final int xp;
  final int streak;
  final String? lastDay; // yyyy-mm-dd of the last completion

  const LearnProgress({
    this.completed = const {},
    this.xp = 0,
    this.streak = 0,
    this.lastDay,
  });

  bool isDone(String lessonId) => completed.contains(lessonId);
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
    return LearnProgress(
      completed: completed,
      xp: _box.get('learn_xp', defaultValue: 0) as int,
      streak: _box.get('learn_streak', defaultValue: 0) as int,
      lastDay: _box.get('learn_last_day') as String?,
    );
  }

  /// Mark a lesson done once. Idempotent  replaying a lesson never re-awards
  /// XP. Advances the streak: same day keeps it, yesterday +1, a gap resets.
  Future<void> completeLesson(String lessonId, int xpGain) async {
    if (state.completed.contains(lessonId)) return;

    final now = DateTime.now();
    final today = _dayStr(now);
    final yesterday = _dayStr(now.subtract(const Duration(days: 1)));
    final last = state.lastDay;

    final int streak;
    if (last == null) {
      streak = 1;
    } else if (last == today) {
      streak = state.streak == 0 ? 1 : state.streak;
    } else if (last == yesterday) {
      streak = state.streak + 1;
    } else {
      streak = 1;
    }

    final completed = {...state.completed, lessonId};
    final xp = state.xp + xpGain;

    await _box.put('learn_completed', completed.toList());
    await _box.put('learn_xp', xp);
    await _box.put('learn_streak', streak);
    await _box.put('learn_last_day', today);

    state = LearnProgress(
      completed: completed,
      xp: xp,
      streak: streak,
      lastDay: today,
    );
  }
}

final learnProgressProvider =
    NotifierProvider<LearnProgressController, LearnProgress>(
      LearnProgressController.new,
    );

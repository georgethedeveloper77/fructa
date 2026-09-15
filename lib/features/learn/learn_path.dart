import '../../data/models/learn.dart';
import 'learn_progress.dart';

/// Where a learner currently stands on the path.
///
/// The unlock rules were already implemented inside `learn_home_page.dart` as
/// private methods. They now live here because two other places need the same
/// answers and must not be allowed to derive them differently: the reminder
/// ladder (which names the next lesson in its copy) and the lesson player
/// (which hands off to the next lesson instead of dropping the learner back on
/// the path). A reminder that says "next up: X" while the player opens Y is
/// worse than a reminder that says nothing.
class LearnPath {
  const LearnPath(this.content, this.progress);

  final LearnContent content;
  final LearnProgress progress;

  LearnUnit? unitById(String? id) {
    if (id == null) return null;
    for (final u in content.units) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// A unit opens when its prerequisite unit is fully done. A missing or
  /// unknown prerequisite opens it, which keeps a content typo from bricking
  /// the whole path.
  bool unlocked(LearnUnit u) {
    if (u.unlockAfter == null) return true;
    final prereq = unitById(u.unlockAfter);
    return prereq == null || prereq.lessons.every((l) => progress.isDone(l.id));
  }

  List<LearnUnit> get unlockedUnits =>
      content.units.where(unlocked).toList(growable: false);

  List<LearnUnit> get lockedUnits =>
      content.units.where((u) => !unlocked(u)).toList(growable: false);

  /// The first lesson the learner can actually open. Lessons unlock in order
  /// inside a unit, so the first one not done is by construction the next one.
  LearnLesson? get nextLesson {
    for (final u in unlockedUnits) {
      for (final l in u.lessons) {
        if (!progress.isDone(l.id)) return l;
      }
    }
    return null;
  }

  /// The unit that [nextLesson] belongs to.
  LearnUnit? get currentUnit {
    for (final u in unlockedUnits) {
      for (final l in u.lessons) {
        if (!progress.isDone(l.id)) return u;
      }
    }
    return null;
  }

  /// Lessons done in [currentUnit], and how many it holds. Both zero when the
  /// path is finished, which callers must read as "no progress line to show"
  /// rather than "zero progress".
  int get unitDone {
    final u = currentUnit;
    if (u == null) return 0;
    return u.lessons.where((l) => progress.isDone(l.id)).length;
  }

  int get unitTotal => currentUnit?.lessons.length ?? 0;

  /// The next unit still sealed behind a prerequisite, used for the line that
  /// tells a learner what finishing this unit buys them.
  LearnUnit? get nextLockedUnit {
    final locked = lockedUnits;
    return locked.isEmpty ? null : locked.first;
  }

  /// Every published lesson is done. The streak ladder must stop naming
  /// lessons at this point and fall back to market-tied copy.
  bool get isComplete => content.units.isNotEmpty && nextLesson == null;

  /// The path as it will look once [lessonId] is marked done. The win screen
  /// renders before the completion is written, so asking the live path for
  /// "what is next" there returns the lesson the learner has just finished.
  LearnPath assumingDone(String lessonId) => LearnPath(
        content,
        LearnProgress(
          completed: {...progress.completed, lessonId},
          xp: progress.xp,
          streak: progress.streak,
          lastDay: progress.lastDay,
          best: progress.best,
          activeDays: progress.activeDays,
        ),
      );
}

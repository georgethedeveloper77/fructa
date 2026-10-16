import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/i18n.dart';
import '../../core/local_notify.dart';
import '../../core/settings_prefs.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../wrap/wrap_engine.dart';
import 'report_archive.dart';
import '../wrap/wrap_feed.dart';

// ── Seen state ─────────────────────────────────────────────────────────────

/// Remembers one id (a week or a month) the user has opened, in the settings
/// box, so NEW tags and dots clear once and stay cleared across launches.
class SeenNotifier extends Notifier<String?> {
  SeenNotifier(this._key);

  final String _key;

  Box get _box => Hive.box('settings');

  @override
  String? build() => _box.get(_key) as String?;

  Future<void> mark(String id) async {
    if (state == id) return;
    state = id;
    await _box.put(_key, id);
  }
}

/// The week id ([WrapArchive.weekId]) of the last live wrap the user watched.
final wrapSeenProvider = NotifierProvider<SeenNotifier, String?>(
  () => SeenNotifier('wrap_seen_week'),
);

/// The id of the last day's stories the user watched (`day-2026-10-16`).
final daySeenProvider = NotifierProvider<SeenNotifier, String?>(
  () => SeenNotifier('wrap_seen_day'),
);

/// The month id ([monthId]) of the last monthly report the user opened.
final reportSeenProvider = NotifierProvider<SeenNotifier, String?>(
  () => SeenNotifier('report_seen_month'),
);

String monthId(DateTime from) => 'm-${from.year}-${from.month}';

/// This week's wrap has stories the user has not watched yet.
final wrapUnseenProvider = Provider.autoDispose<bool>((ref) {
  final wrap = ref.watch(weeklyWrapProvider);
  if (wrap.market.isEmpty) return false;
  return ref.watch(wrapSeenProvider) != WrapArchive.weekId(wrap.to);
});

/// Last month's report, when it has the user's own figures in it and they
/// have not opened it yet. Null otherwise, so callers show nothing.
final newReportProvider = Provider.autoDispose<MonthWrap?>((ref) {
  if (!ref.watch(wrapPersonalUnlockedProvider)) return null;
  final m = ref.watch(monthWrapProvider);
  if (!m.slides.any((s) => s.personal)) return null;
  return ref.watch(reportSeenProvider) == monthId(m.from) ? null : m;
});

// ── Notifications ──────────────────────────────────────────────────────────

/// Raises the story and report notifications, only when there is something
/// to see. Watched once by the main scaffold, which keeps it alive.
///
/// Everything is worked out on the phone from the snapshot and the user's own
/// data, so the timed ones (the wrap, the monthly report, statement due) are
/// scheduled ahead and rebuilt on every refresh: a week with no stories, a
/// report with nothing in it, or a wrap already watched cancels its
/// notification instead of sending an empty one. None of them carry amounts.
final reportNotifyRunnerProvider = Provider<void>((ref) {
  Timer? debounce;
  void kick() {
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 2), () => _sync(ref));
  }

  ref.onDispose(() => debounce?.cancel());
  ref.listen(weeklyWrapProvider, (_, _) => kick(), fireImmediately: true);
  ref.listen(settingsControllerProvider, (_, _) => kick());
  ref.listen(holdingsProvider, (_, _) => kick());
  ref.listen(statementsProvider, (_, _) => kick());
  ref.listen(wrapPersonalUnlockedProvider, (_, _) => kick());
  ref.listen(wrapSeenProvider, (_, _) => kick());
});

int _id(String key) => key.hashCode & 0x7fffffff;

/// Notification id for this week's wrap, so the viewer can cancel it.
int wrapNotificationId(DateTime d) => _id('wrap|${WrapArchive.weekId(d)}');

/// Friday 18:00 of the Monday-based week holding [d].
DateTime _weekClose(DateTime d) {
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return DateTime(monday.year, monday.month, monday.day + 4, 18);
}

Future<void> _sync(Ref ref) async {
  final prefs = ref.read(settingsControllerProvider);
  final on = prefs.masterAlerts;
  final unlocked = ref.read(wrapPersonalUnlockedProvider);
  final now = DateTime.now();
  final wrap = ref.read(weeklyWrapProvider);
  final week = WrapArchive.weekId(wrap.to);

  // ── Weekly wrap: Friday evening, only for a week with stories ────────────
  // Once the server publishes wraps it sends this push itself, with the
  // week's real lead story, so the phone's own reminder stands down.
  final wrapId = wrapNotificationId(wrap.to);
  final close = _weekClose(now);
  final serverPush = ref.read(wrapFeedProvider).value != null;
  if (on &&
      !serverPush &&
      prefs.weeklyDigest &&
      wrap.market.isNotEmpty &&
      ref.read(wrapSeenProvider) != week &&
      close.isAfter(now)) {
    final mine = unlocked && wrap.personal.isNotEmpty;
    // A fund name, never a figure: it is written now and read on Friday.
    WrapSlide? lead;
    for (final s in wrap.market) {
      if (s.fundId != null) {
        lead = s;
        break;
      }
    }
    await LocalNotify.schedule(
      id: wrapId,
      title: t('notify.wrap.title'),
      body: lead == null
          ? t(mine ? 'notify.wrap.plainYou' : 'notify.wrap.plain')
          : t(mine ? 'notify.wrap.bodyYou' : 'notify.wrap.body', {
              'lead': lead.title,
            }),
      when: close,
      target: 'wrap',
      report: true,
    );
  } else {
    await LocalNotify.cancelIds([wrapId]);
  }

  // ── A fund the user holds or follows made the wrap: straight away ────────
  if (on && prefs.fundStories) {
    final mine = <String>{
      ...ref.read(subscriptionsProvider),
      for (final h in ref.read(holdingsProvider))
        if (!h.isSacco) h.fundId,
    };
    final byId = ref.read(fundsByIdProvider);
    var sent = 0;
    for (final e in wrap.badges.entries) {
      // Two at most per refresh; more than that is how alerts get muted.
      if (sent >= 2) break;
      final f = byId[e.key];
      if (!mine.contains(e.key) || f == null || f.currentRate == null) {
        continue;
      }
      if (!LocalNotify.claim('fundstory|$week|${e.key}')) continue;
      await LocalNotify.show(
        id: _id('fundstory|$week|${e.key}'),
        title: t('notify.fund.title', {'fund': f.name}),
        body: t('notify.fund.body', {
          'badge': t(e.value.labelKey),
          'rate': '${f.currentRate!.toStringAsFixed(2)}%',
        }),
        target: 'wrap/${e.value.slideIndex}',
        report: true,
      );
      sent++;
    }
  }

  // ── Monthly report: the 1st, when the user has holdings to report on ─────
  final next = DateTime(now.year, now.month + 1, 1, 9);
  final monthNoteId = _id('month|${next.year}-${next.month}');
  if (on &&
      prefs.monthlyReport &&
      unlocked &&
      ref.read(holdingsProvider).isNotEmpty) {
    await LocalNotify.schedule(
      id: monthNoteId,
      title: t('notify.month.title', {
        'month': monthName(DateTime(now.year, now.month)).split(' ').first,
      }),
      body: t('notify.month.body'),
      when: next,
      target: 'reports',
      report: true,
    );
  } else {
    await LocalNotify.cancelIds([monthNoteId]);
  }

  // ── Statement due: the morning each manager usually releases it ──────────
  final cfg = ref.read(remoteConfigProvider);
  final statements =
      ref.read(statementsProvider).value ?? const <SavedStatement>[];
  for (final key in {for (final s in statements) s.data.managerKey}) {
    final m = cfg.statementManager(key);
    final id = _id('stmt|$key');
    final day = m?.releaseDay;
    if (m == null || day == null || !(on && prefs.statementDue && unlocked)) {
      await LocalNotify.cancelIds([id]);
      continue;
    }
    var at = DateTime(now.year, now.month, day, 8);
    if (!at.isAfter(now)) at = DateTime(now.year, now.month + 1, day, 8);
    await LocalNotify.schedule(
      id: id,
      title: t('notify.stmt.title', {'manager': m.name}),
      body: t('notify.stmt.body'),
      when: at,
      target: 'reports',
      report: true,
    );
  }
}

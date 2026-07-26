import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';

import '../core/local_notify.dart';
import '../core/push.dart';
import '../core/settings_prefs.dart';
import 'models/alert.dart';
import 'models/fund.dart';
import 'models/holding.dart';
import 'models/nav_history.dart';
import 'models/rate_history.dart';
import 'models/stock_history.dart';
import 'repositories/holdings_repository.dart';
import 'repositories/rates_repository.dart';
import 'sources/local/rates_cache.dart';
import 'sources/remote/rates_api.dart';

// rates ----------------------------------------------------------------------
final ratesApiProvider = Provider((ref) => RatesApi());
final ratesCacheProvider = Provider((ref) => RatesCache(Hive.box('rates')));
final ratesRepositoryProvider = Provider(
  (ref) =>
      RatesRepository(ref.read(ratesApiProvider), ref.read(ratesCacheProvider)),
);

/// Above this many followed funds moving in one refresh, collapse to a single
/// summary notification instead of buzzing the phone once per fund.
const _kMaxIndividualRateNotifications = 3;

class RatesNotifier extends AsyncNotifier<List<Fund>> {
  RatesRepository get _repo => ref.read(ratesRepositoryProvider);

  @override
  Future<List<Fund>> build() async {
    final cached = await _repo.cachedOrBundled();
    Future.microtask(_refresh);
    return cached;
  }

  Future<void> _refresh() async {
    final old = state.value;
    try {
      final fresh = await _repo.fetchIfChanged();
      if (fresh != null) {
        if (old != null) _detectAlerts(old, fresh);
        state = AsyncData(fresh);
      }
    } catch (_) {}
  }

  // On a fresh snapshot, raise an alert for any followed fund whose rate moved.
  // Held funds are auto-followed (HoldingsNotifier.setBalance -> ensureFollow),
  // so this single `subs` check already covers "alerts on funds I hold".
  //
  // This detection is local and deterministic, and it has never been the flaky
  // part. What WAS flaky is the four-hop chain that had to succeed for the same
  // fact to reach the drawer: tag lands at OneSignal, filter matches, FCM
  // delivers, Doze does not eat it. So the app knew a followed fund had moved
  // and said nothing, while a far more fragile path was the only thing that
  // could tell the user.
  //
  // It now raises a drawer notification directly. LocalNotify de-duplicates on
  // (fund, resulting rate), so re-detecting the same move across a cold start
  // does not notify twice.
  void _detectAlerts(List<Fund> old, List<Fund> fresh) {
    final subs = ref.read(subscriptionsProvider);
    if (subs.isEmpty) return;

    final oldById = {for (final f in old) f.id: f};
    final alerts = ref.read(alertsProvider.notifier);
    final moved = <({Fund fund, double oldRate, double newRate})>[];

    for (final f in fresh) {
      if (!subs.contains(f.id)) continue;
      final pr = oldById[f.id]?.currentRate;
      final nr = f.currentRate;
      if (pr != null && nr != null && pr != nr) {
        alerts.add(
          RateAlert(fundId: f.id, oldRate: pr, newRate: nr, at: DateTime.now()),
        );
        moved.add((fund: f, oldRate: pr, newRate: nr));
      }
    }

    if (moved.isEmpty) return;

    // The in-app alerts feed above is populated unconditionally: it is a list
    // the user chose to open, not an interruption. The DRAWER notification is an
    // interruption, so it obeys the same two switches the server-side push now
    // obeys. Before this the local path would have buzzed a user who had turned
    // rate-move alerts off, which is precisely the bug this delivery is fixing
    // on the server, reintroduced on the client.
    final prefs = ref.read(settingsControllerProvider);
    if (!prefs.masterAlerts || !prefs.rateMoves) return;

    if (moved.length > _kMaxIndividualRateNotifications) {
      unawaited(LocalNotify.rateChangeSummary(moved.length));
      return;
    }

    for (final m in moved) {
      unawaited(
        LocalNotify.rateChange(
          fundId: m.fund.id,
          name: m.fund.name,
          oldRate: m.oldRate,
          newRate: m.newRate,
        ),
      );
    }
  }

  Future<void> refresh() => _refresh();
}

final ratesProvider = AsyncNotifierProvider<RatesNotifier, List<Fund>>(
  RatesNotifier.new,
);

final fundsByIdProvider = Provider<Map<String, Fund>>((ref) {
  final funds = ref.watch(ratesProvider).value ?? const [];
  return {for (final f in funds) f.id: f};
});

final historyProvider = FutureProvider.autoDispose
    .family<List<RateHistory>, String>((ref, fundId) {
      return ref.read(ratesApiProvider).getHistory(fundId);
    });

/// Per-fund NAV history for a priced fund's detail chart. autoDispose, so
/// leaving the page drops it, exactly like [historyProvider].
///
/// A fund has one of these series or the other, never both: a yield fund logs
/// rates and a priced fund logs prices. That is why they are separate providers
/// off separate tables rather than one series with a unit hidden in a
/// neighbouring column.
final navHistoryProvider = FutureProvider.autoDispose
    .family<List<NavHistory>, String>((ref, fundId) {
      return ref.read(ratesApiProvider).getNavHistory(fundId);
    });

/// The other live classes of one multi-class product, including [fundId] itself,
/// ordered by lock-in and then by label.
///
/// Etica Special Wealth is one fund sold as A, B and C: 6, 9 and 12 month
/// lock-ins at 2.25%, 2.00% and 1.75%, yielding 13.38%, 13.55% and 13.72%.
/// Three rows in the database, one product to a person choosing between them.
///
/// Ordered by lock-in deliberately, and it is the point of the whole feature:
/// the classes line up cheapest-to-enter first, so the yield rising down the
/// list reads as what it is, the price of tying money up for longer, rather
/// than as one class simply being better than its siblings.
///
/// Returns an empty list when the fund has no class group, which is nearly
/// every fund, so callers render nothing without asking whether they should.
final classSiblingsProvider = Provider.family<List<Fund>, String>((ref, fundId) {
  final byId = ref.watch(fundsByIdProvider);
  final me = byId[fundId];
  final group = me?.classGroup;
  if (me == null || group == null || group.isEmpty) return const [];

  // No status filter: the snapshot only carries live funds, so anything
  // reachable through fundsByIdProvider is already published.
  final out = byId.values.where((f) => f.classGroup == group).toList();
  if (out.length < 2) return const [];

  out.sort((a, b) {
    final la = a.lockInMonths ?? 0;
    final lb = b.lockInMonths ?? 0;
    if (la != lb) return la.compareTo(lb);
    return (a.classLabel ?? '').compareTo(b.classLabel ?? '');
  });
  return out;
});

/// Per-stock price history for the detail chart. autoDispose, so leaving the
/// page drops it: this is the one read in the app that is not the snapshot.
final stockHistoryProvider = FutureProvider.autoDispose
    .family<List<StockHistory>, String>((ref, stockId) {
      return ref.read(ratesApiProvider).getStockHistory(stockId);
    });

// holdings -------------------------------------------------------------------
final holdingsRepositoryProvider = Provider(
  (ref) => HoldingsRepository(Hive.box('holdings')),
);

class HoldingsNotifier extends Notifier<List<Holding>> {
  HoldingsRepository get _repo => ref.read(holdingsRepositoryProvider);

  @override
  List<Holding> build() => _repo.all();

  Future<void> setBalance(
    String fundId,
    String currency,
    double balance, {
    HoldingKind kind = HoldingKind.fund,
  }) async {
    await _repo.setBalance(fundId, currency, balance, kind: kind);
    state = _repo.all();
    // A fund you hold is a fund you want alerts on: follow it (add-only, so it
    // never toggles off an existing follow). The user can unfollow from the
    // fund page if they don't want the nudges.
    //
    // NOT for SACCOs. `subscriptionsProvider` is the FUND tag namespace, the one
    // emit-events targets on a fund rate change. Putting a SACCO id in it would
    // write a tag nothing ever matches, so the user would be silently following
    // nothing, and it would sit in the set that drives "alerts on funds I hold".
    // SACCO follows need their own namespace, exactly as stock follows do.
    if (kind == HoldingKind.fund) {
      await ref.read(subscriptionsProvider.notifier).ensureFollow(fundId);
    }
  }

  Future<void> remove(String fundId) async {
    await _repo.remove(fundId);
    state = _repo.all();
    // Intentionally does NOT unfollow: removing a holding leaves the follow in
    // place so a re-add or a "still watching it" case keeps working.
  }
}

final holdingsProvider = NotifierProvider<HoldingsNotifier, List<Holding>>(
  HoldingsNotifier.new,
);

// subscriptions (followed funds) ---------------------------------------------
class SubscriptionsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      ((Hive.box('settings').get('subs', defaultValue: <String>[]) as List)
              .cast<String>())
          .toSet();

  /// Returns true when the fund is now followed, false when it was unfollowed.
  /// The caller needs to know which, because turning a follow ON is the moment
  /// the app has to make sure it can actually deliver on the promise.
  Future<bool> toggle(String fundId) async {
    final s = {...state};
    final added = s.add(fundId);
    if (!added) s.remove(fundId);
    await Hive.box('settings').put('subs', s.toList());
    state = s;

    if (added) {
      await Push.follow(fundId);
    } else {
      await Push.unfollow(fundId);
    }
    return added;
  }

  /// Add-only follow: no-op if already following. Used by auto-follow on
  /// add-holding and by the first-open follow coach, so neither can
  /// accidentally toggle a fund OFF.
  Future<void> ensureFollow(String fundId) async {
    if (state.contains(fundId)) return;
    final s = {...state}..add(fundId);
    await Hive.box('settings').put('subs', s.toList());
    state = s;
    await Push.follow(fundId);
  }
}

final subscriptionsProvider =
    NotifierProvider<SubscriptionsNotifier, Set<String>>(
      SubscriptionsNotifier.new,
    );

// stock follows --------------------------------------------------------------
/// Followed STOCKS, kept in their own Hive key and their own OneSignal tag
/// namespace (`follow_stock_<id>`, see Push.stockTagKey).
///
/// Separate from `subscriptionsProvider` on purpose. Fund ids and stock ids are
/// both slugs, so one shared set could not tell them apart, and a fund follow
/// would have silently subscribed the user to a stock with the same slug. It
/// also means every fund tag already sitting on an installed device keeps
/// working untouched.
///
/// What a stock follow actually buys you is the book-closure alert: own the
/// share by the date the register closes or you do not get the dividend. It is
/// NOT a price alert. A daily "SCOM moved 2%" across sixty four counters is
/// noise, and it teaches the exact reflex the Learn course argues against.
class StockSubscriptionsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      ((Hive.box('settings').get('stockSubs', defaultValue: <String>[]) as List)
              .cast<String>())
          .toSet();

  Future<bool> toggle(String stockId) async {
    final s = {...state};
    final added = s.add(stockId);
    if (!added) s.remove(stockId);
    await Hive.box('settings').put('stockSubs', s.toList());
    state = s;

    if (added) {
      await Push.followStock(stockId);
    } else {
      await Push.unfollowStock(stockId);
    }
    return added;
  }
}

final stockSubscriptionsProvider =
    NotifierProvider<StockSubscriptionsNotifier, Set<String>>(
      StockSubscriptionsNotifier.new,
    );

// alerts feed ----------------------------------------------------------------
class AlertsNotifier extends Notifier<List<RateAlert>> {
  Box get _box => Hive.box('alerts');

  @override
  List<RateAlert> build() {
    final items =
        _box.values
            .map((v) => RateAlert.fromMap(Map<String, dynamic>.from(v as Map)))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return items;
  }

  Future<void> add(RateAlert a) async {
    await _box.add(a.toMap());
    state = [a, ...state];
  }
}

final alertsProvider = NotifierProvider<AlertsNotifier, List<RateAlert>>(
  AlertsNotifier.new,
);

final alertsSeenProvider = StateProvider<DateTime>((ref) {
  final s = Hive.box('settings').get('alertsSeen') as String?;
  return s != null ? DateTime.parse(s) : DateTime.fromMillisecondsSinceEpoch(0);
});

final unreadAlertsProvider = Provider<int>((ref) {
  final seen = ref.watch(alertsSeenProvider);
  return ref.watch(alertsProvider).where((a) => a.at.isAfter(seen)).length;
});

// push delivery state --------------------------------------------------------
/// Reads what OneSignal actually holds for this device. autoDispose so the
/// Settings panel gets a fresh read every time it is opened rather than a stale
/// one from an hour ago.
final pushDiagnosticsProvider = FutureProvider.autoDispose<PushDiagnostics>(
  (ref) => Push.diagnostics(),
);

// settings -------------------------------------------------------------------
class AppLockNotifier extends Notifier<bool> {
  @override
  bool build() =>
      Hive.box('settings').get('appLock', defaultValue: false) as bool;

  Future<void> set(bool v) async {
    await Hive.box('settings').put('appLock', v);
    state = v;
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);

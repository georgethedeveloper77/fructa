import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../core/push.dart';
import 'models/alert.dart';
import 'models/fund.dart';
import 'models/holding.dart';
import 'models/rate_history.dart';
import 'models/stock_history.dart';
import 'repositories/holdings_repository.dart';
import 'repositories/rates_repository.dart';
import 'sources/local/rates_cache.dart';
import 'sources/remote/rates_api.dart';

// ── rates ────────────────────────────────────────────────────────────
final ratesApiProvider = Provider((ref) => RatesApi());
final ratesCacheProvider = Provider((ref) => RatesCache(Hive.box('rates')));
final ratesRepositoryProvider = Provider(
  (ref) =>
      RatesRepository(ref.read(ratesApiProvider), ref.read(ratesCacheProvider)),
);

class RatesNotifier extends AsyncNotifier<List<Fund>> {
  RatesRepository get _repo => ref.read(ratesRepositoryProvider);

  @override
  Future<List<Fund>> build() async {
    final cached = await _repo.cachedOrBundled();
    Future.microtask(_refresh);
    return cached;
  }

  Future<void> _refresh() async {
    final old = state.valueOrNull;
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
  void _detectAlerts(List<Fund> old, List<Fund> fresh) {
    final subs = ref.read(subscriptionsProvider);
    if (subs.isEmpty) return;
    final oldById = {for (final f in old) f.id: f};
    final alerts = ref.read(alertsProvider.notifier);
    for (final f in fresh) {
      if (!subs.contains(f.id)) continue;
      final pr = oldById[f.id]?.currentRate;
      final nr = f.currentRate;
      if (pr != null && nr != null && pr != nr) {
        alerts.add(
          RateAlert(fundId: f.id, oldRate: pr, newRate: nr, at: DateTime.now()),
        );
      }
    }
  }

  Future<void> refresh() => _refresh();
}

final ratesProvider = AsyncNotifierProvider<RatesNotifier, List<Fund>>(
  RatesNotifier.new,
);

final fundsByIdProvider = Provider<Map<String, Fund>>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  return {for (final f in funds) f.id: f};
});

final historyProvider = FutureProvider.autoDispose
    .family<List<RateHistory>, String>((ref, fundId) {
      return ref.read(ratesApiProvider).getHistory(fundId);
    });

/// Per-stock price history for the detail chart. autoDispose, so leaving the
/// page drops it: this is the one read in the app that is not the snapshot.
final stockHistoryProvider = FutureProvider.autoDispose
    .family<List<StockHistory>, String>((ref, stockId) {
      return ref.read(ratesApiProvider).getStockHistory(stockId);
    });

// ── holdings ─────────────────────────────────────────────────────────
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
    // Intentionally does NOT unfollow  removing a holding leaves the follow in
    // place so a re-add or a "still watching it" case keeps working.
  }
}

final holdingsProvider = NotifierProvider<HoldingsNotifier, List<Holding>>(
  HoldingsNotifier.new,
);

// ── subscriptions (followed funds) ───────────────────────────────────
class SubscriptionsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      ((Hive.box('settings').get('subs', defaultValue: <String>[]) as List)
              .cast<String>())
          .toSet();

  Future<void> toggle(String fundId) async {
    final s = {...state};
    final added = s.add(fundId);
    if (!added) s.remove(fundId);
    await Hive.box('settings').put('subs', s.toList());
    state = s;
    if (added) {
      Push.follow(fundId);
    } else {
      Push.unfollow(fundId);
    }
  }

  /// Add-only follow  no-op if already following. Used by auto-follow on
  /// add-holding and by the first-open follow coach, so neither can
  /// accidentally toggle a fund OFF.
  Future<void> ensureFollow(String fundId) async {
    if (state.contains(fundId)) return;
    final s = {...state}..add(fundId);
    await Hive.box('settings').put('subs', s.toList());
    state = s;
    Push.follow(fundId);
  }
}

final subscriptionsProvider =
    NotifierProvider<SubscriptionsNotifier, Set<String>>(
      SubscriptionsNotifier.new,
    );

// ── stock follows ────────────────────────────────────────────────────────────
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

  Future<void> toggle(String stockId) async {
    final s = {...state};
    final added = s.add(stockId);
    if (!added) s.remove(stockId);
    await Hive.box('settings').put('stockSubs', s.toList());
    state = s;
    if (added) {
      Push.followStock(stockId);
    } else {
      Push.unfollowStock(stockId);
    }
  }
}

final stockSubscriptionsProvider =
    NotifierProvider<StockSubscriptionsNotifier, Set<String>>(
      StockSubscriptionsNotifier.new,
    );

// ── alerts feed ──────────────────────────────────────────────────────
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

// ── settings ─────────────────────────────────────────────────────────
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

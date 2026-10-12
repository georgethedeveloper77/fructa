import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../data/providers.dart';

/// Which version of Today the user sees. Derived on device from what they
/// have already done, so an existing user lands in the right state the first
/// time they open the update with no migration step.
///
/// The order of the checks is the order of commitment: holding money beats
/// following, following beats browsing, and browsing beats nothing.
enum TodayMode {
  /// No history at all: show the market and two first steps.
  newcomer,

  /// Has opened fund pages but follows and holds nothing.
  viewer,

  /// Follows at least one fund, holds nothing.
  follower,

  /// Holds at least one fund or SACCO.
  investor,
}

final todayModeProvider = Provider<TodayMode>((ref) {
  if (ref.watch(holdingsProvider).isNotEmpty) return TodayMode.investor;
  if (ref.watch(subscriptionsProvider).isNotEmpty) return TodayMode.follower;
  if (ref.watch(recentFundsProvider).isNotEmpty) return TodayMode.viewer;
  return TodayMode.newcomer;
});

/// Fund ids the user opened, newest first, capped at [_kMaxRecent].
///
/// Written by CompanyPage on open. Kept in the shared `settings` box under
/// `recent_funds`, so it survives restarts and rides the same backup rules as
/// the other on-device preferences.
class RecentFundsNotifier extends Notifier<List<String>> {
  static const _key = 'recent_funds';
  static const _kMaxRecent = 8;

  Box get _box => Hive.box('settings');

  @override
  List<String> build() =>
      (_box.get(_key, defaultValue: <String>[]) as List).cast<String>();

  /// Moves [fundId] to the front, dropping the oldest past the cap.
  Future<void> touch(String fundId) async {
    final next = [fundId, ...state.where((id) => id != fundId)];
    final capped = next.length > _kMaxRecent
        ? next.sublist(0, _kMaxRecent)
        : next;
    await _box.put(_key, capped);
    state = capped;
  }
}

final recentFundsProvider = NotifierProvider<RecentFundsNotifier, List<String>>(
  RecentFundsNotifier.new,
);

/// Today cards the user dismissed for good (`start`, `nudge`). Persisted so a
/// card turned to dust does not come back on the next launch.
class TodayDismissalsNotifier extends Notifier<Set<String>> {
  static const _key = 'today_dismissed';

  Box get _box => Hive.box('settings');

  @override
  Set<String> build() =>
      (_box.get(_key, defaultValue: <String>[]) as List).cast<String>().toSet();

  Future<void> dismiss(String card) async {
    final next = {...state, card};
    await _box.put(_key, next.toList());
    state = next;
  }
}

final todayDismissalsProvider =
    NotifierProvider<TodayDismissalsNotifier, Set<String>>(
      TodayDismissalsNotifier.new,
    );

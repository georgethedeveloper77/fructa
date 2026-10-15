import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../snapshot_providers.dart';

/// Thresholds for smart alerts, Should I switch? and the Today cards, tunable
/// from admin (Config, "Pro tuning") without a release. Each falls back to the
/// value the app shipped with when its key is unset.
class ProTuning {
  const ProTuning({
    required this.underpaidPts,
    required this.floorKes,
    required this.floorUsd,
    required this.transitDays,
    required this.rankTop,
    required this.todaySwitchPts,
  });

  /// Credited this many points a year or more below published is underpaid.
  final double underpaidPts;

  /// A switch must gain at least this much a year to be worth it.
  final double floorKes;
  final double floorUsd;

  /// Days money earns nothing between funds.
  final int transitDays;

  /// Places that count as "top" for rank alerts.
  final int rankTop;

  /// Today shows the switch card at this many net points or more.
  final double todaySwitchPts;

  double floorFor(String currency) => currency == 'USD' ? floorUsd : floorKes;
}

final proTuningProvider = Provider<ProTuning>((ref) {
  final c = ref.watch(remoteConfigProvider);
  return ProTuning(
    underpaidPts: c.number('pro.underpaid_pts', 0.30),
    floorKes: c.number('pro.switch_floor_kes', 500),
    floorUsd: c.number('pro.switch_floor_usd', 5),
    transitDays: c.number('pro.transit_days', 3).round().clamp(0, 14),
    rankTop: c.number('pro.rank_top', 5).round().clamp(1, 20),
    todaySwitchPts: c.number('pro.today_switch_pts', 0.25),
  );
});

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/category_colors.dart';
import '../../core/rate_basis.dart';
import '../../data/models/fund.dart';
import '../../data/models/market_event.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/portfolio_math.dart';

/// The rate categories Today can lead with, in tab order.
enum TodayCategory { mmfKes, fixedIncome, special, mmfUsd, tbill }

extension TodayCategoryX on TodayCategory {
  /// i18n key for the tab label.
  String get labelKey => switch (this) {
    TodayCategory.mmfKes => 'today.cat.mmfKes',
    TodayCategory.fixedIncome => 'today.cat.fixedIncome',
    TodayCategory.special => 'today.cat.special',
    TodayCategory.mmfUsd => 'today.cat.mmfUsd',
    TodayCategory.tbill => 'today.cat.tbill',
  };

  /// Short ticker label key.
  String get shortKey => switch (this) {
    TodayCategory.mmfKes => 'today.short.mmfKes',
    TodayCategory.fixedIncome => 'today.short.fixedIncome',
    TodayCategory.special => 'today.short.special',
    TodayCategory.mmfUsd => 'today.short.mmfUsd',
    TodayCategory.tbill => 'today.short.tbill',
  };

  /// Data colour, from the central palettes so a category looks the same on
  /// Today, in Markets and in the allocation charts.
  Color get color => switch (this) {
    TodayCategory.mmfKes => categoryColor('mmf_kes'),
    TodayCategory.fixedIncome => fundTypeColor('fixed_income'),
    TodayCategory.special => fundTypeColor('special'),
    TodayCategory.mmfUsd => categoryColor('mmf_usd'),
    TodayCategory.tbill => categoryColor('tbill'),
  };

  /// Membership. T-bills are not retail fund rows, so only funds need the
  /// retail cut; bills are matched on their legacy category.
  bool matches(Fund f) => switch (this) {
    TodayCategory.mmfKes =>
      f.retail && f.fundType == 'mmf' && f.currency == 'KES',
    TodayCategory.mmfUsd =>
      f.retail && f.fundType == 'mmf' && f.currency == 'USD',
    TodayCategory.fixedIncome =>
      f.retail &&
          f.fundType == 'fixed_income' &&
          f.currency == 'KES' &&
          f.category != 'tbill' &&
          f.category != 'bond',
    TodayCategory.special => f.retail && f.fundType == 'special',
    TodayCategory.tbill => f.category == 'tbill',
  };
}

/// The best fund in one category, ranked on what the holder keeps.
class TodayLeader {
  const TodayLeader(this.category, this.fund, this.net, this.gross);

  final TodayCategory category;
  final Fund fund;

  /// Net of withholding tax (gross for tax-free funds).
  final double net;

  /// The advertised rate.
  final double gross;

  /// The figure on the app's chosen basis ([showNetProvider]).
  double shown(bool showNet) => showNet ? net : gross;
}

/// One leader per category that has a quoting fund, ranked on the basis the
/// app is showing, so the "best rate" is best on the number printed beside it.
/// Categories with nothing to show are absent.
final todayLeadersProvider = Provider<List<TodayLeader>>((ref) {
  final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final showNet = ref.watch(showNetProvider);
  final out = <TodayLeader>[];
  for (final cat in TodayCategory.values) {
    TodayLeader? best;
    for (final f in funds) {
      if (!f.showsYield || f.currentRate == null || !cat.matches(f)) continue;
      final net = f.netRate(wht) ?? f.currentRate!;
      final cand = TodayLeader(cat, f, net, f.currentRate!);
      if (best == null || cand.shown(showNet) > best.shown(showNet)) {
        best = cand;
      }
    }
    if (best != null) out.add(best);
  }
  return out;
});

/// The five best funds in each category, ranked on the basis the app is
/// showing, for the ticker. Categories with nothing to show are absent; the
/// map keeps the tab order.
final todayTopProvider = Provider<Map<TodayCategory, List<TodayLeader>>>((ref) {
  final funds = ref.watch(ratesProvider).value ?? const <Fund>[];
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final showNet = ref.watch(showNetProvider);
  final out = <TodayCategory, List<TodayLeader>>{};
  for (final cat in TodayCategory.values) {
    final rows = <TodayLeader>[
      for (final f in funds)
        if (f.showsYield && f.currentRate != null && cat.matches(f))
          TodayLeader(cat, f, f.netRate(wht) ?? f.currentRate!, f.currentRate!),
    ]..sort((a, b) => b.shown(showNet).compareTo(a.shown(showNet)));
    if (rows.isNotEmpty) out[cat] = rows.take(5).toList();
  }
  return out;
});

/// The category the hero shows. Null means the first available one.
final todayCategoryProvider = StateProvider<TodayCategory?>((_) => null);

/// The leader currently in the hero.
final todayHeroProvider = Provider<TodayLeader?>((ref) {
  final leaders = ref.watch(todayLeadersProvider);
  if (leaders.isEmpty) return null;
  final want = ref.watch(todayCategoryProvider);
  return leaders.firstWhere(
    (l) => l.category == want,
    orElse: () => leaders.first,
  );
});

/// Change in the whole book since the money went in, as a percentage of cost.
///
/// Today shows only this, never an amount: balances live on the Portfolio tab.
/// Holdings whose KES value cannot be computed (USD with no published FX) are
/// left out of both sides rather than counted as zero. Null when nothing can
/// be valued.
final portfolioGainPctProvider = Provider<double?>((ref) {
  final holdings = ref.watch(holdingsProvider);
  if (holdings.isEmpty) return null;
  final fx = ref.watch(usdKesProvider);
  var value = 0.0;
  var cost = 0.0;
  for (final h in holdings) {
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    final v = PortfolioMath.value(
      h,
      ratePercent: s?.ratePercent,
      taxFree: s?.taxFree ?? false,
      usdKes: fx,
    );
    if (v.valueKes == null || v.principalKes == null) continue;
    value += v.valueKes!;
    cost += v.principalKes!;
  }
  if (cost <= 0) return null;
  return (value - cost) / cost * 100;
});

/// The newest market events, newest first.
final todayEventsProvider = Provider<List<MarketEvent>>((ref) {
  final events = [...ref.watch(marketEventsProvider)]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return events;
});

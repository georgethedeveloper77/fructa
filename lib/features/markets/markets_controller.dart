import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

// ─────────────────────────────────────────────────────────────────────────
// Markets stream state. Kept separate from the legacy `market_filters.dart`
// (still used elsewhere) because the locked v5 tabs group tbill+bond into one
// "Bills & bonds" tab, which the single-category filter can't express.
// ─────────────────────────────────────────────────────────────────────────

// One tab per fund type the market actually has. Fixed Income absorbs T-bills
// and bonds (all fixed-income instruments); Equity is CIS equity funds while
// Stocks is NSE-listed shares  kept distinct. Currency is a sub-filter under
// Money Market, not a top-level tab. Empty tabs auto-hide (see
// [visibleMarketTabsProvider]).
enum MarketTab {
  all,
  moneyMarket,
  fixedIncome,
  equity,
  balanced,
  special,
  sacco,
  stock,
}

extension MarketTabX on MarketTab {
  // Display label. category_tabs renders this directly (no i18n key needed).
  String get label => switch (this) {
    MarketTab.all => 'All',
    MarketTab.moneyMarket => 'Money Market',
    MarketTab.fixedIncome => 'Fixed Income',
    MarketTab.equity => 'Equity',
    MarketTab.balanced => 'Balanced',
    MarketTab.special => 'Special',
    MarketTab.sacco => 'SACCO',
    MarketTab.stock => 'Stocks',
  };

  bool matches(Fund f) => switch (this) {
    MarketTab.all => true,
    // fund_type is the live classifier; category was retired (nullable) so
    // matching on it alone would drop every seeded fund. Legacy categories
    // (tbill/bond/sacco/stock) have no fund_type, so they match on category.
    MarketTab.moneyMarket => f.fundType == 'mmf',
    MarketTab.fixedIncome =>
      f.fundType == 'fixed_income' ||
          f.category == 'tbill' ||
          f.category == 'bond',
    MarketTab.equity => f.fundType == 'equity',
    MarketTab.balanced => f.fundType == 'balanced',
    MarketTab.special => f.fundType == 'special',
    MarketTab.sacco => f.category == 'sacco',
    MarketTab.stock => f.category == 'stock',
  };
}

/// Sort pills. `topMovers` is intentionally absent until C1 lands per-fund
/// deltas  sorting by momentum with no momentum data would be a lie.
enum MarketSort { highestYield, lowestMinimum, taxFree }

extension MarketSortX on MarketSort {
  String get label => switch (this) {
    MarketSort.highestYield => 'Highest yield',
    MarketSort.lowestMinimum => 'Lowest minimum',
    MarketSort.taxFree => 'Tax-free',
  };
}

final marketTabProvider = StateProvider<MarketTab>(
  (_) => MarketTab.moneyMarket,
);
final marketSortProvider = StateProvider<MarketSort>(
  (_) => MarketSort.highestYield,
);
final marketSearchProvider = StateProvider<String>((_) => '');
final marketSearchOpenProvider = StateProvider<bool>((_) => false);

/// The list shows the top [kFundsInitial] by the active sort; the rest are
/// revealed by a "Show more" tap. Collapsed again whenever the filter/sort
/// changes (markets_page resets it) so a fresh view starts short.
const kFundsInitial = 20;
final showAllFundsProvider = StateProvider<bool>((_) => false);

/// Tabs that actually have something to show  a retail fund with a rate.
/// Hides empty categories (REIT, Balanced, Islamic…) instead of dead ends.
/// `all` is always present.
final visibleMarketTabsProvider = Provider<List<MarketTab>>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  bool populated(MarketTab t) =>
      t == MarketTab.all ||
      funds.any((f) => f.retail && f.currentRate != null && t.matches(f));
  return MarketTab.values.where(populated).toList();
});

/// Second-tier currency filter shown under the Money Market tab. `null` = all
/// currencies. The available options come from the data (admin-controlled),
/// see [moneyMarketCurrenciesProvider].
final marketMoneyCcyProvider = StateProvider<String?>((_) => null);

/// Distinct currencies present among money-market funds, KES first. Empty or
/// single-entry means no sub-filter is worth showing.
final moneyMarketCurrenciesProvider = Provider<List<String>>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  final set = <String>{};
  for (final f in funds) {
    if (!MarketTab.moneyMarket.matches(f)) continue;
    final ccy = f.currency;
    if (ccy.isNotEmpty) set.add(ccy);
  }
  int rank(String c) => c == 'KES' ? 0 : (c == 'USD' ? 1 : 2);
  final list = set.toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.compareTo(b);
    });
  return list;
});

double _rate(Fund f) => f.currentRate ?? double.negativeInfinity;
num _min(Fund f) => f.minInvest ?? double.infinity; // nulls sort last

/// Net-of-withholding-tax yield  the honest comparator. Tax-free funds keep
/// gross, so they rank on their real advantage. wht comes from remote config.
double _net(Fund f, double wht) {
  final r = f.currentRate;
  if (r == null) return double.negativeInfinity;
  return f.taxFree ? r : r * (1 - wht / 100);
}

/// The visible stream: tab filter → currency sub-filter → search → sort.
/// Tax-free pill both filters to tax-free instruments and orders them by yield.
final streamFundsProvider = Provider<AsyncValue<List<Fund>>>((ref) {
  final rates = ref.watch(ratesProvider);
  final tab = ref.watch(marketTabProvider);
  final ccy = ref.watch(marketMoneyCcyProvider);
  final sort = ref.watch(marketSortProvider);
  final q = ref.watch(marketSearchProvider).trim().toLowerCase();
  final wht = ref.watch(remoteConfigProvider).whtPct;

  return rates.whenData((funds) {
    // Consumer list shows the retail cut only  the dormant/institutional tail
    // (tiny AUM, USD-only duplicates) is hidden but still in the data.
    var list = funds.where((f) => f.retail).where(tab.matches);
    // currency sub-filter only applies within Money Market
    if (tab == MarketTab.moneyMarket && ccy != null) {
      list = list.where((f) => f.currency == ccy);
    }
    if (sort == MarketSort.taxFree) list = list.where((f) => f.taxFree);
    if (q.isNotEmpty) {
      list = list.where(
        (f) =>
            f.name.toLowerCase().contains(q) ||
            f.manager.toLowerCase().contains(q),
      );
    }
    final out = list.toList();
    switch (sort) {
      case MarketSort.highestYield:
      case MarketSort.taxFree:
        out.sort((a, b) => _net(b, wht).compareTo(_net(a, wht)));
      case MarketSort.lowestMinimum:
        out.sort((a, b) => _min(a).compareTo(_min(b)));
    }
    return out;
  });
});

/// Best KES money-market fund for the hero. Falls back to the highest-yielding
/// fund of any kind if no MMF KES is present.
final bestMmfProvider = Provider<Fund?>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  final wht = ref.watch(remoteConfigProvider).whtPct;
  // Strictly the best retail KES money-market fund  never a bond/equity, so
  // the "best MMF" label can't lie. Null hides the hero.
  final mmf =
      funds
          .where(
            (f) =>
                f.fundType == 'mmf' &&
                f.currency == 'KES' &&
                f.retail &&
                f.currentRate != null,
          )
          .toList()
        ..sort((a, b) => _net(b, wht).compareTo(_net(a, wht)));
  return mmf.isEmpty ? null : mmf.first;
});

/// Treasury bills for the flat strip (91/182/364-day), ordered by yield.
final tbillsProvider = Provider<List<Fund>>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  final bills = funds.where((f) => f.category == 'tbill').toList()
    ..sort((a, b) => _rate(b).compareTo(_rate(a)));
  return bills;
});

// ── News (stub) ──────────────────────────────────────────────────────────
// Populated by snapshot-v2 `market_events` in C1. Until then this returns
// empty and the News section hides itself  no placeholder content.
class NewsItem {
  const NewsItem({required this.title, required this.at, this.body});
  final String title;
  final String? body;
  final DateTime at;
}

final marketNewsProvider = Provider<List<NewsItem>>((ref) {
  final events = ref.watch(marketEventsProvider);
  return events
      .map((e) => NewsItem(title: e.headline, at: e.createdAt))
      .toList();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/models/fund.dart';
import '../../data/models/stock.dart';
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

// NAV-priced fund types (equity/balanced/special) don't quote a single annual
// yield  they stand on AUM and holdings. Tab visibility must NOT gate them on
// currentRate, or their tabs never appear even once they're retail-visible.
// Keyed on fund_type (not `basis`) so this holds regardless of whether the
// snapshot publishes basis yet.
bool _isNavType(Fund f) =>
    f.fundType == 'equity' ||
    f.fundType == 'balanced' ||
    f.fundType == 'special';

/// Tabs that actually have something to show. A fund earns its tab when it's
/// retail and either quotes a rate OR is a NAV-priced type (which shows on AUM
/// alone). `all` is always present. This keeps genuinely-empty yield tabs
/// hidden while surfacing Equity/Balanced/Special once their funds go retail.
final visibleMarketTabsProvider = Provider<List<MarketTab>>((ref) {
  final funds = ref.watch(ratesProvider).valueOrNull ?? const [];
  // Stocks live in their own table, not in `funds`, so MarketTab.stock can
  // never be populated by a fund row. Its visibility is driven by the stocks
  // snapshot instead. (MarketTab.stock.matches() still keys off the legacy
  // `category == 'stock'`, which no live row carries, and that is fine: it
  // keeps stocks out of the `all` stream, which is exactly where they must
  // not appear.)
  final hasStocks = ref.watch(stocksProvider).isNotEmpty;
  bool hasData(Fund f) => f.currentRate != null || _isNavType(f);
  bool populated(MarketTab t) => switch (t) {
    MarketTab.all => true,
    MarketTab.stock => hasStocks,
    _ => funds.any((f) => f.retail && t.matches(f) && hasData(f)),
  };
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


// ─────────────────────────────────────────────────────────────────────────
// Stocks stream. Deliberately a SEPARATE stream from `streamFundsProvider`.
//
// A stock is not a Fund and must never be ranked inside the same list as one:
// a fund yield and a dividend yield are different kinds of number. So the
// Stocks tab swaps the whole list over rather than merging rows in, and stocks
// never appear under `all`. Same shape as the Money Market currency sub-filter,
// but the sub-filter here is sector.
// ─────────────────────────────────────────────────────────────────────────

enum StockSort { movers, dividend, alpha }

extension StockSortX on StockSort {
  String get label => switch (this) {
    StockSort.movers => t('stocks.sort.movers'),
    StockSort.dividend => t('stocks.sort.dividend'),
    StockSort.alpha => t('stocks.sort.alpha'),
  };
}

/// null = the All sector chip.
final stockSectorProvider = StateProvider<String?>((_) => null);

/// Dividend-first, because a price needs a licence and may not be there.
final stockSortProvider = StateProvider<StockSort>((_) => StockSort.dividend);

/// Sectors actually present, alphabetical. One or fewer means the sub-filter
/// row is not worth showing (mirrors moneyMarketCurrenciesProvider).
final stockSectorsProvider = Provider<List<String>>((ref) {
  final set = <String>{};
  for (final s in ref.watch(stocksProvider)) {
    final sec = s.sector;
    if (sec != null && sec.isNotEmpty) set.add(sec);
  }
  final list = set.toList()..sort();
  return list;
});

/// Ranking by day move needs a licensed price. With no prices published there
/// is nothing to rank, so the pill is not offered and the sort falls back.
final effectiveStockSortProvider = Provider<StockSort>((ref) {
  final sort = ref.watch(stockSortProvider);
  final live = ref.watch(stockPricesLiveProvider);
  return (!live && sort == StockSort.movers) ? StockSort.dividend : sort;
});

/// Nulls sort last in both directions: no dividend recorded is not a dividend
/// of zero, and no price is not a price of zero.
int _nullableDesc(double? a, double? b, String an, String bn) {
  if (a == null && b == null) return an.compareTo(bn);
  if (a == null) return 1;
  if (b == null) return -1;
  final r = b.compareTo(a);
  return r != 0 ? r : an.compareTo(bn);
}

final streamStocksProvider = Provider<List<Stock>>((ref) {
  final sector = ref.watch(stockSectorProvider);
  final sort = ref.watch(effectiveStockSortProvider);
  final q = ref.watch(marketSearchProvider).trim().toLowerCase();

  var list = ref.watch(stocksProvider).where(
    (s) => sector == null || s.sector == sector,
  );
  if (q.isNotEmpty) {
    // Ticker is searchable, so "SCOM" finds Safaricom.
    list = list.where(
      (s) =>
          s.name.toLowerCase().contains(q) ||
          s.ticker.toLowerCase().contains(q) ||
          (s.sector ?? '').toLowerCase().contains(q),
    );
  }

  final out = list.toList();
  switch (sort) {
    case StockSort.movers:
      out.sort((a, b) => _nullableDesc(a.changePct, b.changePct, a.name, b.name));
    case StockSort.dividend:
      out.sort((a, b) => _nullableDesc(a.dpsLatest, b.dpsLatest, a.name, b.name));
    case StockSort.alpha:
      out.sort((a, b) => a.name.compareTo(b.name));
  }
  return out;
});

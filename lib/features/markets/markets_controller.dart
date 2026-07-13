import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/models/fund.dart';
import '../../data/models/sacco.dart';
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
    // SACCOs and stocks live in their own tables, NOT in `funds`. Both key off
    // legacy categories that no live row carries, so both match nothing, and
    // that is the point: it keeps them out of the `all` stream by default. A
    // SACCO may only ever join that list DELIBERATELY, through
    // [streamAllRowsProvider] below, and never by an accident of matching.
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
  // Same story for SACCOs (0062): they are rows in `saccos`, never in `funds`,
  // so the tab is driven by the SACCO snapshot. With `saccos.enabled` off the
  // publisher emits none, the list is empty, and the tab simply is not there.
  final hasSaccos = ref.watch(saccosProvider).isNotEmpty;
  bool hasData(Fund f) => f.currentRate != null || _isNavType(f);
  bool populated(MarketTab t) => switch (t) {
    MarketTab.all => true,
    MarketTab.stock => hasStocks,
    MarketTab.sacco => hasSaccos,
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


// ─────────────────────────────────────────────────────────────────────────
// SACCO stream (0062). A separate stream, for the same reason stocks are.
//
// A SACCO is not a Fund. It carries TWO rates paid on two different pots of
// money, and the pot decides everything:
//
//   interest_on_deposits       paid on member savings, which are uncapped. The
//                              number that decides how much a member receives,
//                              and the ONLY number this app ranks SACCOs on.
//   dividend_on_share_capital  paid on share capital, which is capped. Nearly
//                              always the bigger percentage, nearly always the
//                              smaller cheque.
//
// THERE IS NO DIVIDEND SORT, and its absence is a decision, not an oversight.
// The tile's headline figure is the deposit rate. A list ordered by a number
// that is not the headline either reads as broken or, far worse, invites the
// reader to take the headline AS the sort key, which rebuilds precisely the
// confusion this whole feature exists to undo. The dividend is shown on every
// row, clearly labelled, and it does not order anything.
// ─────────────────────────────────────────────────────────────────────────

enum SaccoSort { depositRate, largest, alpha }

extension SaccoSortX on SaccoSort {
  // Literal labels, like MarketTabX.label. No i18n key needed.
  String get label => switch (this) {
    SaccoSort.depositRate => 'On deposits',
    SaccoSort.largest => 'Largest',
    SaccoSort.alpha => 'A to Z',
  };
}

final saccoSortProvider = StateProvider<SaccoSort>((_) => SaccoSort.depositRate);

/// Show only societies a user can actually join. Defaults from remote config
/// (`saccos.open_bond_only_default`, true), so it can be turned off from admin
/// without a release.
///
/// On by default because membership is a harder gate than rate. A society with
/// a brilliant rate and a closed bond is not a better option than one with a
/// duller rate you can join. It is not an option at all.
final saccoOpenOnlyProvider = StateProvider<bool>(
  (ref) => ref
      .watch(remoteConfigProvider)
      .flag('saccos.open_bond_only_default', true),
);

/// The visible SACCO stream: bond filter, then search, then sort.
final streamSaccosProvider = Provider<List<Sacco>>((ref) {
  final sort = ref.watch(saccoSortProvider);
  final openOnly = ref.watch(saccoOpenOnlyProvider);
  final q = ref.watch(marketSearchProvider).trim().toLowerCase();

  var list = ref.watch(saccosProvider).where((s) => !openOnly || s.joinable);

  if (q.isNotEmpty) {
    list = list.where(
      (s) =>
          s.displayName.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q) ||
          (s.county ?? '').toLowerCase().contains(q),
    );
  }

  final out = list.toList();
  switch (sort) {
    case SaccoSort.depositRate:
      out.sort(
        (a, b) => _saccoDesc(
          a.interestOnDeposits,
          b.interestOnDeposits,
          a.displayName,
          b.displayName,
        ),
      );
    case SaccoSort.largest:
      out.sort(
        (a, b) => _saccoDesc(
          a.totalAssetsKes,
          b.totalAssetsKes,
          a.displayName,
          b.displayName,
        ),
      );
    case SaccoSort.alpha:
      out.sort((a, b) => a.displayName.compareTo(b.displayName));
  }
  return out;
});

/// Nulls sort last in both directions. A society with no declared rate is not a
/// society paying zero: we do not know its rate, and "unknown" is not "worst".
int _saccoDesc(double? a, double? b, String an, String bn) {
  if (a == null && b == null) return an.compareTo(bn);
  if (a == null) return 1;
  if (b == null) return -1;
  final r = b.compareTo(a);
  return r != 0 ? r : an.compareTo(bn);
}

/// A rank badge is only honest on a ranked list. Under "A to Z" there is no
/// league position to show.
final saccoRankVisibleProvider = Provider<bool>(
  (ref) => ref.watch(saccoSortProvider) != SaccoSort.alpha,
);

// ─────────────────────────────────────────────────────────────────────────
// The All-tab merge (P6). The one place a SACCO is ranked against a fund.
//
// This is the riskiest thing in the SACCO build, so it is the most gated.
//
// GATE 1: `saccos.in_all_tab`. The product decision.
//
// GATE 2: a CONFIRMED withholding rate on deposit interest. This is not
// bureaucracy, it is arithmetic. The fund list sorts on NET yield, after tax.
// A SACCO declares its rate GROSS. Rank a gross number against net numbers and
// the SACCO carries roughly 1.5 points of unpaid tax into the comparison, which
// is wider than the entire spread between Kenya's best and worst money market
// fund. It would take the top row on a technicality, and the app would be lying
// with arithmetic rather than with words, which is harder to spot and worse.
//
// The public sources on the SACCO withholding rate genuinely disagree (see
// migration 0064). Until one is confirmed, `saccoNetPctProvider` returns null
// and the merge cannot happen no matter what the product flag says.
//
// GATE 3: sort must be "Highest yield". Under "Lowest minimum" a SACCO has no
// comparable figure to offer: its minimums are TWO numbers, a share capital
// floor and a monthly deposit floor, and neither is the same kind of thing as a
// fund's single minimum investment. Rather than pick one and pretend, SACCOs sit
// that sort out. Under "Tax-free" they are excluded because they are not.
//
// GATE 4: not in compare mode. Compare ranks fund yields against one another; a
// SACCO carries two rates on two pots and money you cannot withdraw.
// ─────────────────────────────────────────────────────────────────────────

/// A row in the All league table.
sealed class MarketRow {
  const MarketRow();
}

final class FundRow extends MarketRow {
  const FundRow(this.fund);
  final Fund fund;
}

final class SaccoRow extends MarketRow {
  const SaccoRow(this.sacco, {required this.netRate});
  final Sacco sacco;

  /// The net-of-tax deposit rate this row was RANKED on. Carried on the row
  /// rather than recomputed at paint time, so the number the list sorted by and
  /// the number the tile could show can never drift apart.
  final double netRate;
}

/// Withholding on SACCO deposit interest, as a percentage, or NULL when it has
/// not been confirmed.
///
/// Null is the honest default and it is load-bearing: everything downstream that
/// needs a net SACCO figure checks this and declines to produce one. There is no
/// fallback value, because a fallback here is a guess at a tax rate, and a guess
/// at a tax rate is a wrong number printed next to somebody's savings.
final saccoNetPctProvider = Provider<double?>((ref) {
  final cfg = ref.watch(remoteConfigProvider);
  if (!cfg.flag('saccos.tax_confirmed', false)) return null;
  final v = cfg.number('saccos.wht_deposits_pct', -1);
  return (v < 0 || v >= 100) ? null : v;
});

/// Net-of-tax deposit rate for a society, or null when either the rate or the
/// tax treatment is unknown.
double? saccoNetRate(Sacco s, double? whtPct) {
  final gross = s.interestOnDeposits;
  if (gross == null || whtPct == null) return null;
  return gross * (1 - whtPct / 100);
}

/// Whether SACCOs may be ranked inside the All list right now. All four gates.
final allTabMergeProvider = Provider<bool>((ref) {
  if (!ref.watch(saccosInAllTabProvider)) return false;
  if (ref.watch(saccoNetPctProvider) == null) return false;
  if (ref.watch(marketSortProvider) != MarketSort.highestYield) return false;
  return true;
});

/// The All list, funds and SACCOs interleaved, ranked on the same net-of-tax
/// basis. Falls back to funds alone whenever any gate is shut, which is the
/// normal state.
final streamAllRowsProvider = Provider<AsyncValue<List<MarketRow>>>((ref) {
  final funds = ref.watch(streamFundsProvider);
  final merge = ref.watch(allTabMergeProvider);
  final wht = ref.watch(remoteConfigProvider).whtPct;

  if (!merge) {
    return funds.whenData((l) => l.map<MarketRow>(FundRow.new).toList());
  }

  final saccoWht = ref.watch(saccoNetPctProvider);
  final q = ref.watch(marketSearchProvider).trim().toLowerCase();

  // Only societies a user can actually join, and only those with a declared
  // rate. An unjoinable society ranked above a fund the user CAN buy is not
  // information, it is an obstacle.
  var saccos = ref.watch(joinableSaccosProvider);
  if (q.isNotEmpty) {
    saccos = saccos
        .where(
          (s) =>
              s.displayName.toLowerCase().contains(q) ||
              s.name.toLowerCase().contains(q) ||
              (s.county ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  return funds.whenData((fundList) {
    final rows = <MarketRow>[
      for (final f in fundList) FundRow(f),
      for (final s in saccos)
        if (saccoNetRate(s, saccoWht) case final n?) SaccoRow(s, netRate: n),
    ];

    double key(MarketRow r) => switch (r) {
      FundRow(:final fund) => _net(fund, wht),
      SaccoRow(:final netRate) => netRate,
    };

    rows.sort((a, b) => key(b).compareTo(key(a)));
    return rows;
  });
});

/// True when a SACCO has taken the top of the All list. Drives the one note that
/// must appear when it happens: the row above every money market fund on the
/// page is the row whose money you cannot get back next week.
final saccoLeadsAllProvider = Provider<bool>((ref) {
  if (!ref.watch(allTabMergeProvider)) return false;
  final rows = ref.watch(streamAllRowsProvider).valueOrNull;
  return rows != null && rows.isNotEmpty && rows.first is SaccoRow;
});

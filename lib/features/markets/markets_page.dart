import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/models/sacco.dart';
import '../../data/models/stock.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../alerts/alerts_page.dart';
import '../company/company_page.dart';
import '../compare/compare_bar.dart';
import '../compare/compare_controller.dart';
import '../compare/compare_overlay.dart';
import '../compare/saved_comparisons_section.dart';
import '../insure/insure_overlay.dart';
import '../saccos/sacco_page.dart';
import '../stocks/stock_page.dart';
import '../stocks/stocks_page.dart';
import 'markets_controller.dart';
import 'search_overlay.dart';
import '../../core/widgets/app_loader.dart';
import 'widgets/category_tabs.dart';
import 'widgets/filter_sheet.dart';
import 'widgets/fund_tile.dart';
import 'widgets/fx_context_card.dart';
import 'widgets/insurance_spotlight.dart';
import 'widgets/locked_leader_note.dart';
import 'widgets/market_context_card.dart';
import 'widgets/money_currency_tabs.dart';
import 'widgets/news_feed.dart';
import 'widgets/yields_info_sheet.dart';
import 'widgets/sacco_sort_pills.dart';
import 'widgets/sacco_tile.dart';
import 'widgets/sort_pills.dart';
import 'widgets/stock_sector_tabs.dart';
import 'widgets/yield_curve.dart';

/// How long ago the snapshot was published, short form for the header.
String _ago(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays}d ago';
}

/// Top level, not a method, because _TopBar is a sibling widget rather than a
/// child of the page state and needs the same destination. It already took its
/// context as an argument, so promoting it changes no call site.
void _openFund(BuildContext context, Fund f) {
  // The moment a browser becomes a reader. Logged here rather than inside
  // CompanyPage because this is the single funnel every fund tile, the hero and
  // the search results all pass through.
  Analytics.viewFund(
    fundId: f.id,
    fundType: f.fundType,
    currency: f.currency,
    grossRate: f.currentRate,
  );
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyPage(f)));
}

class MarketsPage extends ConsumerWidget {
  const MarketsPage({super.key});

  void _exitCompare(WidgetRef ref) {
    ref.read(compareModeProvider.notifier).state = false;
    ref.read(compareSelectionProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(comparisonWatcherProvider); // keep leader-flip watcher alive

    final c = context.c;
    final stream = ref.watch(streamFundsProvider);
    final news = ref.watch(marketNewsProvider);
    final hasInsurers = ref
        .watch(insurersProvider)
        .any((i) => i.hasMotor || i.hasTravel || i.plans.isNotEmpty);
    // Insurance is a later launch. Even if insurer data lands early, the
    // spotlight stays hidden until an admin flips insurance.launched
    // (App Store 2.1  no teasers for unlaunched features).
    final insuranceLaunched = ref
        .watch(remoteConfigProvider)
        .flag('insurance.launched', false);

    final compareMode = ref.watch(compareModeProvider);
    final selection = ref.watch(compareSelectionProvider);

    // "Show more" state: collapsed back to the top 20 whenever the filter,
    // sort, currency sub-filter or search changes, so each view starts short.
    //
    // The collapse is derived in markets_controller now. It used to be seven
    // ref.listen calls here writing the flag back to false, and one of them
    // could fire during this very build, which is what threw markNeedsBuild
    // out of UncontrolledProviderScope. Nothing writes anything here any more.
    final showAll = ref.watch(showAllFundsProvider);
    final total = stream.value?.length ?? 0;

    // The Stocks tab swaps the whole stream over. Stocks are not Funds and are
    // never merged into the fund list, so `all` stays a pure rates league table.
    final isStock = ref.watch(marketTabProvider) == MarketTab.stock;
    final stocks = ref.watch(streamStocksProvider);

    // Same treatment for SACCOs. They are not Funds, they carry two rates paid
    // on two different pots of money, and their deposit rate is paid on money
    // the member cannot withdraw while they remain a member. So the SACCO tab
    // swaps the whole list over rather than merging rows into the fund league
    // table, and `all` stays a pure, liquid, single-rate list.
    //
    // Ranking SACCOs beside funds is a separate, deliberate decision gated on
    // `saccos.in_all_tab`, and it is not this one.
    final isSacco = ref.watch(marketTabProvider) == MarketTab.sacco;
    final saccos = ref.watch(streamSaccosProvider);
    final saccoRank = ref.watch(saccoRankVisibleProvider);

    // P6: the merged All list. `allTabMergeProvider` is shut unless the product
    // flag is on AND a withholding rate has been confirmed AND the sort is
    // Highest yield AND compare is off. When it is shut this is just the fund
    // list wearing a different type, so this branch is safe to take always.
    final isAll = ref.watch(marketTabProvider) == MarketTab.all;
    final merged = isAll && !compareMode && ref.watch(allTabMergeProvider);
    final allRows = ref.watch(streamAllRowsProvider);
    // A rank badge beside an alphabetical list would imply a league position
    // that does not exist.
    final stockRank = ref.watch(effectiveStockSortProvider) != StockSort.alpha;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const _TopBar(),
                Expanded(
                  child: RefreshIndicator(
                    color: c.accent,
                    backgroundColor: c.s1,
                    onRefresh: () => ref.read(ratesProvider.notifier).refresh(),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // ── Rates first: the featured fund, then the market
                        // shape by type. Context (inflation, yield curve) is
                        // parked at the foot of the page.
                        if (!compareMode)
                          const SliverToBoxAdapter(
                            child: SavedComparisonsSection(),
                          ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _StreamHeader(
                            // A pinned persistent header does not re-run build on
                            // a Theme (inherited) change, so mode/accent switches
                            // were leaving this header's band + label in the old
                            // colours until something else forced a rebuild. Feed
                            // it the live brightness/accent so shouldRebuild can
                            // fire on the switch. The page itself rebuilds on any
                            // theme change (it reads context.c above).
                            brightness: c.brightness,
                            accentKind: c.accentKind,
                            compareMode: compareMode,
                            isStock: isStock,
                            isSacco: isSacco,
                            // Currency chips under ANY tab that has more than
                            // one currency, not just Money Market. A special
                            // fund is sold in a KES and a USD version exactly as
                            // an MMF is, and while this was nailed to one tab
                            // the dollar version had no chip and no way to be
                            // isolated. tabCurrenciesProvider answers for the
                            // tab currently selected, so Money Market behaves
                            // exactly as before and every other tab is finally
                            // right.
                            showCcy:
                                ref.watch(tabCurrenciesProvider).length > 1,
                            showSector:
                                isStock &&
                                ref.watch(stockSectorsProvider).length > 1,
                          ),
                        ),
                        // The note that must appear when the ranking puts the
                        // least accessible money on the page at the top of it.
                        // Hides itself whenever that is not what happened.
                        if (merged)
                          const SliverToBoxAdapter(child: LockedLeaderNote()),
                        if (isSacco)
                          _saccosSliver(context, saccos, saccoRank)
                        else if (isStock)
                          _stocksSliver(context, stocks, stockRank)
                        else if (merged)
                          _mergedSliver(
                            context,
                            ref,
                            allRows,
                            showAll ? 1 << 30 : kFundsInitial,
                          )
                        else
                          stream.when(
                            loading: () => SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Center(child: const AppLoader()),
                              ),
                            ),
                            error: (e, _) => SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  t('markets.loadError', {'error': '$e'}),
                                  style: TextStyle(color: c.muted),
                                ),
                              ),
                            ),
                            data: (funds) => funds.isEmpty
                                ? SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.all(40),
                                      child: Center(
                                        child: Text(
                                          t('markets.noMatch'),
                                          style: TextStyle(color: c.muted),
                                        ),
                                      ),
                                    ),
                                  )
                                : SliverList.separated(
                                    itemCount: showAll
                                        ? funds.length
                                        : (funds.length < kFundsInitial
                                              ? funds.length
                                              : kFundsInitial),
                                    separatorBuilder: (_, _) =>
                                        const SizedBox.shrink(),
                                    itemBuilder: (context, i) {
                                      final f = funds[i];
                                      return FundTile(
                                        f,
                                        rank: i + 1,
                                        onTap: () => _openFund(context, f),
                                        selectable: compareMode,
                                        selected: selection.contains(f.id),
                                        onToggleSelect: () => ref
                                            .read(
                                              compareSelectionProvider.notifier,
                                            )
                                            .toggle(f.id),
                                        brandColor: ref.watch(
                                          brandColorProvider(f.id),
                                        ),
                                        delta: ref.watch(
                                          fundDeltaProvider(f.id),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        if (!isStock &&
                            !isSacco &&
                            !showAll &&
                            (merged ? (allRows.value?.length ?? 0) : total) >
                                kFundsInitial)
                          SliverToBoxAdapter(
                            child: _ShowMoreButton(
                              count:
                                  (merged
                                      ? (allRows.value?.length ?? 0)
                                      : total) -
                                  kFundsInitial,
                              // Records WHICH view was expanded. The moment
                              // any filter moves, the signature no longer
                              // matches and the list is short again.
                              onTap: () =>
                                  ref
                                      .read(expandedViewProvider.notifier)
                                      .state = ref.read(
                                    marketViewKeyProvider,
                                  ),
                            ),
                          ),
                        // The footnote under the list: its label shows, the
                        // text opens on tap. Under SACCOs it is the one about
                        // savings not coming back on demand.
                        SliverToBoxAdapter(
                          child: RevealNote(
                            label: t(
                              isSacco
                                  ? 'markets.sacco.aboutLabel'
                                  : isStock
                                  ? 'stocks.aboutLabel'
                                  : 'markets.aboutLabel',
                            ),
                            body: isSacco
                                ? t('markets.sacco.about')
                                : isStock
                                ? t('stocks.disclaimer')
                                : t('markets.disclaimer'),
                            actionLabel: !isSacco && !isStock
                                ? t('markets.aboutMore')
                                : null,
                            onAction: !isSacco && !isStock
                                ? () => showYieldsInfoSheet(context)
                                : null,
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                          ),
                        ),
                        // ── Market context (post-rates): the "beating
                        // inflation" read, then the currency, then the
                        // government yield curve, and finally any market news.
                        //
                        // The currency card sits inside this block rather than
                        // beside the USD sub-filter above, because inflation,
                        // FX and the yield curve are all macro context and none
                        // of them is a fund ranking. It shares the section
                        // kicker MarketContextCard already renders.
                        // Insurance sits after the rates: Markets is a rates page first.
                        if (hasInsurers && insuranceLaunched)
                          SliverToBoxAdapter(
                            child: InsuranceSpotlight(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const InsureOverlay(),
                                ),
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: MarketContextCard()),
                        const SliverToBoxAdapter(child: FxContextSection()),
                        const SliverToBoxAdapter(child: YieldCurve()),
                        SliverToBoxAdapter(child: NewsFeed(news)),
                        SliverToBoxAdapter(
                          child: SizedBox(height: compareMode ? 160 : 100),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (compareMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CompareBar(
                  count: selection.length,
                  onExit: () => _exitCompare(ref),
                  onCompare: () {
                    final ids = List<String>.of(selection);
                    _exitCompare(ref);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CompareOverlay(ids)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Topbar: icons only (title lives in the display header) ─────────────────
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final searching = ref.watch(marketSearchOpenProvider);
    final unread = ref.watch(unreadAlertsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
      child: Row(
        children: [
          if (searching)
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  autofocus: true,
                  onChanged: (v) =>
                      ref.read(marketSearchProvider.notifier).state = v,
                  style: TextStyle(color: c.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: t('markets.search'),
                    hintStyle: TextStyle(color: c.faint),
                    filled: true,
                    fillColor: c.s2,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                // Nothing on the strip names a fund, so the tap answers the
                // question it actually provokes: what is the market doing.
                // Title, freshness and sources on one line: the page opens
                // on the list, not on a heading block.
                child: Row(
                  children: [
                    Text(
                      t('nav.markets'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.up,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _ago(ref.watch(snapshotUpdatedProvider)),
                        style: TextStyle(color: c.muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchOverlay())),
            icon: Icon(Icons.search, color: c.muted),
          ),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AlertsPage())),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              backgroundColor: c.accent,
              textColor: c.onAccent,
              child: Icon(Icons.notifications_none, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pinned tabs + sort + count header ──────────────────────────────────────
class _StreamHeader extends SliverPersistentHeaderDelegate {
  _StreamHeader({
    required this.brightness,
    required this.accentKind,
    required this.compareMode,
    required this.showCcy,
    required this.isStock,
    required this.isSacco,
    required this.showSector,
  });
  // Theme identity, carried only so shouldRebuild can fire on a mode/accent
  // switch. A pinned header ignores inherited Theme changes otherwise.
  final Brightness brightness;
  final fructaAccent accentKind;
  final bool compareMode;
  final bool showCcy;
  final bool isStock;
  final bool isSacco;
  final bool showSector;

  // CategoryTabs(46) + gap(8) + SortPills(42) + gap(8) + count(22) + pad(8)
  static const _base = 46.0 + 8 + 42 + 8 + 22 + 8;
  // gap + the stock sector row (38px).
  static const _ccyRow = 8.0 + 38;
  // Funds: CategoryTabs(42) + gap(10) + FundFilterBar(40) + pad(8).
  static const _funds = 42.0 + 10 + 40 + 8;

  double get _h {
    if (!isSacco && !isStock) return _funds;
    return _base + (showSector ? _ccyRow : 0);
  }

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final c = context.c;
    return Consumer(
      builder: (context, ref, _) {
        final merged = ref.watch(allTabMergeProvider) && !compareMode;
        final count = isSacco
            ? ref.watch(streamSaccosProvider).length
            : merged
            ? (ref.watch(streamAllRowsProvider).value?.length ?? 0)
            : isStock
            ? ref.watch(streamStocksProvider).length
            : ref
                  .watch(streamFundsProvider)
                  .maybeWhen(data: (l) => l.length, orElse: () => 0);

        // Under Stocks the count reads in stocks, not funds, and Compare is
        // absent: Compare ranks yields, and a stock has no yield to rank.
        final String label;
        if (isSacco) {
          // The count says how many you can JOIN when the filter is on, not how
          // many exist. Reporting 176 while showing 14 would be a lie about the
          // list the user is looking at.
          final onlyJoinable = ref.watch(saccoOpenOnlyProvider);
          final noun = count == 1 ? 'society' : 'societies';
          label = onlyJoinable ? '$count $noun you can join' : '$count $noun';
        } else if (isStock) {
          label = count == 1
              ? t('stocks.countOne')
              : t('stocks.count', {'n': '$count'});
        } else if (compareMode) {
          label = t('compare.selectHint', {'n': '$kMaxCompare'});
        } else {
          label = t('markets.fundCount', {'n': '$count'});
        }

        if (!isSacco && !isStock) {
          return Container(
            color: c.bg,
            child: Column(
              children: [
                const CategoryTabs(),
                const SizedBox(height: 10),
                FundFilterBar(
                  label: label,
                  onCompare: compareMode
                      ? null
                      : () =>
                            ref.read(compareModeProvider.notifier).state = true,
                ),
              ],
            ),
          );
        }

        return Container(
          color: c.bg,
          child: Column(
            children: [
              const SizedBox(height: 4),
              const CategoryTabs(),
              if (showCcy) ...[
                const SizedBox(height: 8),
                const MoneyCurrencyTabs(),
              ],
              if (showSector) ...[
                const SizedBox(height: 8),
                const StockSectorTabs(),
              ],
              const SizedBox(height: 8),
              if (isSacco)
                const SaccoSortPills()
              else if (isStock)
                const StockSortPills()
              else
                // Compare is absent under SACCOs, exactly as it is under Stocks.
                // Compare ranks fund yields against one another; a SACCO carries
                // two rates on two different pots and locked money, and dropping
                // it into that matrix would produce a tidy table of numbers that
                // are not comparable.
                SortPills(
                  onCompare: compareMode
                      ? null
                      : () =>
                            ref.read(compareModeProvider.notifier).state = true,
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(color: c.faint, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  @override
  bool shouldRebuild(covariant _StreamHeader old) =>
      old.brightness != brightness ||
      old.accentKind != accentKind ||
      old.compareMode != compareMode ||
      old.showCcy != showCcy ||
      old.isStock != isStock ||
      old.isSacco != isSacco ||
      old.showSector != showSector;
}

// ── "Show more"  reveals the funds beyond the top 20 (no nested scroll) ────
class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Show $count more',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, size: 18, color: c.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Stocks tab's list. A sibling of the fund SliverList, not a merge into
/// it: StockTile shares FundTile's shell so the rows read as the same kind of
/// object, while the right-hand figure stays honest (price only under licence,
/// otherwise the declared dividend, otherwise a dash).
///
/// Returns a sliver directly rather than a widget, because `slivers:` needs
/// real slivers.
Widget _stocksSliver(BuildContext context, List<Stock> stocks, bool showRank) {
  if (stocks.isEmpty) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            t('markets.noMatch'),
            style: TextStyle(color: context.c.muted),
          ),
        ),
      ),
    );
  }
  return SliverList.separated(
    itemCount: stocks.length,
    separatorBuilder: (_, _) => const SizedBox.shrink(),
    itemBuilder: (context, i) {
      final s = stocks[i];
      return StockTile(
        s,
        rank: showRank ? i + 1 : null,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => StockPage(s))),
      );
    },
  );
}

/// The SACCO tab's list. A sibling of the fund SliverList, never a merge into
/// it: SaccoTile shares FundTile's shell so the rows read as the same kind of
/// object, while the two rates stay separately labelled and the lock chip rides
/// on every row.
Widget _saccosSliver(BuildContext context, List<Sacco> saccos, bool showRank) {
  if (saccos.isEmpty) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            t('markets.noMatch'),
            style: TextStyle(color: context.c.muted),
          ),
        ),
      ),
    );
  }
  return SliverList.separated(
    itemCount: saccos.length,
    separatorBuilder: (_, _) => const SizedBox.shrink(),
    itemBuilder: (context, i) {
      final s = saccos[i];
      return SaccoTile(
        s,
        // A rank badge beside an alphabetical list would imply a league
        // position that does not exist. It also never appears beside a society
        // with no declared rate, because those sort last and are not ranked.
        rank: showRank && s.hasDepositRate ? i + 1 : null,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => SaccoPage(s))),
      );
    },
  );
}

/// The All list when SACCOs are merged in. Funds and societies interleaved and
/// ranked on the SAME net-of-tax basis, which is the only basis on which putting
/// them in one list is defensible at all.
///
/// A SACCO row keeps everything that makes it a SACCO: the deposit rate carries
/// its ON DEPOSITS label, the dividend rides as its own labelled chip, and the
/// lock chip is there. It is ranked like a fund and it does not pretend to be
/// one.
///
/// The net figure handed to the tile is the very number the list SORTED by, not
/// a recomputation, so the ranking and the rendering cannot disagree.
Widget _mergedSliver(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<List<MarketRow>> rows,
  int limit,
) {
  return rows.when(
    loading: () => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: const AppLoader()),
      ),
    ),
    error: (e, _) => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          t('markets.loadError', {'error': '$e'}),
          style: TextStyle(color: context.c.muted),
        ),
      ),
    ),
    data: (list) {
      if (list.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(
                t('markets.noMatch'),
                style: TextStyle(color: context.c.muted),
              ),
            ),
          ),
        );
      }
      final n = list.length < limit ? list.length : limit;
      return SliverList.separated(
        itemCount: n,
        separatorBuilder: (_, _) => const SizedBox.shrink(),
        itemBuilder: (context, i) => switch (list[i]) {
          FundRow(:final fund) => FundTile(
            fund,
            rank: i + 1,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => CompanyPage(fund))),
            brandColor: ref.watch(brandColorProvider(fund.id)),
            delta: ref.watch(fundDeltaProvider(fund.id)),
          ),
          SaccoRow(:final sacco, :final netRate) => SaccoTile(
            sacco,
            rank: i + 1,
            netRate: netRate,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SaccoPage(sacco))),
          ),
        },
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../app/app_root.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../alerts/alerts_page.dart';
import '../company/company_page.dart';
import '../compare/compare_bar.dart';
import '../compare/compare_controller.dart';
import '../compare/compare_overlay.dart';
import '../compare/saved_comparisons_section.dart';
import '../insure/insure_overlay.dart';
import '../learn/learn_home_page.dart';
import '../learn/learn_progress.dart';
import 'markets_controller.dart';
import 'search_overlay.dart';
import 'widgets/best_fund_hero.dart';
import 'widgets/category_tabs.dart';
import 'widgets/fund_tile.dart';
import 'widgets/insurance_spotlight.dart';
import 'widgets/market_allocation_donut.dart';
import 'widgets/market_context_card.dart';
import 'widgets/money_currency_tabs.dart';
import 'widgets/news_feed.dart';
import 'widgets/sort_pills.dart';
import 'widgets/ticker_tape.dart';
import 'widgets/yield_curve.dart';

// Current East Africa Time (UTC+3) as "HH:MM EAT" for the LIVE header tag.
// Refreshes whenever the page rebuilds (data change / pull-to-refresh).
String _eatNow() {
  final t = DateTime.now().toUtc().add(const Duration(hours: 3));
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm EAT';
}

// "Updated …" from the snapshot's real publish time  no more hardcoded "today".
String _updatedLabel(DateTime? at) {
  const src = 'CBK, CMA & industry sources';
  if (at == null) return 'Updated recently \u00b7 $src';
  final d = DateTime.now().difference(at);
  final String rel;
  if (d.inMinutes < 2) {
    rel = 'just now';
  } else if (d.inMinutes < 60) {
    rel = '${d.inMinutes}m ago';
  } else if (d.inHours < 24) {
    rel = '${d.inHours}h ago';
  } else if (d.inDays == 1) {
    rel = 'yesterday';
  } else {
    rel = '${d.inDays}d ago';
  }
  return 'Updated $rel \u00b7 $src';
}

// Learn-persona primer: a one-time nudge atop Markets for users who chose
// "explain it as I go" at onboarding. Self-hides once they open Learn, finish a
// lesson, or dismiss it. Persona is the flag persisted during onboarding.
final _learnPrimerDismissedProvider = NotifierProvider<_PrimerDismiss, bool>(
  _PrimerDismiss.new,
);

class _PrimerDismiss extends Notifier<bool> {
  @override
  bool build() =>
      Hive.box('settings').get('learn_primer_dismissed', defaultValue: false)
          as bool;
  void dismiss() {
    Hive.box('settings').put('learn_primer_dismissed', true);
    state = true;
  }
}

class _LearnPrimer extends ConsumerWidget {
  const _LearnPrimer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onboardingPersonaProvider) != 'learn') {
      return const SizedBox.shrink();
    }
    if (ref.watch(_learnPrimerDismissedProvider))
      return const SizedBox.shrink();
    if (ref.watch(learnProvider).isEmpty) return const SizedBox.shrink();
    if (ref.watch(learnProgressProvider).completed.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LearnHomePage())),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.accent.withValues(alpha: 0.14), c.s2],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line2),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.s3,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.school_rounded, color: c.accent, size: 22),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New here? Start with a 2-minute primer',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'What a rate means?',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => ref
                      .read(_learnPrimerDismissedProvider.notifier)
                      .dismiss(),
                  icon: Icon(Icons.close_rounded, color: c.faint, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MarketsPage extends ConsumerWidget {
  const MarketsPage({super.key});

  void _openFund(BuildContext context, Fund f) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => CompanyPage(f)));

  void _exitCompare(WidgetRef ref) {
    ref.read(compareModeProvider.notifier).state = false;
    ref.read(compareSelectionProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(comparisonWatcherProvider); // keep leader-flip watcher alive

    final c = context.c;
    final all = ref.watch(ratesProvider).valueOrNull ?? const [];
    final stream = ref.watch(streamFundsProvider);
    final hero = ref.watch(bestMmfProvider);
    final news = ref.watch(marketNewsProvider);
    final hasInsurers = ref
        .watch(insurersProvider)
        .any((i) => i.hasMotor || i.plans.isNotEmpty);
    // Insurance is a later launch. Even if insurer data lands early, the
    // spotlight stays hidden until an admin flips insurance.launched
    // (App Store 2.1  no teasers for unlaunched features).
    final insuranceLaunched = ref
        .watch(remoteConfigProvider)
        .flag('insurance.launched', false);

    final compareMode = ref.watch(compareModeProvider);
    final selection = ref.watch(compareSelectionProvider);

    // "Show more" state: collapse back to the top 20 whenever the filter,
    // sort, currency sub-filter or search changes, so each view starts short.
    final showAll = ref.watch(showAllFundsProvider);
    void collapse() => ref.read(showAllFundsProvider.notifier).state = false;
    ref.listen<MarketTab>(marketTabProvider, (_, __) => collapse());
    ref.listen<MarketSort>(marketSortProvider, (_, __) => collapse());
    ref.listen<String?>(marketMoneyCcyProvider, (_, __) => collapse());
    ref.listen<String>(marketSearchProvider, (_, __) => collapse());
    final total = stream.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const _TopBar(),
                if (!ref.watch(marketSearchOpenProvider))
                  DisplayHeader(
                    title: t('nav.markets'),
                    sub: '${all.length} retail funds',
                    live: true,
                    time: _eatNow(),
                    updated: _updatedLabel(ref.watch(snapshotUpdatedProvider)),
                  ),
                TickerTape(all),
                Divider(height: 1, color: c.line),
                Expanded(
                  child: RefreshIndicator(
                    color: c.accent,
                    backgroundColor: c.s1,
                    onRefresh: () => ref.read(ratesProvider.notifier).refresh(),
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Learn-persona primer (self-hides otherwise).
                        const SliverToBoxAdapter(child: _LearnPrimer()),
                        // ── Rates first: the featured fund, then the market
                        // shape by type. Context (inflation, yield curve) is
                        // parked at the foot of the page.
                        if (hero != null)
                          SliverToBoxAdapter(
                            child: BestFundHero(
                              hero,
                              delta: ref.watch(fundDeltaProvider(hero.id)),
                              brandColor: ref.watch(
                                brandColorProvider(hero.id),
                              ),
                              onTap: () => _openFund(context, hero),
                            ),
                          ),
                        const SliverToBoxAdapter(
                          child: MarketAllocationDonut(),
                        ),
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
                        if (!compareMode)
                          const SliverToBoxAdapter(
                            child: SavedComparisonsSection(),
                          ),
                        // "All rates" section header (scrolls; tabs pin below)
                        SliverToBoxAdapter(
                          child: SectionHeader(
                            title: t('markets.allRates'),
                            trailing: t('markets.allRatesSub'),
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _StreamHeader(
                            compareMode: compareMode,
                            showCcy:
                                ref.watch(marketTabProvider) ==
                                    MarketTab.moneyMarket &&
                                ref
                                        .watch(moneyMarketCurrenciesProvider)
                                        .length >
                                    1,
                          ),
                        ),
                        stream.when(
                          loading: () => SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(40),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: c.accent,
                                ),
                              ),
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
                                      delta: ref.watch(fundDeltaProvider(f.id)),
                                    );
                                  },
                                ),
                        ),
                        if (!showAll && total > kFundsInitial)
                          SliverToBoxAdapter(
                            child: _ShowMoreButton(
                              count: total - kFundsInitial,
                              onTap: () =>
                                  ref
                                          .read(showAllFundsProvider.notifier)
                                          .state =
                                      true,
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: Disclaimer(t('markets.disclaimer')),
                        ),
                        // ── Market context (post-rates): the "beating
                        // inflation" read, then the government yield curve, and
                        // finally any market news.
                        const SliverToBoxAdapter(child: MarketContextCard()),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
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
            const Spacer(),
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
  _StreamHeader({required this.compareMode, required this.showCcy});
  final bool compareMode;
  final bool showCcy;

  // CategoryTabs(46) + gap(8) + SortPills(42) + gap(8) + count(22) + pad(8)
  static const _base = 46.0 + 8 + 42 + 8 + 22 + 8;
  static const _ccyRow = 8.0 + 38; // gap + MoneyCurrencyTabs

  double get _h => _base + (showCcy ? _ccyRow : 0);

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final c = context.c;
    return Consumer(
      builder: (context, ref, _) {
        final count = ref
            .watch(streamFundsProvider)
            .maybeWhen(data: (l) => l.length, orElse: () => 0);
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
              const SizedBox(height: 8),
              SortPills(
                onCompare: compareMode
                    ? null
                    : () => ref.read(compareModeProvider.notifier).state = true,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        compareMode
                            ? t('compare.selectHint', {'n': '$kMaxCompare'})
                            : t('markets.fundCount', {'n': '$count'}),
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
      old.compareMode != compareMode || old.showCcy != showCcy;
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

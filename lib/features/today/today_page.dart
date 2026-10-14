import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_scaffold.dart';
import '../../core/analytics.dart';
import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/rate_basis.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../core/widgets/fund_logo.dart';
import '../../core/widgets/rate_basis_toggle.dart';
import '../../data/models/fund.dart';
import '../../data/models/market_event.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../app/app_root.dart';
import '../alerts/alerts_page.dart';
import '../company/company_page.dart';
import '../learn/learn_home_page.dart';
import '../learn/learn_progress.dart';
import '../markets/market_page.dart';
import '../markets/search_overlay.dart';
import '../markets/widgets/market_allocation_donut.dart';
import '../markets/widgets/market_pulse.dart';
import '../portfolio/add_holding_page.dart';
import '../settings/following_page.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../../data/statements/statement_store.dart';
import '../wrap/wrap_viewer.dart';
import 'portfolio_bubble.dart';
import 'today_providers.dart';
import 'today_state.dart';

/// The Today tab: one hero rate, then only the modules this user's state calls
/// for (see [TodayMode]). Every figure appears once on this screen; anything
/// longer than a line lives one tap away.
class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final mode = ref.watch(todayModeProvider);
    final leaders = ref.watch(todayLeadersProvider);
    final hero = ref.watch(todayHeroProvider);
    final dismissed = ref.watch(todayDismissalsProvider);
    final events = ref.watch(todayEventsProvider);
    final eventCount = mode == TodayMode.investor ? 2 : 3;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: c.accent,
              backgroundColor: c.s1,
              onRefresh: () => ref.read(ratesProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  const _TopBar(),
                  _Greeting(mode: mode),
                  if (hero != null && leaders.length > 1)
                    _LeaderTicker(
                      leaders: [
                        for (final l in leaders)
                          if (l.category != hero.category) l,
                      ],
                    ),
                  _StatementLine(mode: mode),
                  if (leaders.length > 1)
                    _CategoryChips(leaders: leaders, selected: hero?.category),
                  if (hero != null) _HeroCard(leader: hero),
                  const _LearnPrimer(),
                  if (mode == TodayMode.newcomer &&
                      !dismissed.contains('start'))
                    const _StartCard(),
                  if (mode == TodayMode.viewer) const _RecentSection(),
                  if (mode == TodayMode.follower || mode == TodayMode.investor)
                    const _FollowingSection(),
                  if (mode == TodayMode.follower &&
                      !dismissed.contains('nudge'))
                    const _AddNudge(),
                  // The Weekly wrap replaces the weekly report card: market stories
                  // for everyone, the user's own week after them (Pro).
                  const WeeklyWrapCard(),
                  if (events.isNotEmpty)
                    _EventsSection(events: events.take(eventCount).toList()),
                  // Kenya's fund market: context, so it sits after the user's own
                  // modules and the news, never above them.
                  const MarketAllocationDonut(),
                  const _TbillRow(),
                ],
              ),
            ),
          ),
          // The book's day, docked bottom right, popped on demand. Sits above
          // the nav bar, which the scaffold draws over the body.
          if (mode == TodayMode.investor)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 16,
              child: const PortfolioBubble(),
            ),
        ],
      ),
    );
  }
}

/// Opens a fund page through the same analytics funnel Markets uses.
void _openFund(BuildContext context, Fund f) {
  Analytics.viewFund(
    fundId: f.id,
    fundType: f.fundType,
    currency: f.currency,
    grossRate: f.currentRate,
  );
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompanyPage(f)));
}

/// Signed percentage with two decimals, e.g. `+0.22%`.
String _signedPct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

/// Signed point move with two decimals, e.g. `-0.19 pts`.
String _signedPts(double v) =>
    t('today.pts', {'v': '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}'});

/// Section title in the app's display weight.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing, this.onTrailing});

  final String text;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (trailing != null)
            TextButton(
              onPressed: onTrailing,
              child: Text(
                trailing!,
                style: TextStyle(
                  color: c.accentInk,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Top bar: the header chart (market pulse), search, alerts ────────────────
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unread = ref.watch(unreadAlertsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: MarketPulse(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MarketPage()),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: t('markets.search'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SearchOverlay())),
            icon: Icon(Icons.search, color: c.muted),
          ),
          IconButton(
            tooltip: t('nav.alerts'),
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

// ── Greeting: date, title, live badge ───────────────────────────────────────
const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.mode});

  final TodayMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = DateTime.now();
    final date =
        '${_weekdays[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}';
    final updated = ref.watch(snapshotUpdatedProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: TextStyle(color: c.muted, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  t(
                    mode == TodayMode.newcomer
                        ? 'today.welcome'
                        : 'today.title',
                  ),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LiveBadge(updated: updated),
          ),
        ],
      ),
    );
  }
}

/// Pulsing LIVE dot plus how long ago the snapshot was published.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.updated});

  final DateTime? updated;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String? _ago(DateTime? at) {
    if (at == null) return null;
    final m = DateTime.now().difference(at).inMinutes;
    if (m < 1) return t('today.justNow');
    if (m < 60) return t('today.minAgo', {'n': '$m'});
    final h = m ~/ 60;
    if (h < 24) return t('today.hourAgo', {'n': '$h'});
    return t('today.dayAgo', {'n': '${h ~/ 24}'});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ago = _ago(widget.updated);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final v = _pulse.value;
            return Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: c.up,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.up.withValues(alpha: 0.45 * (1 - v)),
                    spreadRadius: 7 * v,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 7),
        Text(
          t('today.live'),
          style: TextStyle(
            color: c.up,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        if (ago != null) ...[
          const SizedBox(width: 6),
          Text(ago, style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ],
    );
  }
}

// ── Ticker: the OTHER categories' leaders, scrolling ────────────────────────
class _LeaderTicker extends ConsumerStatefulWidget {
  const _LeaderTicker({required this.leaders});

  final List<TodayLeader> leaders;

  @override
  ConsumerState<_LeaderTicker> createState() => _LeaderTickerState();
}

class _LeaderTickerState extends ConsumerState<_LeaderTicker>
    with SingleTickerProviderStateMixin {
  /// Logical px per second.
  static const _speed = 28.0;

  final _scroll = ScrollController();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _offset = 0;
  bool _held = false;

  /// True once layout shows one copy fits the screen, so nothing scrolls and
  /// the duplicate copy is dropped.
  bool _fits = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_held || !_scroll.hasClients) return;
    final p = _scroll.position;
    final copy = (p.maxScrollExtent + p.viewportDimension) / 2;
    if (copy <= p.viewportDimension) {
      if (!_fits) setState(() => _fits = true);
      return;
    }
    _offset = (_offset + dt * _speed) % copy;
    _scroll.jumpTo(_offset);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final copies = _fits || reduceMotion(context) ? 1 : 2;
    final items = [
      for (var k = 0; k < copies; k++)
        for (final l in widget.leaders)
          InkWell(
            onTap: () =>
                ref.read(todayCategoryProvider.notifier).state = l.category,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: l.category.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    t(l.category.shortKey),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${l.shown(ref.watch(showNetProvider)).toStringAsFixed(2)}%',
                    style: fructaFonts.numeric(
                      color: c.text,
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: Listener(
        onPointerDown: (_) => _held = true,
        onPointerUp: (_) => _held = false,
        onPointerCancel: (_) => _held = false,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(children: items),
        ),
      ),
    );
  }
}

// ── Statements: the latest finding, or a nudge on statement week ───────────
/// One line, no amounts (Today never shows balances). After a check it states
/// the finding; early in the month, for someone who holds funds and has not
/// checked one recently, it says statements are out. Hidden otherwise, and
/// while `statements.enabled` is off.
class _StatementLine extends ConsumerWidget {
  const _StatementLine({required this.mode});

  final TodayMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(remoteConfigProvider).statementsEnabled) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    final items =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final now = DateTime.now();
    final latest = items.isEmpty ? null : items.first;
    final fresh = latest != null && now.difference(latest.data.to).inDays <= 45;

    String? title;
    String? sub;
    Color tone = c.accentInk;
    VoidCallback? onTap;

    if (latest != null && fresh) {
      final gap = ref
          .watch(statementAnalysisProvider(latest.id))
          .value
          ?.analysis
          .gapPts;
      if (gap == null) return const SizedBox.shrink();
      final under = gap <= -0.25;
      tone = under ? c.down : c.up;
      title = t(under ? 'statement.today.under' : 'statement.today.ok', {
        'name': latest.data.managerName,
        'gap': gap.abs().toStringAsFixed(2),
      });
      sub = t('statement.today.from', {'date': dayLabel(latest.data.to)});
      onTap = () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StatementDetailPage(saved: latest)),
      );
    } else if (mode == TodayMode.investor && now.day <= 10) {
      title = t('statement.today.out');
      sub = t('statement.today.outSub');
      onTap = () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const StatementCheckPage()));
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: c.isDark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.fact_check_outlined, size: 19, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Category chips ──────────────────────────────────────────────────────────
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.leaders, required this.selected});

  final List<TodayLeader> leaders;
  final TodayCategory? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        itemCount: leaders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = leaders[i].category;
          final on = cat == selected;
          return Material(
            color: on ? c.text : c.s1,
            shape: StadiumBorder(side: BorderSide(color: on ? c.text : c.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => ref.read(todayCategoryProvider.notifier).state = cat,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: cat.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      t(cat.labelKey),
                      style: TextStyle(
                        color: on ? c.bg : c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Hero: the best rate in the selected category ────────────────────────────
class _HeroCard extends ConsumerWidget {
  const _HeroCard({required this.leader});

  final TodayLeader leader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = leader.fund;
    final cfg = ref.watch(remoteConfigProvider);
    final isNet = ref.watch(showNetProvider);
    final brand = ref.watch(brandColorProvider(f.id)) ?? leader.category.color;
    final line = c.brandOnBg(brand);
    final delta = ref.watch(fundDeltaProvider(f.id));
    final gross = f.currentRate!;
    final net = leader.net;

    final isBill = leader.category == TodayCategory.tbill;
    final isKes = f.currency == 'KES';
    final inflation = cfg.inflationFor(f.currency);
    final real = inflation == null
        ? null
        : f.realRate(inflation, whtPct: cfg.whtPct);
    final tbill = cfg.tbill91Pct;

    final caption = f.taxFree
        ? t('today.taxFreeCaption')
        : isNet
        ? t('today.netCaption', {'wht': cfg.whtPct.toStringAsFixed(0)})
        : t('today.grossCaption');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.line),
        ),
        // The manager's brand washes in from the top-left corner, as on the
        // fund page, so the hero reads as that fund's card at a glance.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.3,
            colors: [
              brand.withValues(alpha: c.isDark ? 0.16 : 0.08),
              brand.withValues(alpha: 0),
            ],
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _openFund(context, f),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FundLogo(
                        domain: f.logoDomain,
                        seed: f.manager,
                        logoUrl: ref.watch(logoUrlProvider(f.id)),
                        brandColor: brand,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f.name,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${f.manager} \u00b7 ${f.currency}',
                              style: TextStyle(color: c.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          t('today.bestRate'),
                          style: TextStyle(
                            color: c.onAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        // Stretch answers the user's own switch; Glitch answers
                        // a new print for THIS fund. Keying Glitch by fund id
                        // means a category switch starts a fresh, quiet Glitch
                        // instead of reading as a market tick.
                        child: StretchSwap(
                          value: '${leader.category.name}|$isNet',
                          child: Glitch(
                            key: ValueKey(f.id),
                            trigger: gross,
                            a: c.accent,
                            b: c.down,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: (isNet ? net : gross).toStringAsFixed(
                                      2,
                                    ),
                                    style: fructaFonts.numeric(
                                      color: c.text,
                                      size: 60,
                                      weight: FontWeight.w500,
                                      letterSpacing: -2.4,
                                      height: 1,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' %',
                                    style: TextStyle(
                                      color: c.muted,
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!f.taxFree)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: RateBasisToggle(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(caption, style: TextStyle(color: c.muted, fontSize: 12)),
                  if (delta != null && delta != 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      t('today.thisWeek', {'move': _signedPts(delta)}),
                      style: TextStyle(color: c.delta(delta), fontSize: 13),
                    ),
                  ],
                  if (f.spark.length >= 2) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 84,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SparkPainter(
                          points: f.spark,
                          line: line,
                          bench: isKes && !isBill ? tbill : null,
                          benchColor: c.faint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _LegendKey(color: line, label: t('today.legend.fund')),
                        if (isKes && !isBill) ...[
                          const SizedBox(width: 14),
                          _LegendKey(
                            color: c.faint,
                            label: t('today.legend.tbill'),
                            dashed: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        _Metric(
                          label: t('today.afterInflation'),
                          value: real == null
                              ? t('common.dash')
                              : _signedPct(real),
                          color: real == null ? c.muted : c.delta(real),
                        ),
                        _Metric(
                          label: t('today.vsTbill'),
                          value: isBill
                              ? t('today.benchmark')
                              : isKes
                              ? _signedPts(gross - tbill)
                              : t('today.noBench'),
                          color: isBill || !isKes ? c.muted : c.text,
                          divided: true,
                        ),
                        _Metric(
                          label: t(isNet ? 'today.gross' : 'today.net'),
                          value: '${(isNet ? gross : net).toStringAsFixed(2)}%',
                          color: c.text,
                          divided: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One cell of the hero's three-figure row.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    this.divided = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Container(
        padding: EdgeInsets.only(left: divided ? 12 : 0, right: 6),
        decoration: divided
            ? BoxDecoration(
                border: Border(left: BorderSide(color: c.line)),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value,
              style: fructaFonts.numeric(
                color: color,
                size: 16,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 2,
          child: CustomPaint(painter: _DashPainter(color, dashed: dashed)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: c.muted, fontSize: 11)),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, {required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height;
    if (!dashed) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 3).clamp(0, size.width), size.height / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// The hero's rate line with a soft fill, plus the dashed T-bill level when
/// the fund is a KES fund. The vertical range always includes the benchmark,
/// so the dashed line is never drawn off the canvas.
class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.points,
    required this.line,
    required this.bench,
    required this.benchColor,
  });

  final List<double> points;
  final Color line;
  final double? bench;
  final Color benchColor;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = points.reduce((a, b) => a < b ? a : b);
    var hi = points.reduce((a, b) => a > b ? a : b);
    if (bench != null) {
      if (bench! < lo) lo = bench!;
      if (bench! > hi) hi = bench!;
    }
    final pad = ((hi - lo) * 0.18).clamp(0.05, 5.0);
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final dx = size.width / (points.length - 1);

    final path = Path()..moveTo(0, y(points.first));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(dx * i, y(points[i]));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.22), line.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    if (bench != null) {
      final by = y(bench!);
      final p = Paint()
        ..color = benchColor
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, by),
          Offset((x + 4).clamp(0, size.width), by),
          p,
        );
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points != points ||
      old.line != line ||
      old.bench != bench ||
      old.benchColor != benchColor;
}

// ── Learn primer: for users who chose "explain it as I go" ─────────────────
/// Shown to a 'learn' persona until they finish a lesson or dismiss it. Moved
/// here from Markets so a new user meets it on the first screen they see.
/// Dismissal keeps the key Markets used, so anyone who closed it there stays
/// closed.
class _LearnPrimer extends ConsumerWidget {
  const _LearnPrimer();

  static const _key = 'learn_primer_dismissed';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final box = ref.watch(settingsBoxProvider);
    final hidden =
        ref.watch(onboardingPersonaProvider) != 'learn' ||
        ref.watch(todayDismissalsProvider).contains('learn') ||
        (box.get(_key, defaultValue: false) as bool) ||
        ref.watch(learnProvider).isEmpty ||
        ref.watch(learnProgressProvider).completed.isNotEmpty;
    if (hidden) return const SizedBox.shrink();

    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ThanosDismiss(
        onDismissed: () {
          box.put(_key, true);
          ref.read(todayDismissalsProvider.notifier).dismiss('learn');
        },
        builder: (context, snap) => Material(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LearnHomePage())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.s1,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.school_rounded,
                      color: c.accentInk,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('today.learn.title'),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t('today.learn.body'),
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t('today.dismiss'),
                    onPressed: snap,
                    icon: Icon(Icons.close_rounded, size: 18, color: c.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── New user: two first steps, dismissible with Thanos ──────────────────────
class _StartCard extends ConsumerWidget {
  const _StartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ThanosDismiss(
        onDismissed: () =>
            ref.read(todayDismissalsProvider.notifier).dismiss('start'),
        builder: (context, snap) => Container(
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.line),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('today.start.title'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('today.start.body'),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    _StepRow(
                      icon: Icons.star_outline_rounded,
                      title: t('today.start.follow'),
                      sub: t('today.start.followSub'),
                      onTap: () =>
                          ref.read(selectedTabProvider.notifier).state =
                              AppTab.markets,
                    ),
                    Divider(height: 1, color: c.line),
                    _StepRow(
                      icon: Icons.add_rounded,
                      title: t('today.start.add'),
                      sub: t('today.start.addSub'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AddHoldingPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  tooltip: t('today.dismiss'),
                  onPressed: snap,
                  icon: Icon(Icons.close_rounded, size: 18, color: c.faint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: c.accentInk),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.faint),
          ],
        ),
      ),
    );
  }
}

// ── Viewer: recently opened funds with a one-tap follow ─────────────────────
class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final byId = ref.watch(fundsByIdProvider);
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final funds = [
      for (final id in ref.watch(recentFundsProvider))
        if (byId[id] != null) byId[id]!,
    ].take(3).toList();
    if (funds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(t('today.recent')),
        for (final f in funds)
          _FundRow(
            fund: f,
            sub: f.netRate(wht) == null
                ? f.currency
                : t('today.netOf', {
                    'rate': '${f.netRate(wht)!.toStringAsFixed(2)}%',
                  }),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: BorderSide(color: c.line2),
                shape: const StadiumBorder(),
                foregroundColor: c.text,
              ),
              onPressed: () =>
                  ref.read(subscriptionsProvider.notifier).toggle(f.id),
              child: Text(
                t('today.follow'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Follower and investor: the watchlist with this week's moves ─────────────
class _FollowingSection extends ConsumerWidget {
  const _FollowingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final byId = ref.watch(fundsByIdProvider);
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final funds = [
      for (final id in ref.watch(subscriptionsProvider))
        if (byId[id] != null) byId[id]!,
    ]..sort((a, b) => (b.netRate(wht) ?? -1).compareTo(a.netRate(wht) ?? -1));
    if (funds.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          t('today.following'),
          trailing: funds.length > 5 ? t('today.all') : null,
          onTrailing: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const FollowingPage())),
        ),
        for (final f in funds.take(5))
          Builder(
            builder: (context) {
              final delta = ref.watch(fundDeltaProvider(f.id));
              final net = f.netRate(wht);
              return _FundRow(
                fund: f,
                sub: '${f.manager} \u00b7 ${f.currency}',
                spark: f.spark,
                sparkColor: delta == null || delta == 0
                    ? c.faint
                    : c.delta(delta),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      net == null
                          ? t('common.dash')
                          : '${net.toStringAsFixed(2)}%',
                      style: fructaFonts.numeric(
                        color: c.text,
                        size: 17,
                        weight: FontWeight.w600,
                      ),
                    ),
                    if (delta != null && delta != 0)
                      Text(
                        _signedPts(delta),
                        style: TextStyle(color: c.delta(delta), fontSize: 12),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// A fund row on a hairline: logo, name, one supporting line, a trailing slot.
class _FundRow extends ConsumerWidget {
  const _FundRow({
    required this.fund,
    required this.sub,
    required this.trailing,
    this.spark,
    this.sparkColor,
  });

  final Fund fund;
  final String sub;
  final Widget trailing;
  final List<double>? spark;
  final Color? sparkColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = spark;
    return InkWell(
      onTap: () => _openFund(context, fund),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            FundLogo(
              domain: fund.logoDomain,
              seed: fund.manager,
              logoUrl: ref.watch(logoUrlProvider(fund.id)),
              brandColor: ref.watch(brandColorProvider(fund.id)),
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fund.name,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: c.muted, fontSize: 13)),
                ],
              ),
            ),
            if (s != null && s.length >= 2) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 22,
                child: CustomPaint(
                  painter: _MiniSparkPainter(s, sparkColor ?? c.faint),
                ),
              ),
            ],
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _MiniSparkPainter extends CustomPainter {
  _MiniSparkPainter(this.points, this.color);

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = points.reduce((a, b) => a < b ? a : b);
    final hi = points.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final dx = size.width / (points.length - 1);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final y = (hi - lo) == 0
          ? size.height / 2
          : size.height - (points[i] - lo) / span * size.height;
      i == 0 ? path.moveTo(0, y) : path.lineTo(dx * i, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparkPainter old) =>
      old.points != points || old.color != color;
}

// ── Follower: one quiet nudge toward adding a holding ───────────────────────
class _AddNudge extends ConsumerWidget {
  const _AddNudge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: ThanosDismiss(
        onDismissed: () =>
            ref.read(todayDismissalsProvider.notifier).dismiss('nudge'),
        builder: (context, snap) => Material(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AddHoldingPage())),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, color: c.accentInk, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t('today.nudge'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: t('today.dismiss'),
                    onPressed: snap,
                    icon: Icon(Icons.close_rounded, size: 18, color: c.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── What moved the market ───────────────────────────────────────────────────
class _EventsSection extends ConsumerWidget {
  const _EventsSection({required this.events});

  final List<MarketEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final byId = ref.watch(fundsByIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          t('today.moved'),
          trailing: t('today.all'),
          onTrailing: () =>
              ref.read(selectedTabProvider.notifier).state = AppTab.markets,
        ),
        for (final e in events)
          Builder(
            builder: (context) {
              final (label, color) = _tag(c, e);
              final fund = e.fundId == null ? null : byId[e.fundId];
              return InkWell(
                onTap: fund == null ? null : () => _openFund(context, fund),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(
                                alpha: c.isDark ? 0.16 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: c.dataInk(color),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _when(e.createdAt),
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.headline,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// Tag text and colour per event type. Rate moves take the direction colour.
  (String, Color) _tag(fructaColors c, MarketEvent e) => switch (e.type) {
    'auction_result' => (t('today.tag.auction'), TodayCategory.tbill.color),
    'leader_change' => (t('today.tag.leader'), c.accent),
    'coupon' => (t('today.tag.coupon'), TodayCategory.mmfUsd.color),
    _ => (
      t('today.tag.rate'),
      e.delta == null || e.delta == 0 ? c.muted : c.delta(e.delta!),
    ),
  };

  String _when(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return t('today.when.today');
    if (diff == 1) return t('today.when.yesterday');
    return '${at.day} ${_months[at.month - 1].substring(0, 3)}';
  }
}

// ── T-bill reference line ───────────────────────────────────────────────────
class _TbillRow extends ConsumerWidget {
  const _TbillRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final b = cfg.benchmark('benchmark.tbill_91');
    final rate = b?.rate ?? cfg.tbill91Pct;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: TodayCategory.tbill.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b?.asOf == null
                      ? t('today.tbill')
                      : t('today.tbillAsOf', {'date': b!.asOf!}),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  t('today.tbillLine', {'rate': '${rate.toStringAsFixed(2)}%'}),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

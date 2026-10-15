import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/portfolio_math.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../today/today_state.dart';
import 'fund_watch_page.dart';
import 'goals.dart';
import 'pro_widgets.dart';
import 'switch_page.dart';

/// Pro, placed where it helps.
///
/// A subscriber never sees the word "Pro": the tools are simply part of Today,
/// Portfolio, the fund page and the holding sheet. A free user sees the same
/// places as small locked teasers with a PRO badge that open the paywall.
/// While Pro is switched off remotely there is nothing to sell, so everyone
/// gets the full tools.
final proAccessProvider = Provider<bool>(
  (ref) => !ref.watch(proEnabledProvider) || ref.watch(isProProvider),
);

/// Show locked teasers: Pro is on sale and this user has not bought it.
final proTeaserProvider = Provider<bool>(
  (ref) => ref.watch(proEnabledProvider) && !ref.watch(isProProvider),
);

// ── Switch opportunity ───────────────────────────────────────────────────────

/// The best move for one holding: the highest net rate among funds of the
/// same kind and currency, and what it is worth a year on the user's balance,
/// after tax and three days in transit.
class SwitchOpportunity {
  const SwitchOpportunity({
    required this.from,
    required this.to,
    required this.ptsNet,
    required this.gain,
    required this.currency,
  });

  final Fund from;
  final Fund to;

  /// Net rate difference, points a year.
  final double ptsNet;

  /// First-year gain in the holding's currency, after transit days.
  final double gain;
  final String currency;

  /// Worth acting on: KES 500 (or USD 5) a year or more.
  bool get worth => gain >= (currency == 'USD' ? 5 : 500);
}

double _net(Fund f, double wht) => f.taxFree || !f.whtStillDue
    ? f.currentRate!
    : f.currentRate! * (1 - wht / 100);

final switchOpportunityProvider = Provider.autoDispose
    .family<SwitchOpportunity?, String>((ref, fundId) {
      final funds = ref.watch(fundsByIdProvider);
      final from = funds[fundId];
      final h = ref
          .watch(holdingsProvider)
          .where((x) => x.fundId == fundId && !x.isSacco)
          .firstOrNull;
      if (from == null ||
          h == null ||
          from.currentRate == null ||
          !from.showsYield)
        return null;
      final wht = ref.watch(remoteConfigProvider).whtPct;
      final peers =
          funds.values
              .where(
                (x) =>
                    x.id != from.id &&
                    x.retail &&
                    x.showsYield &&
                    x.currentRate != null &&
                    x.currency == from.currency &&
                    x.fundType == from.fundType,
              )
              .toList()
            ..sort((a, b) => _net(b, wht).compareTo(_net(a, wht)));
      if (peers.isEmpty) return null;
      final to = peers.first;
      final pts = _net(to, wht) - _net(from, wht);
      if (pts <= 0) return null;
      final value = PortfolioMath.value(
        h,
        ratePercent: from.currentRate,
        taxFree: from.taxFree,
        usdKes: null,
      ).valueNative;
      final gain = value * pts / 100 - value * _net(to, wht) / 100 * 3 / 365;
      return SwitchOpportunity(
        from: from,
        to: to,
        ptsNet: pts,
        gain: gain,
        currency: h.currency,
      );
    });

/// The biggest opportunity across all holdings, for Today.
final bestSwitchProvider = Provider.autoDispose<SwitchOpportunity?>((ref) {
  SwitchOpportunity? best;
  for (final h in ref.watch(holdingsProvider)) {
    final o = ref.watch(switchOpportunityProvider(h.fundId));
    if (o == null || o.ptsNet < 0.25) continue;
    if (best == null || o.gain > best.gain) best = o;
  }
  return best;
});

/// This fund's watch card, when the user holds it.
final fundWatchForProvider = Provider.autoDispose.family<FundWatch?, String>(
  (ref, fundId) => ref
      .watch(fundWatchProvider)
      .where((w) => w.fund.id == fundId)
      .firstOrNull,
);

const _mon = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

Color _scoreTone(BuildContext context, int? score) {
  final c = context.c;
  if (score == null) return c.muted;
  return score >= 8 ? c.up : (score >= 5 ? c.accentInk : c.down);
}

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

// ── Shared row ───────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.tone,
    required this.title,
    required this.sub,
    required this.onTap,
    this.locked = false,
    this.trailing,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool locked;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                  child: Icon(icon, size: 19, color: tone),
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
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(color: c.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (locked)
                  const ProBadge()
                else
                  trailing ?? Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Today: "Your money" ──────────────────────────────────────────────────────

/// Up to four one-line cards under Today's hero, each only when it has
/// something to say. No amounts, as everywhere on Today: points, percentages
/// and on-track status only.
class YourMoneySection extends ConsumerWidget {
  const YourMoneySection({super.key, required this.mode});

  final TodayMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final access = ref.watch(proAccessProvider);
    final holdsFunds = ref.watch(holdingsProvider).any((h) => !h.isSacco);
    final cards = <Widget>[];

    if (access) {
      // Something to watch in the user's funds.
      final watches = ref
          .watch(fundWatchProvider)
          .where((w) => w.toWatch > 0)
          .toList();
      if (watches.isNotEmpty) {
        final n = watches.fold(0, (s, w) => s + w.toWatch);
        final first = watches.first;
        final sig = first.signals.firstWhere(
          (s) => s.level == WatchLevel.watch,
        );
        cards.add(
          _Card(
            icon: Icons.health_and_safety_outlined,
            tone: c.down,
            title: t(n == 1 ? 'yourMoney.watchOne' : 'yourMoney.watchMany', {
              'n': '$n',
            }),
            sub: '${first.fund.name}: ${sig.title.toLowerCase()}',
            onTap: () => _push(context, const FundWatchPage()),
          ),
        );
      }

      // A better fund, in points.
      final o = ref.watch(bestSwitchProvider);
      if (o != null) {
        cards.add(
          _Card(
            icon: Icons.swap_horiz_rounded,
            tone: c.up,
            title: t('yourMoney.switch', {
              'to': o.to.name,
              'pts': o.ptsNet.toStringAsFixed(2),
            }),
            sub: t('yourMoney.switchSub'),
            onTap: () => _push(
              context,
              SwitchPage(fromFundId: o.from.id, toFundId: o.to.id),
            ),
          ),
        );
      }

      // The nearest goal.
      final goals = ref.watch(goalsProvider);
      if (goals.isNotEmpty) {
        final g = goals.first;
        final p = ref.watch(goalProgressProvider(g));
        final on = p.projected >= g.target;
        final pct = g.target <= 0
            ? 0
            : (p.saved / g.target * 100).clamp(0, 100).round();
        cards.add(
          _Card(
            icon: Icons.flag_outlined,
            tone: on ? c.up : c.down,
            title: t(on ? 'yourMoney.goalOn' : 'yourMoney.goalBehind', {
              'name': g.name,
            }),
            sub: t('yourMoney.goalSub', {
              'pct': '$pct',
              'by': '${_mon[g.by.month - 1]} ${g.by.year}',
            }),
            onTap: () => _push(context, GoalDetailPage(goalId: g.id)),
          ),
        );
      }
    }

    // Statement week: open to everyone (the headline check is free).
    if (ref.watch(remoteConfigProvider).statementsEnabled &&
        mode == TodayMode.investor) {
      final items =
          ref.watch(statementsProvider).value ?? const <SavedStatement>[];
      final now = DateTime.now();
      final fresh =
          items.isNotEmpty && now.difference(items.first.data.to).inDays <= 40;
      if (!fresh && now.day <= 10) {
        cards.add(
          _Card(
            icon: Icons.mark_email_unread_outlined,
            tone: c.accentInk,
            title: t('statement.today.out'),
            sub: t('statement.today.outSub'),
            onTap: () => _push(context, const StatementCheckPage()),
          ),
        );
      }
    }

    // Free users with holdings: one teaser for what they are missing.
    if (!access && ref.watch(proTeaserProvider) && holdsFunds) {
      cards.add(
        _Card(
          icon: Icons.health_and_safety_outlined,
          tone: c.accentInk,
          title: t('yourMoney.teaser'),
          sub: t('yourMoney.teaserSub'),
          locked: true,
          onTap: () => ensurePro(context, ref, source: 'today_your_money'),
        ),
      );
    }

    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              t('yourMoney.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...cards,
        ],
      ),
    );
  }
}

// ── Fund page: health, switch, your statement ────────────────────────────────

/// Cards at the top of a held fund's Overview tab. Renders nothing for funds
/// the user does not hold.
class FundProCards extends ConsumerStatefulWidget {
  const FundProCards({super.key, required this.fund});

  final Fund fund;

  @override
  ConsumerState<FundProCards> createState() => _FundProCardsState();
}

class _FundProCardsState extends ConsumerState<FundProCards> {
  int _open = -1;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final f = widget.fund;
    final held = ref.watch(holdingsProvider).any((h) => h.fundId == f.id);
    if (!held) return const SizedBox.shrink();
    final access = ref.watch(proAccessProvider);

    if (!access) {
      if (!ref.watch(proTeaserProvider)) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          children: [
            _Card(
              icon: Icons.health_and_safety_outlined,
              tone: c.accentInk,
              title: t('fundPro.teaserHealth'),
              sub: t('fundPro.teaserHealthSub'),
              locked: true,
              onTap: () => ensurePro(context, ref, source: 'fund_health'),
            ),
            _Card(
              icon: Icons.swap_horiz_rounded,
              tone: c.up,
              title: t('fundPro.teaserSwitch'),
              sub: t('yourMoney.switchSub'),
              locked: true,
              onTap: () => ensurePro(context, ref, source: 'fund_switch'),
            ),
          ],
        ),
      );
    }

    final w = ref.watch(fundWatchForProvider(f.id));
    final o = ref.watch(switchOpportunityProvider(f.id));
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final st = statements.where((s) => s.fundId == f.id).firstOrNull;
    final a = st == null
        ? null
        : ref.watch(statementAnalysisProvider(st.id)).value?.analysis;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (w != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('fundPro.health'),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (w.score != null)
                        Text(
                          '${w.score}/10',
                          style: fructaFonts.numeric(
                            color: _scoreTone(context, w.score),
                            size: 30,
                            weight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          w.toWatch == 0
                              ? t('watch.allClear')
                              : t(
                                  w.toWatch == 1
                                      ? 'watch.oneToWatch'
                                      : 'watch.nToWatch',
                                  {'n': '${w.toWatch}'},
                                ),
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < w.signals.length; i++)
                    InkWell(
                      onTap: () => setState(() => _open = _open == i ? -1 : i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.line)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  switch (w.signals[i].level) {
                                    WatchLevel.ok => Icons.check_circle_rounded,
                                    WatchLevel.watch => Icons.error_rounded,
                                    WatchLevel.info =>
                                      Icons.info_outline_rounded,
                                  },
                                  size: 17,
                                  color: switch (w.signals[i].level) {
                                    WatchLevel.ok => c.up,
                                    WatchLevel.watch => c.down,
                                    WatchLevel.info => c.muted,
                                  },
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    w.signals[i].title,
                                    style: TextStyle(
                                      color: c.text,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  w.signals[i].value,
                                  style: fructaFonts.numeric(
                                    color: c.muted,
                                    size: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            if (_open == i)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 27,
                                  top: 4,
                                ),
                                child: Text(
                                  w.signals[i].detail,
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (o != null)
            _Card(
              icon: Icons.swap_horiz_rounded,
              tone: o.worth ? c.up : c.muted,
              title: o.worth
                  ? t('fundPro.switchWorth', {
                      'to': o.to.name,
                      'amount': money(o.currency, o.gain),
                    })
                  : t('fundPro.switchNot', {'to': o.to.name}),
              sub: o.worth
                  ? t('fundPro.switchWorthSub')
                  : t('fundPro.switchNotSub', {
                      'amount': money(o.currency, math.max(0, o.gain)),
                    }),
              onTap: () => _push(
                context,
                SwitchPage(fromFundId: f.id, toFundId: o.to.id),
              ),
            ),
          if (st != null && a?.gapPts != null)
            _Card(
              icon: Icons.fact_check_outlined,
              tone: a!.gapPts! <= -0.25 ? c.down : c.up,
              title: t('fundPro.statement', {
                'gap':
                    '${a.gapPts! >= 0 ? '+' : ''}${a.gapPts!.toStringAsFixed(2)}',
              }),
              sub: t('fundPro.statementSub', {
                'credited': a.recentCreditedPct!.toStringAsFixed(2),
                'published': a.recentPublishedPct!.toStringAsFixed(2),
              }),
              onTap: () => _push(context, StatementDetailPage(saved: st)),
            ),
        ],
      ),
    );
  }
}

// ── Portfolio: health dot, Goals ─────────────────────────────────────────────

/// A dot on a holding's logo: green all clear, gold something to watch, red
/// several. Nothing for free users or funds with no judged signals.
class HealthDot extends ConsumerWidget {
  const HealthDot({super.key, required this.fundId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(proAccessProvider)) return const SizedBox.shrink();
    final w = ref.watch(fundWatchForProvider(fundId));
    final score = w?.score;
    if (score == null) return const SizedBox.shrink();
    final c = context.c;
    return Semantics(
      label: t('fundPro.healthA11y', {'score': '$score'}),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: _scoreTone(context, score),
          shape: BoxShape.circle,
          border: Border.all(color: c.bg, width: 2),
        ),
      ),
    );
  }
}

/// Goals on Portfolio: a ring per goal, and a way to add one.
class GoalsSection extends ConsumerWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final access = ref.watch(proAccessProvider);
    if (!access && !ref.watch(proTeaserProvider))
      return const SizedBox.shrink();
    final goals = access ? ref.watch(goalsProvider) : const <Goal>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  t('goals.title'),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (access)
                TextButton(
                  onPressed: () => showGoalSheet(context),
                  style: TextButton.styleFrom(foregroundColor: c.accentInk),
                  child: Text(t('goals.add')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (!access)
            _Card(
              icon: Icons.flag_outlined,
              tone: c.accentInk,
              title: t('goals.teaser'),
              sub: t('goals.teaserSub'),
              locked: true,
              onTap: () => ensurePro(context, ref, source: 'portfolio_goals'),
            )
          else if (goals.isEmpty)
            _Card(
              icon: Icons.flag_outlined,
              tone: c.accentInk,
              title: t('goals.teaser'),
              sub: t('goals.teaserSub'),
              onTap: () => showGoalSheet(context),
            )
          else
            for (final g in goals) _GoalRow(goal: g),
        ],
      ),
    );
  }
}

class _GoalRow extends ConsumerWidget {
  const _GoalRow({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final p = ref.watch(goalProgressProvider(goal));
    final on = p.projected >= goal.target;
    final pct = goal.target <= 0
        ? 0.0
        : (p.saved / goal.target).clamp(0.0, 1.0);
    return _Card(
      icon: Icons.flag_outlined,
      tone: on ? c.up : c.down,
      title: goal.name,
      sub: t('goals.rowSub', {
        'pct': '${(pct * 100).round()}',
        'target': money('KES', goal.target),
        'by': '${_mon[goal.by.month - 1]} ${goal.by.year}',
      }),
      trailing: Text(
        t(on ? 'goals.onTrack' : 'goals.behind'),
        style: TextStyle(
          color: on ? c.up : c.down,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () => _push(context, GoalDetailPage(goalId: goal.id)),
    );
  }
}

// ── Holding sheet ────────────────────────────────────────────────────────────

/// Should I switch? and the fund's health, in the holding sheet.
class HoldingProActions extends ConsumerWidget {
  const HoldingProActions({super.key, required this.fundId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (!ref.watch(proAccessProvider)) {
      if (!ref.watch(proTeaserProvider)) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _Card(
          icon: Icons.health_and_safety_outlined,
          tone: c.accentInk,
          title: t('fundPro.teaserHealth'),
          sub: t('fundPro.teaserHealthSub'),
          locked: true,
          onTap: () => ensurePro(context, ref, source: 'holding_sheet'),
        ),
      );
    }
    final o = ref.watch(switchOpportunityProvider(fundId));
    final w = ref.watch(fundWatchForProvider(fundId));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          if (o != null)
            _Card(
              icon: Icons.swap_horiz_rounded,
              tone: o.worth ? c.up : c.muted,
              title: t('switch.title'),
              sub: o.worth
                  ? t('fundPro.sheetWorth', {
                      'to': o.to.name,
                      'amount': money(o.currency, o.gain),
                    })
                  : t('fundPro.sheetNot', {
                      'amount': money(o.currency, math.max(0, o.gain)),
                    }),
              onTap: () => _push(
                context,
                SwitchPage(fromFundId: fundId, toFundId: o.to.id),
              ),
            ),
          if (w != null && w.score != null)
            _Card(
              icon: Icons.health_and_safety_outlined,
              tone: _scoreTone(context, w.score),
              title: t('fundPro.sheetHealth', {'score': '${w.score}'}),
              sub: w.toWatch == 0
                  ? t('watch.allClear')
                  : t(w.toWatch == 1 ? 'watch.oneToWatch' : 'watch.nToWatch', {
                      'n': '${w.toWatch}',
                    }),
              onTap: () => _push(context, const FundWatchPage()),
            ),
        ],
      ),
    );
  }
}

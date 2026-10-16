import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../pro/fund_watch_page.dart';
import '../pro/goals.dart';
import '../pro/pro_inline.dart';
import '../pro/pro_widgets.dart';
import '../reports/report_notify.dart';
import '../reports/reports_page.dart';
import '../statements/statement_controller.dart';
import '../statements/statement_pages.dart';
import '../wrap/wrap_engine.dart';

/// One tool in the mosaic: what it is, its live figure, and where it goes.
class _Tool {
  const _Tool({
    required this.key,
    required this.icon,
    required this.name,
    required this.figure,
    required this.tone,
    required this.onTap,
    this.locked = false,
    this.attention = false,
  });

  final String key;
  final IconData icon;
  final String name;
  final String figure;
  final Color tone;
  final VoidCallback onTap;

  /// Pro, for a free user: a PRO tag, and the paywall on tap.
  final bool locked;

  /// Needs the user now, while another tool leads: an accent edge and dot.
  final bool attention;

  _Tool flagged() => _Tool(
    key: key,
    icon: icon,
    name: name,
    figure: figure,
    tone: tone,
    onTap: onTap,
    locked: locked,
    attention: true,
  );
}

const _usageKey = 'tools_usage';

/// The most opened tool, once tools have been opened [minTaps] times in all.
String? _favourite(Map<String, int> usage, {required int minTaps}) {
  final total = usage.values.fold(0, (a, b) => a + b);
  if (total < minTaps) return null;
  String? best;
  for (final e in usage.entries) {
    if (best == null || e.value > usage[best]!) best = e.key;
  }
  return best;
}

/// What leads the mosaic: the one thing that needs the user most right now.
class _Featured {
  const _Featured({
    required this.key,
    required this.icon,
    required this.tag,
    required this.title,
    required this.big,
    required this.bigTone,
    required this.unit,
    required this.action,
    required this.onTap,
  });

  final String key;
  final IconData icon;
  final String tag;
  final String title;
  final String big;
  final Color bigTone;
  final String unit;
  final String action;
  final VoidCallback onTap;
}

/// Portfolio's tools as a mosaic: the most pressing one large on the left,
/// two more as tiles beside it, the rest as wide rows under. Every tile
/// carries a live figure, so a glance says which is worth a tap.
///
/// What leads: the tool the user opens most, counted on the phone. Before
/// that is known, whatever needs them most. A tool that needs them while
/// another leads gets an accent edge and a dot.
class ToolsMosaic extends ConsumerWidget {
  const ToolsMosaic({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final access = ref.watch(proAccessProvider);
    final teaser = ref.watch(proTeaserProvider);
    final cfg = ref.watch(remoteConfigProvider);
    final hide = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );
    final now = DateTime.now();

    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    // How often each tool is opened, kept on the phone, so the one the user
    // reaches for most can lead.
    final box = Hive.box('settings');
    final usage = Map<String, int>.from(
      (box.get(_usageKey) as Map?)?.map(
            (k, v) => MapEntry('$k', (v as num).toInt()),
          ) ??
          const <String, int>{},
    );
    void use(String key, VoidCallback then) {
      usage[key] = (usage[key] ?? 0) + 1;
      box.put(_usageKey, usage);
      then();
    }

    Future<void> pro(String source, VoidCallback then) async {
      if (!access && !await ensurePro(context, ref, source: source)) return;
      if (!context.mounted) return;
      then();
    }

    // ── Statements ─────────────────────────────────────────────────────────
    final statementsOn = cfg.statementsEnabled;
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final latest = statements.isEmpty ? null : statements.first;
    final gap = latest == null
        ? null
        : ref
              .watch(statementAnalysisProvider(latest.id))
              .value
              ?.analysis
              .gapPts;
    String? dueManager;
    for (final key in {for (final s in statements) s.data.managerKey}) {
      final m = cfg.statementManager(key);
      final checkedThisMonth = statements.any(
        (s) =>
            s.data.managerKey == key &&
            s.checkedAt.year == now.year &&
            s.checkedAt.month == now.month,
      );
      if (m?.releaseDay == now.day && !checkedThisMonth) dueManager = m!.name;
    }
    final gapText = gap == null
        ? t('tools.stmt.never')
        : t('tools.stmt.last', {
            'gap': '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
          });
    final gapTone = gap == null ? c.muted : (gap <= -0.25 ? c.down : c.up);

    // ── Reports, Fund watch, Goals ────────────────────────────────────────
    final report = ref.watch(newReportProvider);
    final watch = access ? ref.watch(fundWatchProvider) : const <FundWatch>[];
    final things = watch.fold(0, (n, w) => n + w.toWatch);
    final goals = access ? ref.watch(goalsProvider) : const <Goal>[];
    final nearest = goals.isEmpty
        ? null
        : ([...goals]..sort((a, b) => a.by.compareTo(b.by))).first;
    final nearestPct = nearest == null
        ? 0
        : () {
            final p = ref.watch(goalProgressProvider(nearest));
            return nearest.target <= 0
                ? 0
                : (p.saved / nearest.target * 100).clamp(0, 100).round();
          }();
    String kes(double v) =>
        hide ? 'KES \u2022\u2022\u2022\u2022' : money('KES', v);

    // ── What each tool looks like when it leads ────────────────────────────
    _Featured? leadFor(String key) {
      switch (key) {
        case 'stmt':
          if (!statementsOn) return null;
          if (dueManager != null) {
            return _Featured(
              key: 'stmt',
              icon: Icons.fact_check_outlined,
              tag: t('tools.due.tag'),
              title: t('tools.due.title', {'manager': dueManager}),
              big: gap == null
                  ? t('tools.due.big')
                  : '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
              bigTone: gapTone,
              unit: gap == null ? t('tools.due.unitNew') : t('tools.due.unit'),
              action: t('tools.due.action'),
              onTap: () => use('stmt', () => push(const StatementCheckPage())),
            );
          }
          return _Featured(
            key: 'stmt',
            icon: Icons.fact_check_outlined,
            tag: gap == null ? t('tools.start.tag') : t('tools.stmt.tag'),
            title: t('tools.start.title'),
            big: gap == null
                ? ''
                : '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}',
            bigTone: gapTone,
            unit: gap == null ? t('tools.start.unit') : t('tools.due.unit'),
            action: t('tools.start.action'),
            onTap: () => use('stmt', () => push(const StatementCheckPage())),
          );
        case 'reports':
          if (report != null) {
            final month = monthName(report.from).split(' ').first;
            return _Featured(
              key: 'reports',
              icon: Icons.description_outlined,
              tag: t('tools.report.tag'),
              title: t('tools.report.title', {'month': month}),
              big: '+${kes(report.earnedKes)}',
              bigTone: c.up,
              unit: t('tools.report.unit', {'month': month}),
              action: t('tools.report.action'),
              onTap: () => use('reports', () => push(const ReportsPage())),
            );
          }
          return _Featured(
            key: 'reports',
            icon: Icons.description_outlined,
            tag: t('tools.reports.tag'),
            title: t('tools.reports.name'),
            big: '',
            bigTone: c.accentInk,
            unit: t('tools.reports.sub'),
            action: t('tools.report.action'),
            onTap: () => use('reports', () => push(const ReportsPage())),
          );
        case 'watch':
          if (!access) return null;
          return _Featured(
            key: 'watch',
            icon: Icons.visibility_outlined,
            tag: t('tools.watch.tag'),
            title: t('tools.watch.title'),
            big: '$things',
            bigTone: things == 0 ? c.up : c.down,
            unit: things == 0
                ? t('tools.watch.clear')
                : t(things == 1 ? 'tools.watch.unitOne' : 'tools.watch.unit'),
            action: t('tools.watch.action'),
            onTap: () => use('watch', () => push(const FundWatchPage())),
          );
        case 'goals':
          if (!access) return null;
          if (nearest == null) {
            return _Featured(
              key: 'goals',
              icon: Icons.flag_outlined,
              tag: t('tools.goal.tag'),
              title: t('tools.goal.none'),
              big: '',
              bigTone: c.accentInk,
              unit: t('tools.goal.noneSub'),
              action: t('tools.goal.add'),
              onTap: () => use('goals', () => showGoalSheet(context)),
            );
          }
          return _Featured(
            key: 'goals',
            icon: Icons.flag_outlined,
            tag: t('tools.goal.tag'),
            title: nearest.name,
            big: '$nearestPct%',
            bigTone: c.accentInk,
            unit: t('tools.goal.unit', {'target': kes(nearest.target)}),
            action: t('tools.goal.action'),
            onTap: () =>
                use('goals', () => push(GoalDetailPage(goalId: nearest.id))),
          );
      }
      return null;
    }

    // ── Pick what leads ────────────────────────────────────────────────────
    // The tool the user opens most leads, once they have opened tools a few
    // times. Until then, whatever needs them most: a statement due today, a
    // new monthly report, a fund to watch, their nearest goal, else the
    // statement check.
    final urgent = <String>{
      if (statementsOn && dueManager != null) 'stmt',
      if (report != null) 'reports',
      if (access && things > 0) 'watch',
    };
    final favourite = _favourite(usage, minTaps: 3);
    _Featured? lead = favourite == null ? null : leadFor(favourite);
    for (final k in [
      if (statementsOn && dueManager != null) 'stmt',
      if (report != null) 'reports',
      if (access && things > 0) 'watch',
      if (nearest != null) 'goals',
      'stmt',
      'reports',
    ]) {
      lead ??= leadFor(k);
    }
    final featured = lead!;

    // ── The rest, as tiles ─────────────────────────────────────────────────
    final tools =
        <_Tool>[
              if (statementsOn)
                _Tool(
                  key: 'stmt',
                  icon: Icons.fact_check_outlined,
                  name: t('tools.stmt.name'),
                  figure: gapText,
                  tone: gapTone,
                  onTap: () =>
                      use('stmt', () => push(const StatementCheckPage())),
                ),
              _Tool(
                key: 'reports',
                icon: Icons.description_outlined,
                name: t('tools.reports.name'),
                figure: report != null
                    ? t('tools.reports.ready', {
                        'month': monthName(report.from).split(' ').first,
                      })
                    : t('tools.reports.sub'),
                tone: report != null ? c.accentInk : c.muted,
                onTap: () => use('reports', () => push(const ReportsPage())),
              ),
              if (access || teaser)
                _Tool(
                  key: 'watch',
                  icon: Icons.visibility_outlined,
                  name: t('tools.watch.name'),
                  figure: !access
                      ? t('tools.watch.teaser')
                      : things == 0
                      ? t('tools.watch.clear')
                      : t(things == 1 ? 'tools.watch.one' : 'tools.watch.n', {
                          'n': '$things',
                        }),
                  tone: !access ? c.muted : (things == 0 ? c.up : c.down),
                  locked: !access,
                  onTap: () => pro(
                    'portfolio_watch',
                    () => use('watch', () => push(const FundWatchPage())),
                  ),
                ),
              if (access || teaser)
                _Tool(
                  key: 'goals',
                  icon: Icons.flag_outlined,
                  name: t('tools.goal.name'),
                  figure: nearest == null
                      ? t('tools.goal.none')
                      : t('tools.goal.row', {
                          'name': nearest.name,
                          'pct': '$nearestPct',
                        }),
                  tone: nearest == null ? c.muted : c.accentInk,
                  locked: !access,
                  onTap: () => pro(
                    'portfolio_goals',
                    () => use('goals', () {
                      if (nearest == null) {
                        showGoalSheet(context);
                      } else {
                        push(GoalDetailPage(goalId: nearest.id));
                      }
                    }),
                  ),
                ),
            ]
            .where((x) => x.key != featured.key)
            .map((x) => urgent.contains(x.key) ? x.flagged() : x)
            .toList();

    final side = tools.take(2).toList();
    final wide = tools.skip(2).toList();
    final calm = reduceMotion(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              t('tools.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            height: 266,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 115,
                  child: _Pop(
                    index: 0,
                    calm: calm,
                    child: _FeaturedTile(f: featured),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Expanded(
                          child: i < side.length
                              ? _Pop(
                                  index: i + 1,
                                  calm: calm,
                                  child: _ToolTile(tool: side[i]),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < wide.length; i++) ...[
            const SizedBox(height: 10),
            _Pop(
              index: i + 3,
              calm: calm,
              child: _ToolTile(tool: wide[i], wide: true),
            ),
          ],
          // The weekly report, for free users, as one row: what it is and when.
          if (teaser) ...[
            const SizedBox(height: 10),
            _Pop(
              index: wide.length + 3,
              calm: calm,
              child: _ToolTile(
                wide: true,
                tool: _Tool(
                  key: 'week',
                  icon: Icons.insights_rounded,
                  name: t('tools.week.name'),
                  figure: t('tools.week.sub'),
                  tone: c.muted,
                  locked: true,
                  onTap: () =>
                      ensurePro(context, ref, source: 'portfolio_upsell'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiles arrive one after another.
class _Pop extends StatelessWidget {
  const _Pop({required this.index, required this.calm, required this.child});

  final int index;
  final bool calm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (calm) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon(this.icon, {this.size = 38});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: c.accentInk),
    );
  }
}

class _FeaturedTile extends StatelessWidget {
  const _FeaturedTile({required this.f});

  final _Featured f;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.s1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.accent, width: 1.5),
      ),
      child: InkWell(
        onTap: f.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-1, -1),
              radius: 1.3,
              colors: [c.accentSoft, c.accentSoft.withValues(alpha: 0)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Icon(f.icon, size: 40),
                const SizedBox(height: 12),
                Text(
                  f.tag,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  f.title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const Spacer(),
                if (f.big.isNotEmpty)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      f.big,
                      style: fructaFonts.numeric(
                        color: f.bigTone,
                        size: 30,
                        weight: FontWeight.w600,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                Text(
                  f.unit,
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.3),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    f.action,
                    style: TextStyle(
                      color: c.onAccent,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool, this.wide = false});

  final _Tool tool;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tool.name,
          style: TextStyle(
            color: c.text,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(tool.figure, style: TextStyle(color: tool.tone, fontSize: 12.5)),
      ],
    );
    return Material(
      color: c.s1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: tool.attention ? c.accent : c.line,
          width: tool.attention ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tool.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: wide
              ? Row(
                  children: [
                    _Icon(tool.icon, size: 36),
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    if (tool.locked) const ProBadge(),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: c.faint),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Icon(tool.icon, size: 36),
                        const Spacer(),
                        if (tool.locked) const ProBadge(),
                        if (tool.attention)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    text,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Today's way into the statement check, under the weekly wrap card.
///
/// For anyone who holds a fund and has not checked a statement this month.
/// On the day a manager's statement usually arrives it says so, with last
/// time's result and a Check button; otherwise it asks the one question the
/// check answers.
class StatementTodayCard extends ConsumerWidget {
  const StatementTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    if (!cfg.statementsEnabled) return const SizedBox.shrink();
    final holds = ref.watch(holdingsProvider).any((h) => !h.isSacco);
    if (!holds) return const SizedBox.shrink();
    final now = DateTime.now();
    final statements =
        ref.watch(statementsProvider).value ?? const <SavedStatement>[];
    final checked = statements.any(
      (s) => s.checkedAt.year == now.year && s.checkedAt.month == now.month,
    );
    if (checked) return const SizedBox.shrink();

    String? due;
    SavedStatement? last;
    for (final s in statements) {
      final m = cfg.statementManager(s.data.managerKey);
      if (m?.releaseDay == now.day) {
        due = m!.name;
        last = s;
        break;
      }
    }
    final gap = last == null
        ? null
        : ref.watch(statementAnalysisProvider(last.id)).value?.analysis.gapPts;

    void open() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StatementCheckPage()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: c.s1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: due != null ? c.accent : c.line),
        ),
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                const _Icon(Icons.fact_check_outlined, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        due != null
                            ? t('tools.today.dueTitle', {'manager': due})
                            : t('tools.today.title'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (due != null && gap != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: t('tools.today.lastTime')),
                              TextSpan(
                                text:
                                    '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)} pts',
                                style: fructaFonts.numeric(
                                  color: gap <= -0.25 ? c.down : c.up,
                                  size: 12.5,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        )
                      else
                        Text(
                          t('tools.today.sub'),
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (due != null)
                  Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t('tools.today.check'),
                      style: TextStyle(
                        color: c.onAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

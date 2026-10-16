import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../core/widgets/reveal_note.dart';
import '../../data/models/fund.dart';
import '../../data/models/fund_composition.dart';
import '../../data/pro/pro_tuning.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../company/company_page.dart';
import '../../core/motion/motion.dart';
import '../statements/statement_pages.dart';
import 'switch_page.dart';
import '../statements/statement_controller.dart';

enum WatchLevel { ok, watch, info }

/// What a signal offers to do about itself.
enum WatchAction { switchFund, openStatement, checkStatement }

/// One thing Fructa checked about a fund the user holds.
class WatchSignal {
  const WatchSignal(
    this.level,
    this.title,
    this.detail,
    this.value, {
    this.action,
  });

  final WatchLevel level;
  final String title;
  final String detail;
  final String value;
  final WatchAction? action;
}

/// A held fund and what its signals say.
class FundWatch {
  const FundWatch(this.fund, this.signals, {this.statement});

  final Fund fund;
  final List<WatchSignal> signals;

  /// The statement the statement checks came from, if one was checked.
  final SavedStatement? statement;

  /// Out of 10, from the signals that could be judged (info ones don't count).
  int? get score {
    final judged = signals.where((s) => s.level != WatchLevel.info).toList();
    if (judged.isEmpty) return null;
    final ok = judged.where((s) => s.level == WatchLevel.ok).length;
    return (ok / judged.length * 10).round();
  }

  int get toWatch => signals.where((s) => s.level == WatchLevel.watch).length;
}

/// Signals for every fund the user holds, from three sources: their own
/// statements (paid as published, tax, every month credited), Fructa's rate
/// data (trend against peers, rank) and CMA filings (what the fund holds).
final fundWatchProvider = Provider.autoDispose<List<FundWatch>>((ref) {
  final funds = ref.watch(fundsByIdProvider);
  final statements =
      ref.watch(statementsProvider).value ?? const <SavedStatement>[];
  final underpaid = ref.watch(proTuningProvider).underpaidPts;
  final out = <FundWatch>[];

  for (final h in ref.watch(holdingsProvider)) {
    if (h.isSacco) continue;
    final f = funds[h.fundId];
    if (f == null) continue;
    final s = <WatchSignal>[];

    // ── From the user's statement ──────────────────────────────────────────
    final st = statements.where((x) => x.fundId == f.id).firstOrNull;
    final a = st == null
        ? null
        : ref.watch(statementAnalysisProvider(st.id)).value?.analysis;
    if (a != null) {
      final gap = a.gapPts;
      if (gap != null) {
        s.add(
          WatchSignal(
            gap <= -underpaid ? WatchLevel.watch : WatchLevel.ok,
            t(gap <= -underpaid ? 'watch.underpays' : 'watch.paysAsPublished'),
            t('watch.gapDetail', {
              'credited': a.recentCreditedPct!.toStringAsFixed(2),
              'published': a.recentPublishedPct!.toStringAsFixed(2),
            }),
            '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)} pts',
            action: gap <= -underpaid ? WatchAction.switchFund : null,
          ),
        );
      }
      final taxOk = a.findings.any((x) => x.key == 'statement.find.taxOk');
      final taxOff = a.findings.any(
        (x) =>
            x.key == 'statement.find.taxOff' ||
            x.key == 'statement.find.taxOnTaxFree',
      );
      if (taxOk || taxOff) {
        s.add(
          WatchSignal(
            taxOk ? WatchLevel.ok : WatchLevel.watch,
            t(taxOk ? 'watch.taxOk' : 'watch.taxOff'),
            t('watch.taxDetail'),
            taxOk ? '\u2713' : '!',
          ),
        );
      }
      final every = a.findings
          .where((x) => x.key == 'statement.find.everyMonth')
          .firstOrNull;
      final missing = a.findings
          .where((x) => x.key == 'statement.find.missingMonths')
          .firstOrNull;
      if (every != null || missing != null) {
        s.add(
          WatchSignal(
            every != null ? WatchLevel.ok : WatchLevel.watch,
            t(every != null ? 'watch.everyMonth' : 'watch.missing'),
            every != null
                ? t('watch.everyMonthDetail', {'n': every.vars['n'] ?? ''})
                : t('watch.missingDetail', {
                    'months': missing!.vars['months'] ?? '',
                  }),
            every != null ? '${every.vars['n']}/${every.vars['n']}' : '!',
            action: every == null ? WatchAction.openStatement : null,
          ),
        );
      }
    } else {
      s.add(
        WatchSignal(
          WatchLevel.info,
          t('watch.noStatement'),
          t('watch.noStatementDetail'),
          '',
          action: WatchAction.checkStatement,
        ),
      );
    }

    // ── From Fructa's rate data: trend against peers, and rank ─────────────
    final peers = funds.values
        .where(
          (x) =>
              x.retail &&
              x.showsYield &&
              x.currentRate != null &&
              x.currency == f.currency &&
              x.fundType == f.fundType,
        )
        .toList();
    if (f.showsYield && f.currentRate != null && f.spark.length >= 2) {
      final move = f.spark.last - f.spark.first;
      final moves = [
        for (final p in peers)
          if (p.spark.length >= 2) p.spark.last - p.spark.first,
      ]..sort();
      final median = moves.isEmpty ? 0.0 : moves[moves.length ~/ 2];
      final behind = move - median < -0.3;
      s.add(
        WatchSignal(
          behind ? WatchLevel.watch : WatchLevel.ok,
          t(behind ? 'watch.trendBehind' : 'watch.trendWith'),
          t('watch.trendDetail', {
            'move': '${move >= 0 ? '+' : ''}${move.toStringAsFixed(2)}',
            'median': '${median >= 0 ? '+' : ''}${median.toStringAsFixed(2)}',
          }),
          '${move >= 0 ? '+' : ''}${move.toStringAsFixed(2)}',
        ),
      );
      final ranked = [...peers]
        ..sort((x, y) => y.currentRate!.compareTo(x.currentRate!));
      final rank = ranked.indexWhere((x) => x.id == f.id) + 1;
      if (rank > 0) {
        final third = (ranked.length / 3).ceil();
        s.add(
          WatchSignal(
            rank > ranked.length - third ? WatchLevel.watch : WatchLevel.ok,
            t('watch.rank'),
            t('watch.rankDetail', {'n': '${ranked.length}'}),
            '#$rank',
          ),
        );
      }
    }

    // ── From CMA filings: what the fund holds ──────────────────────────────
    final comp = ref.watch(compositionProvider(f.id));
    if (comp != null && !comp.isEmpty) {
      final risky =
          comp.pct(AssetClass.unlisted) +
          comp.pct(AssetClass.otherCis) +
          comp.pct(AssetClass.offshore) +
          comp.pct(AssetClass.alternative);
      final top = comp.sorted.first;
      s.add(
        WatchSignal(
          f.fundType == 'mmf' && risky > 20
              ? WatchLevel.watch
              : WatchLevel.info,
          t('watch.holds'),
          t('watch.holdsDetail', {
            'cls': top.key.label,
            'asOf': comp.asOf ?? '',
          }),
          '${comp.pct(top.key).toStringAsFixed(0)}%',
        ),
      );
    }

    out.add(FundWatch(f, s, statement: st));
  }
  out.sort((x, y) => y.toWatch.compareTo(x.toWatch));
  return out;
});

/// Fund watch: a health check on every fund the user holds.
///
/// The book first: an average score and how many funds are healthy. Then one
/// card per fund, problems first. A card with something to watch opens by
/// itself; an all-clear card stays folded, its strip of check results saying
/// enough. Each check opens on tap for its exact figures and, where it helps,
/// the next step.
class FundWatchPage extends ConsumerStatefulWidget {
  const FundWatchPage({super.key});

  @override
  ConsumerState<FundWatchPage> createState() => _FundWatchPageState();
}

enum _Filter { all, watch, clear }

class _FundWatchPageState extends ConsumerState<FundWatchPage> {
  _Filter _filter = _Filter.all;
  bool _how = false;

  /// Cards the user opened or closed by hand, overriding the default.
  final _opened = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final list = ref.watch(fundWatchProvider);
    final scores = [for (final w in list) ?w.score];
    final book = scores.isEmpty
        ? null
        : scores.reduce((a, b) => a + b) / scores.length;
    final healthy = list.where((w) => w.toWatch == 0).length;
    final flagged = list.where((w) => w.toWatch > 0).toList();
    final things = flagged.fold(0, (n, w) => n + w.toWatch);
    final shown = [
      for (final w in list)
        if (_filter == _Filter.all ||
            (_filter == _Filter.watch && w.toWatch > 0) ||
            (_filter == _Filter.clear && w.toWatch == 0))
          w,
    ];

    Widget chip(_Filter f, String label) {
      final on = _filter == f;
      return Material(
        color: on ? c.text : c.s1,
        shape: StadiumBorder(side: BorderSide(color: on ? c.text : c.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => setState(() => _filter = f),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: on ? c.bg : c.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('watch.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  t('watch.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 15, height: 1.45),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                // ── The book at a glance ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.s1,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      if (book != null) ...[
                        _ScoreRing(score: book),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('watch.healthy', {
                                'ok': '$healthy',
                                'n': '${list.length}',
                              }),
                              style: fructaFonts.numeric(
                                color: c.text,
                                size: 22,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              things == 0
                                  ? t('watch.allClear')
                                  : flagged.length == 1
                                  ? t('watch.thingsIn', {
                                      'things': t(
                                        things == 1
                                            ? 'watch.oneToWatch'
                                            : 'watch.nToWatch',
                                        {'n': '$things'},
                                      ),
                                      'fund': flagged.first.fund.name,
                                    })
                                  : t('watch.nToWatch', {'n': '$things'}),
                              style: TextStyle(color: c.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                RevealNote(
                  label: t('watch.how'),
                  body: t('watch.howBody'),
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    chip(
                      _Filter.all,
                      t('watch.filter.all', {'n': '${list.length}'}),
                    ),
                    chip(
                      _Filter.watch,
                      t('watch.filter.watch', {'n': '${flagged.length}'}),
                    ),
                    chip(
                      _Filter.clear,
                      t('watch.filter.clear', {'n': '$healthy'}),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (final w in shown)
                  _WatchCard(
                    key: ValueKey(w.fund.id),
                    watch: w,
                    open: _opened[w.fund.id] ?? w.toWatch > 0,
                    onToggle: () => setState(
                      () => _opened[w.fund.id] =
                          !(_opened[w.fund.id] ?? w.toWatch > 0),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The book's average score as a ring that fills on entry.
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tone = score >= 8 ? c.up : (score >= 5 ? c.accentInk : c.down);
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: reduceMotion(context) ? score / 10 : 0.0,
        end: score / 10,
      ),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox(
        width: 76,
        height: 76,
        child: CustomPaint(
          painter: _RingPainter(v, tone, c.s3),
          child: Center(
            child: Text(
              score.toStringAsFixed(1),
              style: fructaFonts.numeric(
                color: c.text,
                size: 20,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction, this.color, this.track);

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(3.5, 3.5, size.width - 7, size.height - 7);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 6.2832, false, p..color = track);
    canvas.drawArc(r, -1.5708, 6.2832 * fraction, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

class _WatchCard extends ConsumerStatefulWidget {
  const _WatchCard({
    super.key,
    required this.watch,
    required this.open,
    required this.onToggle,
  });

  final FundWatch watch;
  final bool open;
  final VoidCallback onToggle;

  @override
  ConsumerState<_WatchCard> createState() => _WatchCardState();
}

class _WatchCardState extends ConsumerState<_WatchCard> {
  /// Checks whose detail is open.
  final _detail = <int>{};

  static int _rank(WatchLevel l) => switch (l) {
    WatchLevel.watch => 0,
    WatchLevel.ok => 1,
    WatchLevel.info => 2,
  };

  void _act(WatchAction a) {
    final w = widget.watch;
    final page = switch (a) {
      WatchAction.switchFund => SwitchPage(fromFundId: w.fund.id),
      WatchAction.openStatement =>
        w.statement == null
            ? const StatementCheckPage()
            : StatementDetailPage(saved: w.statement!),
      WatchAction.checkStatement => const StatementCheckPage(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget.watch;
    final f = w.fund;
    final score = w.score;
    final tone = score == null
        ? c.muted
        : (score >= 8 ? c.up : (score >= 5 ? c.accentInk : c.down));
    final signals = [...w.signals]
      ..sort((a, b) => _rank(a.level).compareTo(_rank(b.level)));
    final calm = reduceMotion(context);
    Color levelColor(WatchLevel l) => switch (l) {
      WatchLevel.ok => c.up,
      WatchLevel.watch => c.down,
      WatchLevel.info => c.line2,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: w.toWatch > 0 ? c.down.withValues(alpha: 0.45) : c.line,
        ),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: widget.open,
            child: InkWell(
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
                child: Row(
                  children: [
                    FundLogo(
                      domain: f.logoDomain,
                      logoUrl: ref.watch(logoUrlProvider(f.id)),
                      brandColor: ref.watch(brandColorProvider(f.id)),
                      seed: f.manager,
                      size: 40,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // One bar per check, so a folded card still
                              // says how it went.
                              for (final s in signals)
                                Container(
                                  width: 18,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: levelColor(s.level),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              const SizedBox(width: 2),
                              Text(
                                w.toWatch == 0
                                    ? t('watch.allClear')
                                    : t(
                                        w.toWatch == 1
                                            ? 'watch.oneToWatch'
                                            : 'watch.nToWatch',
                                        {'n': '${w.toWatch}'},
                                      ),
                                style: TextStyle(
                                  color: w.toWatch > 0 ? c.down : c.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (score != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$score',
                              style: fructaFonts.numeric(
                                color: tone,
                                size: 22,
                                weight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '/10',
                              style: fructaFonts.numeric(
                                color: c.faint,
                                size: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: widget.open ? 0.5 : 0,
                      duration: Duration(milliseconds: calm ? 0 : 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: c.faint,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: calm ? 0 : 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !widget.open
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (var i = 0; i < signals.length; i++)
                        _SignalRow(
                          signal: signals[i],
                          open: _detail.contains(i),
                          onTap: () => setState(
                            () => _detail.contains(i)
                                ? _detail.remove(i)
                                : _detail.add(i),
                          ),
                          onAct: signals[i].action == null
                              ? null
                              : () => _act(signals[i].action!),
                        ),
                      InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CompanyPage(f)),
                        ),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 46),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: c.line)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t('watch.openFund'),
                                  style: TextStyle(
                                    color: c.accentInk,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: c.faint,
                                size: 20,
                              ),
                            ],
                          ),
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

/// One check: its mark, title and value; the detail and next step on tap.
class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.signal,
    required this.open,
    required this.onTap,
    required this.onAct,
  });

  final WatchSignal signal;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback? onAct;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = signal;
    final calm = reduceMotion(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Semantics(
        button: true,
        expanded: open,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Mark(level: s.level),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s.title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (s.value.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        s.value,
                        style: fructaFonts.numeric(
                          color: switch (s.level) {
                            WatchLevel.ok => c.up,
                            WatchLevel.watch => c.down,
                            WatchLevel.info => c.muted,
                          },
                          size: 13,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                AnimatedSize(
                  duration: Duration(milliseconds: calm ? 0 : 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: !open
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(38, 8, 0, 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.detail,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 12.5,
                                  height: 1.45,
                                ),
                              ),
                              if (onAct != null) ...[
                                const SizedBox(height: 8),
                                Material(
                                  color: c.accentSoft,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: onAct,
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 36,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        t(switch (s.action!) {
                                          WatchAction.switchFund =>
                                            'watch.act.switch',
                                          WatchAction.openStatement =>
                                            'watch.act.statement',
                                          WatchAction.checkStatement =>
                                            'watch.act.check',
                                        }),
                                        style: TextStyle(
                                          color: c.accentInk,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
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

class _Mark extends StatelessWidget {
  const _Mark({required this.level});

  final WatchLevel level;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, fg, bg) = switch (level) {
      WatchLevel.ok => (Icons.check_rounded, c.up, c.upSoft),
      WatchLevel.watch => (Icons.priority_high_rounded, c.down, c.downSoft),
      WatchLevel.info => (Icons.info_outline_rounded, c.muted, c.s2),
    };
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 15, color: fg),
    );
  }
}

/// Count of funds with something to watch, for Pro home.
final fundWatchCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(fundWatchProvider).where((w) => w.toWatch > 0).length,
);

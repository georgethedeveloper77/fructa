import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/fund.dart';
import '../../data/models/fund_composition.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../company/company_page.dart';
import '../statements/statement_controller.dart';

enum WatchLevel { ok, watch, info }

/// One thing Fructa checked about a fund the user holds.
class WatchSignal {
  const WatchSignal(this.level, this.title, this.detail, this.value);

  final WatchLevel level;
  final String title;
  final String detail;
  final String value;
}

/// A held fund and what its signals say.
class FundWatch {
  const FundWatch(this.fund, this.signals);

  final Fund fund;
  final List<WatchSignal> signals;

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
            gap <= -0.25 ? WatchLevel.watch : WatchLevel.ok,
            t(gap <= -0.25 ? 'watch.underpays' : 'watch.paysAsPublished'),
            t('watch.gapDetail', {
              'credited': a.recentCreditedPct!.toStringAsFixed(2),
              'published': a.recentPublishedPct!.toStringAsFixed(2),
            }),
            '${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)} pts',
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

    out.add(FundWatch(f, s));
  }
  out.sort((x, y) => y.toWatch.compareTo(x.toWatch));
  return out;
});

/// Fund watch: a health check on every fund the user holds.
class FundWatchPage extends ConsumerWidget {
  const FundWatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final list = ref.watch(fundWatchProvider);
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    t('watch.sub'),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
                for (final w in list) _WatchCard(watch: w),
              ],
            ),
    );
  }
}

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch});

  final FundWatch watch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final f = watch.fund;
    final score = watch.score;
    final tone = score == null
        ? c.muted
        : (score >= 8 ? c.up : (score >= 5 ? c.accentInk : c.down));
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => CompanyPage(f))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  FundLogo(
                    domain: f.logoDomain,
                    logoUrl: ref.watch(logoUrlProvider(f.id)),
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
                        const SizedBox(height: 2),
                        Text(
                          watch.toWatch == 0
                              ? t('watch.allClear')
                              : t(
                                  watch.toWatch == 1
                                      ? 'watch.oneToWatch'
                                      : 'watch.nToWatch',
                                  {'n': '${watch.toWatch}'},
                                ),
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  if (score != null)
                    Text(
                      '$score/10',
                      style: fructaFonts.numeric(
                        color: tone,
                        size: 22,
                        weight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          for (final s in watch.signals)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Mark(level: s.level),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.detail,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
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
            ),
        ],
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

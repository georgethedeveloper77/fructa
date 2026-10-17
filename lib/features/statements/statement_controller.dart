import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/fund.dart';
import '../../data/models/holding.dart';
import '../../data/models/rate_history.dart';
import '../../data/models/remote_config.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/statement/published_average.dart';
import '../../engine/statement/statement_analysis.dart';
import '../../engine/statement/statement_model.dart';
import '../../engine/statement/statement_parser.dart';

/// Everything beyond the headline is Pro. Follows [proAccessProvider], so a
/// remote switch-off hides the full check rather than giving it away.
final statementFullAccessProvider = Provider<bool>(
  (ref) => ref.watch(proAccessProvider),
);

/// Admin-described managers as parser entries. A bad pattern is skipped, not
/// fatal: one typo in admin must not stop every statement from reading.
List<StatementManager> configManagers(RemoteConfig cfg) {
  final out = <StatementManager>[];
  for (final m in cfg.statementManagers) {
    try {
      out.add(
        StatementManager(m.key, m.name, RegExp(m.match, caseSensitive: false)),
      );
    } catch (_) {
      continue;
    }
  }
  return out;
}

/// Every manager the app tracks, as parser entries, tried after admin config
/// and the built-in list. Lets a statement from any fund in the snapshot be
/// named without a release: the pattern is the distinctive part of the
/// manager's name ("Old Mutual" from "Old Mutual Investment Group"), so the
/// short form a statement prints still matches.
List<StatementManager> trackedManagers(Iterable<Fund> funds) {
  const tail = {
    'asset',
    'assets',
    'investment',
    'investments',
    'management',
    'managers',
    'manager',
    'limited',
    'ltd',
    'plc',
    'kenya',
    'group',
    'bank',
    'company',
    'co',
    'fund',
    'funds',
  };
  final seen = <String>{};
  final out = <StatementManager>[];
  final names = {for (final f in funds) f.manager.trim()}.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    final words = name
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    while (words.length > 1 && tail.contains(words.last.toLowerCase())) {
      words.removeLast();
    }
    final core = words.join(' ');
    if (core.replaceAll(' ', '').length < 3 || !seen.add(core.toLowerCase())) {
      continue;
    }
    final key = core.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');
    out.add(
      StatementManager(
        key,
        name,
        RegExp(
          '\\b${words.map(RegExp.escape).join(r'[\s\-]*')}\\b',
          caseSensitive: false,
        ),
      ),
    );
  }
  return out;
}

/// The money market fund a statement belongs to: same manager (by name),
/// same currency. Retail funds first. Null when nothing fits, in which case
/// the user picks.
Fund? matchFund(StatementData d, Iterable<Fund> funds) {
  final name = _letters(d.managerName);
  if (name.isEmpty) return null;
  final hits =
      funds
          .where(
            (f) =>
                _letters(f.manager).contains(name) &&
                f.currency == d.currency &&
                (f.fundType == 'mmf' || f.fundType == null),
          )
          .toList()
        ..sort((a, b) => (b.retail ? 1 : 0) - (a.retail ? 1 : 0));
  return hits.isEmpty ? null : hits.first;
}

/// Funds from the same manager in the same currency, for the user to pick
/// from when [matchFund] is unsure.
List<Fund> candidateFunds(StatementData d, Iterable<Fund> funds) {
  final name = _letters(d.managerName);
  return funds
      .where(
        (f) =>
            f.currency == d.currency &&
            (name.isEmpty || _letters(f.manager).contains(name)),
      )
      .toList();
}

String _letters(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// The statement's deposits and withdrawals as ledger entries.
List<Txn> flowsOf(StatementData d) => [
  for (final e in d.entries)
    if (e.kind != StatementEntryKind.interest)
      Txn(
        amount: e.amount,
        type: e.amount >= 0 ? 'deposit' : 'withdrawal',
        date: e.date,
        source: 'statement',
        ref: e.ref,
      ),
];

/// The statement's closing balance as the holding's confirmed balance.
BalanceAnchor anchorOf(StatementData d) => BalanceAnchor(
  balance: d.closingBalance,
  date: d.to,
  label:
      '${d.managerName.isEmpty ? 'Fund' : d.managerName} statement, ${dayLabel(d.to)}',
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
String dayLabel(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}';
String monthLabel(DateTime d) => '${_mon[d.month - 1]} \u2019${d.year % 100}';

/// A saved statement's analysis plus what it was measured against.
class StatementResult {
  const StatementResult({
    required this.analysis,
    required this.fund,
    required this.publishedIsToday,
  });

  final StatementAnalysis analysis;

  /// The fund the statement belongs to, matched or chosen.
  final Fund? fund;

  /// True when Fructa's history did not reach back far enough and the gap is
  /// measured against today's published rate instead. The UI says so.
  final bool publishedIsToday;
}

/// The analysis of a saved statement, with the published rate averaged from
/// the matched fund's rate history over the same days.
///
/// Keyed by [SavedStatement.id]; reads the statement from the store, so a
/// re-match (new fund id) re-runs the analysis automatically.
final statementAnalysisProvider = FutureProvider.autoDispose
    .family<StatementResult, String>((ref, id) async {
      final all = await ref.watch(statementsProvider.future);
      final s = all.firstWhere((x) => x.id == id);
      final cfg = ref.watch(remoteConfigProvider);
      final funds = ref.watch(fundsByIdProvider);
      final fund = s.fundId != null
          ? funds[s.fundId]
          : matchFund(s.data, funds.values);
      var history = const <RateHistory>[];
      if (fund != null) {
        try {
          history = await ref.watch(historyProvider(fund.id).future);
        } catch (_) {
          history = const [];
        }
      }
      var usedToday = false;
      double? published(DateTime from, DateTime to) {
        final avg = publishedAverage(history, from, to);
        if (avg != null) return avg;
        usedToday = fund?.currentRate != null;
        return fund?.currentRate;
      }

      final a = StatementAnalyzer.analyze(
        s.data,
        whtPct: cfg.whtPct,
        taxFree: fund?.taxFree ?? false,
        published: fund == null ? null : published,
      );
      return StatementResult(
        analysis: a,
        fund: fund,
        publishedIsToday: usedToday,
      );
    });

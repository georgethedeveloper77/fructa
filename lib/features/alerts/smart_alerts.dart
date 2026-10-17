import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_notify.dart';
import '../../core/settings_prefs.dart';
import '../../data/models/fund.dart';
import '../../data/models/smart_alert.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/pro/pro_tuning.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../../engine/portfolio_math.dart';
import '../statements/statement_controller.dart';

/// Runs the smart alerts whenever their inputs change: a fresh rates snapshot
/// (better fund, rank drops) or a newly checked statement (underpaid, no
/// interest). Watched once by the main scaffold, which keeps it alive.
///
/// Everything is worked out on the phone. Each finding has a stable key, so
/// the same thing is never raised twice, and a drawer notification only goes
/// out when the user has alerts on and the alert type switched on.
final smartAlertsRunnerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<List<Fund>>>(ratesProvider, (prev, next) {
    final fresh = next.value;
    if (fresh == null) return;
    final old = prev?.value;
    Future.microtask(() => _runMarket(ref, old: old, fresh: fresh));
  });
  ref.listen<AsyncValue<List<SavedStatement>>>(statementsProvider, (_, next) {
    final list = next.value;
    if (list == null || list.isEmpty) return;
    Future.microtask(() => _runStatements(ref, list));
  });
});

bool _allowed(Ref ref, SmartAlertType t) {
  final unlocked = ref.read(proAccessProvider);
  return unlocked && (ref.read(smartAlertPrefsProvider)[t] ?? true);
}

Future<void> _raise(Ref ref, SmartAlert a) async {
  final isNew = await ref.read(smartAlertsProvider.notifier).add(a);
  if (!isNew) return;
  if (!ref.read(settingsControllerProvider).masterAlerts) return;
  unawaited(
    LocalNotify.show(
      id: a.key.hashCode & 0x7fffffff,
      title: a.title,
      body: a.body,
      target: a.target,
    ),
  );
}

String _week(DateTime d) {
  final monday = DateTime(
    d.year,
    d.month,
    d.day,
  ).subtract(Duration(days: d.weekday - 1));
  return '${monday.year}-${monday.month}-${monday.day}';
}

/// Funds of the same kind and currency as [f] that quote a rate.
List<Fund> _peers(Fund f, List<Fund> all) => all
    .where(
      (x) =>
          x.retail &&
          x.showsYield &&
          x.currentRate != null &&
          x.currency == f.currency &&
          x.fundType == f.fundType,
    )
    .toList();

String _money(String ccy, double v) {
  final whole = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return '$ccy $b';
}

Future<void> _runMarket(
  Ref ref, {
  List<Fund>? old,
  required List<Fund> fresh,
}) async {
  final wht = ref.read(remoteConfigProvider).whtPct;
  final tune = ref.read(proTuningProvider);
  double net(Fund f) => f.taxFree || !f.whtStillDue
      ? f.currentRate!
      : f.currentRate! * (1 - wht / 100);
  final now = DateTime.now();
  final byId = {for (final f in fresh) f.id: f};

  // ── A better fund for money you hold ─────────────────────────────────────
  if (_allowed(ref, SmartAlertType.betterFund)) {
    for (final h in ref.read(holdingsProvider)) {
      if (h.isSacco) continue;
      final mine = byId[h.fundId];
      if (mine == null || mine.currentRate == null || !mine.showsYield) {
        continue;
      }
      final peers = _peers(mine, fresh)
        ..sort((a, b) => net(b).compareTo(net(a)));
      if (peers.isEmpty || peers.first.id == mine.id) continue;
      final best = peers.first;
      final diff = net(best) - net(mine);
      if (diff <= 0) continue;
      final value = PortfolioMath.value(
        h,
        ratePercent: mine.currentRate,
        taxFree: mine.taxFree,
        usdKes: null,
      ).valueNative;
      final extra =
          value * diff / 100 - value * net(best) / 100 * tune.transitDays / 365;
      final floor = tune.floorFor(h.currency);
      if (extra < floor) continue;
      await _raise(
        ref,
        SmartAlert(
          key: 'better|${h.fundId}|${best.id}|${_week(now)}',
          type: SmartAlertType.betterFund,
          title:
              '${best.name} would pay you about ${_money(h.currency, extra)} more a year',
          body:
              'Than ${mine.name}, after tax and ${tune.transitDays} days in transit. Rates move, so this is a guide.',
          at: now,
          target: 'fund/${best.id}',
        ),
      );
    }
  }

  // ── A followed fund left the top 5 ───────────────────────────────────────
  if (old != null && _allowed(ref, SmartAlertType.rankDrop)) {
    final oldById = {for (final f in old) f.id: f};
    for (final id in ref.read(subscriptionsProvider)) {
      final f = byId[id];
      final was = oldById[id];
      if (f == null ||
          was == null ||
          f.currentRate == null ||
          was.currentRate == null) {
        continue;
      }
      int rankIn(Fund x, List<Fund> list) {
        final peers = _peers(x, list)
          ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
        return peers.indexWhere((p) => p.id == x.id) + 1;
      }

      final before = rankIn(was, old);
      final after = rankIn(f, fresh);
      if (before == 0 || after == 0) continue;
      if (before <= tune.rankTop && after > tune.rankTop) {
        final n = _peers(f, fresh).length;
        await _raise(
          ref,
          SmartAlert(
            key: 'rank|$id|$after|${now.year}-${now.month}-${now.day}',
            type: SmartAlertType.rankDrop,
            title: '${f.name} left the top ${tune.rankTop}',
            body:
                'Now #$after of $n ${f.currency} funds of its kind, at ${f.currentRate!.toStringAsFixed(2)}% gross. It was #$before.',
            at: now,
            target: 'fund/$id',
          ),
        );
      }
    }
  }
}

Future<void> _runStatements(Ref ref, List<SavedStatement> list) async {
  final tune = ref.read(proTuningProvider);
  // Latest statement per account only: older ones were already judged.
  final latest = <String, SavedStatement>{};
  for (final s in list) {
    final k = '${s.data.managerKey}|${s.data.accountNo}';
    final cur = latest[k];
    if (cur == null || s.data.to.isAfter(cur.data.to)) latest[k] = s;
  }
  final now = DateTime.now();
  for (final s in latest.values) {
    final StatementResult r;
    try {
      r = await ref.read(statementAnalysisProvider(s.id).future);
    } catch (_) {
      continue;
    }
    final a = r.analysis;
    final name = s.data.managerName.isEmpty ? 'Your fund' : s.data.managerName;

    final gap = a.gapPts;
    if (gap != null &&
        gap <= -tune.underpaidPts &&
        _allowed(ref, SmartAlertType.underpaid)) {
      await _raise(
        ref,
        SmartAlert(
          key: 'underpaid|${s.id}',
          type: SmartAlertType.underpaid,
          title:
              '$name paid ${gap.abs().toStringAsFixed(2)} pts below its published rate',
          body:
              'Credited ${a.recentCreditedPct!.toStringAsFixed(2)}% against ${a.recentPublishedPct!.toStringAsFixed(2)}%, from your statement to ${dayLabel(s.data.to)}.',
          at: now,
          target: 'portfolio',
        ),
      );
    }

    final missing = a.findings
        .where((f) => f.key == 'statement.find.missingMonths')
        .firstOrNull;
    if (missing != null && _allowed(ref, SmartAlertType.noInterest)) {
      await _raise(
        ref,
        SmartAlert(
          key: 'nointerest|${s.id}',
          type: SmartAlertType.noInterest,
          title: '$name credited no interest in ${missing.vars['months']}',
          body:
              'From your statement to ${dayLabel(s.data.to)}. Worth asking the manager why.',
          at: now,
          target: 'portfolio',
        ),
      );
    }
  }
}

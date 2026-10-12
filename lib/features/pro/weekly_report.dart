import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/rate_basis.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../engine/portfolio_math.dart';
import '../today/today_providers.dart';

/// One holding's contribution to the week.
class WeekHolding {
  const WeekHolding(
    this.name,
    this.currency,
    this.earnedNative,
    this.earnedKes,
  );

  final String name;
  final String currency;

  /// Accrual over the window in the holding's own currency.
  final double earnedNative;

  /// Same, in KES. Null when the holding is USD and no FX is published.
  final double? earnedKes;
}

/// One followed fund's move over the week.
class WeekFollow {
  const WeekFollow(this.fund, this.net, this.delta);

  final Fund fund;
  final double? net;

  /// Seven-day move in points, null when no event carried one.
  final double? delta;
}

/// Everything the weekly report shows, computed on the device.
class WeeklyReport {
  const WeeklyReport({
    required this.start,
    required this.end,
    required this.holdings,
    required this.earnedKes,
    required this.valueStartKes,
    required this.follows,
    required this.leaders,
    required this.leaderChanges,
    required this.auctions,
    required this.tbill91,
  });

  final DateTime start;
  final DateTime end;
  final List<WeekHolding> holdings;

  /// Total accrual across holdings that could be valued in KES.
  final double earnedKes;

  /// Book value in KES at the start of the window, for the percentage.
  final double valueStartKes;

  final List<WeekFollow> follows;
  final List<TodayLeader> leaders;
  final int leaderChanges;
  final int auctions;
  final double tbill91;

  /// Week-on-week change of the book, or null with nothing to value.
  double? get pct => valueStartKes > 0 ? earnedKes / valueStartKes * 100 : null;
}

/// The last seven days, ending now.
///
/// Earnings are the difference between each holding's accrued value now and a
/// week ago. PortfolioMath carries a lot dated inside the window at face value
/// on the earlier date, so a deposit made mid-week contributes only the
/// interest it earned since, never its principal: this is accrual, not money
/// added.
final weeklyReportProvider = Provider<WeeklyReport>((ref) {
  final end = DateTime.now();
  final start = end.subtract(const Duration(days: 7));
  final fx = ref.watch(usdKesProvider);
  final wht = ref.watch(remoteConfigProvider).whtPct;

  final holdings = <WeekHolding>[];
  var earnedKes = 0.0;
  var valueStartKes = 0.0;
  for (final h in ref.watch(holdingsProvider)) {
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    if (s == null) continue;
    final now = PortfolioMath.value(
      h,
      ratePercent: s.ratePercent,
      taxFree: s.taxFree,
      usdKes: fx,
      asOf: end,
    );
    final then = PortfolioMath.value(
      h,
      ratePercent: s.ratePercent,
      taxFree: s.taxFree,
      usdKes: fx,
      asOf: start,
    );
    final earnedNative = now.valueNative - then.valueNative;
    final kes = (now.valueKes != null && then.valueKes != null)
        ? now.valueKes! - then.valueKes!
        : null;
    holdings.add(WeekHolding(s.name, h.currency, earnedNative, kes));
    if (kes != null) {
      earnedKes += kes;
      valueStartKes += then.valueKes!;
    }
  }
  holdings.sort((a, b) => (b.earnedKes ?? 0).compareTo(a.earnedKes ?? 0));

  final byId = ref.watch(fundsByIdProvider);
  final follows = [
    for (final id in ref.watch(subscriptionsProvider))
      if (byId[id] case final f?)
        WeekFollow(f, f.netRate(wht), ref.watch(fundDeltaProvider(f.id))),
  ]..sort((a, b) => (b.delta?.abs() ?? 0).compareTo(a.delta?.abs() ?? 0));

  final inWindow = ref
      .watch(marketEventsProvider)
      .where((e) => e.createdAt.isAfter(start))
      .toList();

  return WeeklyReport(
    start: start,
    end: end,
    holdings: holdings,
    earnedKes: earnedKes,
    valueStartKes: valueStartKes,
    follows: follows,
    leaders: ref.watch(todayLeadersProvider),
    leaderChanges: inWindow.where((e) => e.type == 'leader_change').length,
    auctions: inWindow.where((e) => e.type == 'auction_result').length,
    tbill91: ref.watch(remoteConfigProvider).tbill91Pct,
  );
});

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

/// `5 to 12 Oct`, or `28 Sep to 5 Oct` across a month boundary.
String weekRangeLabel(DateTime start, DateTime end) {
  final a = start.month == end.month
      ? '${start.day}'
      : '${start.day} ${_mon[start.month - 1]}';
  return t('report.range', {
    'from': a,
    'to': '${end.day} ${_mon[end.month - 1]}',
  });
}

/// The Pro weekly report.
class WeeklyReportPage extends ConsumerWidget {
  const WeeklyReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final r = ref.watch(weeklyReportProvider);
    final hidden = ref.watch(
      settingsControllerProvider.select((p) => p.hideBalances),
    );
    String kes(double v) => hidden
        ? 'KES \u2022\u2022\u2022\u2022'
        : '${v >= 0 ? '+' : '-'}${money('KES', v.abs())}';

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            t('report.kicker'),
            style: TextStyle(
              color: c.accentInk,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('report.title'),
            style: TextStyle(
              color: c.text,
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            weekRangeLabel(r.start, r.end),
            style: TextStyle(color: c.muted, fontSize: 14),
          ),

          // ── Your money ─────────────────────────────────────────────────
          if (r.holdings.isNotEmpty) ...[
            _Heading(t('report.money')),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('report.earned'),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kes(r.earnedKes),
                    style: fructaFonts.numeric(
                      color: c.delta(r.earnedKes),
                      size: 32,
                      weight: FontWeight.w600,
                      letterSpacing: -0.8,
                    ),
                  ),
                  if (r.pct case final p?)
                    Text(
                      t('report.ofBook', {
                        'pct': '${p >= 0 ? '+' : ''}${p.toStringAsFixed(2)}%',
                      }),
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  const SizedBox(height: 10),
                  for (final h in r.holdings)
                    _Row(
                      label: h.name,
                      value: hidden
                          ? '\u2022\u2022\u2022\u2022'
                          : h.earnedKes != null
                          ? kes(h.earnedKes!)
                          : '${h.earnedNative >= 0 ? '+' : '-'}${h.currency} ${h.earnedNative.abs().toStringAsFixed(2)}',
                      color: c.delta(h.earnedNative),
                    ),
                ],
              ),
            ),
          ],

          // ── Funds you follow ───────────────────────────────────────────
          if (r.follows.isNotEmpty) ...[
            _Heading(t('report.following')),
            _Card(
              child: Column(
                children: [
                  for (final f in r.follows)
                    _Row(
                      label: f.fund.name,
                      sub: f.net == null
                          ? null
                          : t('today.netOf', {
                              'rate': '${f.net!.toStringAsFixed(2)}%',
                            }),
                      value: f.delta == null || f.delta == 0
                          ? t('report.noMove')
                          : t('today.pts', {
                              'v':
                                  '${f.delta! > 0 ? '+' : ''}${f.delta!.toStringAsFixed(2)}',
                            }),
                      color: f.delta == null || f.delta == 0
                          ? c.muted
                          : c.delta(f.delta!),
                    ),
                ],
              ),
            ),
          ],

          // ── The market ─────────────────────────────────────────────────
          _Heading(t('report.market')),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in r.leaders)
                  _Row(
                    dot: l.category.color,
                    label: t(l.category.labelKey),
                    sub: l.fund.name,
                    value:
                        '${l.shown(ref.watch(showNetProvider)).toStringAsFixed(2)}%',
                    color: c.text,
                  ),
                _Row(
                  dot: TodayCategory.tbill.color,
                  label: t('today.tbill'),
                  value: '${r.tbill91.toStringAsFixed(2)}%',
                  color: c.text,
                ),
                const SizedBox(height: 8),
                Text(
                  t('report.events', {
                    'leaders': '${r.leaderChanges}',
                    'auctions': '${r.auctions}',
                  }),
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Text(
            t('report.foot'),
            style: TextStyle(color: c.faint, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: c.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.color,
    this.sub,
    this.dot,
  });

  final String label;
  final String? sub;
  final String value;
  final Color color;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub != null)
                  Text(sub!, style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: fructaFonts.numeric(
              color: color,
              size: 14,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

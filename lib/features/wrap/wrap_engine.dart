import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/fund.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../pro/weekly_report.dart';
import '../statements/statement_controller.dart';

/// Colour family of a slide, resolved against the story palette in the UI.
enum WrapTone { up, down, info, tbill, accent }

/// One story in the Weekly wrap.
class WrapSlide {
  const WrapSlide({
    required this.tagKey,
    required this.title,
    required this.big,
    required this.unit,
    required this.line,
    required this.tone,
    this.series = const [],
    this.fundId,
    this.personal = false,
  });

  /// i18n key for the small caps label (`wrap.tag.improved`).
  final String tagKey;
  final String title;

  /// The one big figure.
  final String big;
  final String unit;

  /// One sentence. Long ones are tap-to-reveal in the viewer.
  final String line;
  final WrapTone tone;

  /// Line drawn under the figure; empty draws nothing.
  final List<double> series;

  /// The fund the story is about, for the badge and "open fund".
  final String? fundId;

  /// Built from the user's own holdings or statements (Pro).
  final bool personal;
}

/// A medal on a Markets row, linking back to its story.
class FundBadge {
  const FundBadge(this.labelKey, this.tone, this.slideIndex);

  final String labelKey;
  final WrapTone tone;
  final int slideIndex;
}

/// This week's wrap: market stories everyone sees, then the user's own.
class WeeklyWrap {
  const WeeklyWrap({
    required this.from,
    required this.to,
    required this.market,
    required this.personal,
    required this.badges,
  });

  final DateTime from;
  final DateTime to;
  final List<WrapSlide> market;
  final List<WrapSlide> personal;
  final Map<String, FundBadge> badges;

  List<WrapSlide> get all => [...market, ...personal];
}

String _pts(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';
String _pct(double v) => '${v.toStringAsFixed(2)}%';

/// The KES money market funds the market stories compare. One currency and
/// one fund type, so every figure in a story is like for like.
List<Fund> _field(List<Fund> funds) => funds
    .where(
      (f) =>
          f.retail &&
          f.showsYield &&
          f.currency == 'KES' &&
          f.fundType == 'mmf' &&
          f.currentRate != null,
    )
    .toList();

/// Worked out on the phone from the snapshot each time it refreshes: no new
/// data, nothing sent anywhere. Each market story is skipped when the data
/// cannot support it (no moves this week, too little history), so the wrap
/// never fills a slide with a made-up number.
final weeklyWrapProvider = Provider.autoDispose<WeeklyWrap>((ref) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 7));
  final cfg = ref.watch(remoteConfigProvider);
  final field = _field(ref.watch(ratesProvider).value ?? const <Fund>[]);
  final market = <WrapSlide>[];
  final badges = <String, FundBadge>{};

  // ── Most improved and biggest drop, from the 7-day rate events ───────────
  Fund? up;
  Fund? down;
  double upD = 0;
  double downD = 0;
  for (final f in field) {
    final d = ref.watch(fundDeltaProvider(f.id));
    if (d == null) continue;
    if (d > upD) {
      upD = d;
      up = f;
    }
    if (d < downD) {
      downD = d;
      down = f;
    }
  }
  if (up != null) {
    badges[up.id] = FundBadge(
      'wrap.badge.improved',
      WrapTone.up,
      market.length,
    );
    market.add(
      WrapSlide(
        tagKey: 'wrap.tag.improved',
        title: up.name,
        big: _pts(upD),
        unit: 'pts in 7 days \u00b7 now ${_pct(up.currentRate!)} gross',
        line:
            'The biggest climb among ${field.length} KES money market funds this week.',
        tone: WrapTone.up,
        series: up.spark,
        fundId: up.id,
      ),
    );
  }
  if (down != null) {
    market.add(
      WrapSlide(
        tagKey: 'wrap.tag.drop',
        title: down.name,
        big: _pts(downD),
        unit: 'pts in 7 days \u00b7 now ${_pct(down.currentRate!)} gross',
        line: 'The biggest fall among KES money market funds this week.',
        tone: WrapTone.down,
        series: down.spark,
        fundId: down.id,
      ),
    );
  }

  // ── Most stable: smallest spread of recent prints, among the better half ─
  final rates = field.map((f) => f.currentRate!).toList()..sort();
  final median = rates.isEmpty ? 0.0 : rates[rates.length ~/ 2];
  Fund? stable;
  var spread = double.infinity;
  for (final f in field) {
    if (f.spark.length < 6 || f.currentRate! < median) continue;
    final hi = f.spark.reduce((a, b) => a > b ? a : b);
    final lo = f.spark.reduce((a, b) => a < b ? a : b);
    if (hi - lo < spread) {
      spread = hi - lo;
      stable = f;
    }
  }
  if (stable != null) {
    badges.putIfAbsent(
      stable.id,
      () => FundBadge('wrap.badge.stable', WrapTone.info, market.length),
    );
    market.add(
      WrapSlide(
        tagKey: 'wrap.tag.stable',
        title: stable.name,
        big: _pct(stable.currentRate!),
        unit: spread < 0.005
            ? 'unchanged across its last ${stable.spark.length} prints'
            : 'moved only ${spread.toStringAsFixed(2)} pts across its last ${stable.spark.length} prints',
        line: 'The steadiest rate in the better-paying half of the market.',
        tone: WrapTone.info,
        series: stable.spark,
        fundId: stable.id,
      ),
    );
  }

  // ── Moving up: places climbed, from where each fund's line started ───────
  final withHistory = field.where((f) => f.spark.length >= 2).toList();
  if (withHistory.length >= 3) {
    final before = [...withHistory]
      ..sort((a, b) => b.spark.first.compareTo(a.spark.first));
    final after = [...withHistory]
      ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
    Fund? climber;
    var places = 0;
    for (var i = 0; i < after.length; i++) {
      final was = before.indexWhere((f) => f.id == after[i].id);
      if (was - i > places) {
        places = was - i;
        climber = after[i];
      }
    }
    if (climber != null) {
      final rank = after.indexWhere((f) => f.id == climber!.id) + 1;
      badges.putIfAbsent(
        climber.id,
        () => FundBadge('wrap.badge.movingUp', WrapTone.up, market.length),
      );
      market.add(
        WrapSlide(
          tagKey: 'wrap.tag.movingUp',
          title: climber.name,
          big: '+$places',
          unit: places == 1
              ? 'place \u00b7 now #$rank of ${after.length}'
              : 'places \u00b7 now #$rank of ${after.length}',
          line: 'The biggest climb in the KES money market ranking.',
          tone: WrapTone.up,
          series: climber.spark,
          fundId: climber.id,
        ),
      );
    }
  }

  // ── Beating the T-bill ───────────────────────────────────────────────────
  final tb = cfg.tbill91Pct;
  final above = field.where((f) => f.currentRate! > tb).toList()
    ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
  if (field.isNotEmpty) {
    if (above.isNotEmpty) {
      badges.putIfAbsent(
        above.first.id,
        () => FundBadge('wrap.badge.top', WrapTone.accent, market.length),
      );
    }
    market.add(
      WrapSlide(
        tagKey: 'wrap.tag.tbill',
        title: '91-day Treasury bill at ${_pct(tb)}',
        big: '${above.length} of ${field.length}',
        unit: 'KES money market funds pay more, before tax',
        line: above.isEmpty
            ? 'No KES money market fund beats the bill this week.'
            : 'The best, ${above.first.name}, pays ${_pts(above.first.currentRate! - tb)} pts more.',
        tone: WrapTone.tbill,
      ),
    );
  }

  // ── Your week (Pro): only what the user's own data can support ───────────
  final personal = <WrapSlide>[];
  final report = ref.watch(weeklyReportProvider);
  if (report.holdings.isNotEmpty) {
    final bps = report.pct == null ? null : report.pct! * 100;
    final best = [...report.holdings]
      ..sort((a, b) => (b.earnedKes ?? 0).compareTo(a.earnedKes ?? 0));
    personal.add(
      WrapSlide(
        tagKey: 'wrap.tag.earned',
        title: 'Interest across your portfolio',
        big: '+KES ${report.earnedKes.toStringAsFixed(2)}',
        unit: bps == null
            ? 'this week'
            : '+${bps.toStringAsFixed(1)} bps on your portfolio this week',
        line: best.length > 1
            ? 'Your biggest earner was ${best.first.name}.'
            : 'All of it from ${best.first.name}.',
        tone: WrapTone.up,
        personal: true,
      ),
    );
  }
  final statements =
      ref.watch(statementsProvider).value ?? const <SavedStatement>[];
  if (statements.isNotEmpty) {
    final s = statements.first;
    final gap = ref
        .watch(statementAnalysisProvider(s.id))
        .value
        ?.analysis
        .gapPts;
    if (gap != null) {
      personal.add(
        WrapSlide(
          tagKey: 'wrap.tag.statement',
          title: '${s.data.managerName} \u00b7 ${s.data.currency}',
          big: _pts(gap),
          unit: 'pts a year against its published rate',
          line: gap <= -0.25
              ? 'From your statement to ${dayLabel(s.data.to)}. Worth comparing with the top funds in Markets.'
              : 'From your statement to ${dayLabel(s.data.to)}. Paid in line with what it advertised.',
          tone: gap <= -0.25 ? WrapTone.down : WrapTone.up,
          personal: true,
        ),
      );
    }
    final m = cfg.statementManager(s.data.managerKey);
    if (m?.releaseDay != null) {
      var next = DateTime(now.year, now.month, m!.releaseDay!);
      if (!next.isAfter(now))
        next = DateTime(now.year, now.month + 1, m.releaseDay!);
      final days = next
          .difference(DateTime(now.year, now.month, now.day))
          .inDays;
      personal.add(
        WrapSlide(
          tagKey: 'wrap.tag.next',
          title: 'Your next ${m.name} statement',
          big: days == 1 ? '1 day' : '$days days',
          unit: 'until it usually arrives',
          line: 'We will remind you that morning.',
          tone: WrapTone.accent,
          personal: true,
        ),
      );
    }
  }

  return WeeklyWrap(
    from: from,
    to: now,
    market: market,
    personal: personal,
    badges: badges,
  );
});

/// Pro decides whether the personal slides open. While Pro is switched off
/// remotely there is nothing to sell, so they are open to everyone.
final wrapPersonalUnlockedProvider = Provider<bool>((ref) {
  if (!ref.watch(proEnabledProvider)) return true;
  return ref.watch(isProProvider);
});

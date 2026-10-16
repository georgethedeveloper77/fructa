import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/fund.dart';
import '../../engine/portfolio_math.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../../data/statements/statement_store.dart';
import '../pro/weekly_report.dart';
import '../statements/statement_controller.dart';
import 'wrap_feed.dart';

/// Colour family of a slide, resolved against the story palette in the UI.
enum WrapTone { up, down, info, tbill, accent }

/// Which chart a story draws under its figure. Each kind has two labelled
/// axes; the viewer picks the scale.
enum WrapChartKind {
  /// No chart (personal slides with no series).
  none,

  /// A rate over dated days, with the start level and a bracket for the move.
  line,

  /// Like [line], drawn as steps so a cut lands on the day it happened.
  step,

  /// A flat rate set inside the field's low to high range.
  band,

  /// Ranking, #1 at the top of the axis.
  rank,

  /// One bar per fund, best first, against a reference rate.
  bars,
}

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
    this.chart = WrapChartKind.none,
    this.windowDays = 7,
    this.refRate,
    this.refKey,
    this.field = const [],
    this.rankFrom,
    this.rankTo,
    this.rankOf,
    this.points = const [],
    this.type,
    this.ratio,
    this.trendWeeks,
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

  /// Chart drawn under the figure.
  final WrapChartKind chart;

  /// Days of dated history the chart covers, ending today.
  final int windowDays;

  /// Reference rate drawn across the chart (category average, the T-bill).
  final double? refRate;

  /// i18n key for the reference label, with a `{v}` slot for the rate.
  final String? refKey;

  /// [WrapChartKind.bars]: every fund's rate, best first.
  /// [WrapChartKind.band]: the field's low and high rate now.
  final List<double> field;

  /// [WrapChartKind.rank]: place at the start of the window, place now, and
  /// how many funds were ranked.
  final int? rankFrom;
  final int? rankTo;
  final int? rankOf;

  /// Dated points for the chart, from a server story. Empty for stories built
  /// on the phone, whose chart reads the fund's history instead.
  final List<({DateTime day, double v})> points;

  /// The server's story type (improved, drop, stable, breadth...), for badges.
  final String? type;

  /// How unusual the move was: its size over the fund's normal weekly move.
  final double? ratio;

  /// Consecutive weeks the fund has moved the same way.
  final int? trendWeeks;

  Map<String, dynamic> toMap() => {
    'tag': tagKey,
    'title': title,
    'big': big,
    'unit': unit,
    'line': line,
    'tone': tone.name,
    'series': series,
    'fund': fundId,
    'personal': personal,
    'chart': chart.name,
    'window': windowDays,
    'ref': refRate,
    'refKey': refKey,
    'field': field,
    'rankFrom': rankFrom,
    'rankTo': rankTo,
    'rankOf': rankOf,
    'points': [
      for (final p in points) [p.day.toIso8601String().substring(0, 10), p.v],
    ],
    'type': type,
    'ratio': ratio,
    'trend': trendWeeks,
  };

  static WrapSlide fromMap(Map m) => WrapSlide(
    tagKey: m['tag'] as String,
    title: m['title'] as String,
    big: m['big'] as String,
    unit: m['unit'] as String,
    line: m['line'] as String,
    tone: WrapTone.values.byName(m['tone'] as String),
    series: ((m['series'] as List?) ?? const [])
        .map((x) => (x as num).toDouble())
        .toList(),
    fundId: m['fund'] as String?,
    personal: (m['personal'] as bool?) ?? false,
    // Weeks archived before charts existed carry none of these keys.
    chart: WrapChartKind.values.asNameMap()[m['chart']] ?? WrapChartKind.none,
    windowDays: (m['window'] as int?) ?? 7,
    refRate: (m['ref'] as num?)?.toDouble(),
    refKey: m['refKey'] as String?,
    field: ((m['field'] as List?) ?? const [])
        .map((x) => (x as num).toDouble())
        .toList(),
    rankFrom: m['rankFrom'] as int?,
    rankTo: m['rankTo'] as int?,
    rankOf: m['rankOf'] as int?,
    points: [
      for (final p in (m['points'] as List?) ?? const [])
        if (p is List && p.length == 2)
          (day: DateTime.parse('${p[0]}'), v: (p[1] as num).toDouble()),
    ],
    type: m['type'] as String?,
    ratio: (m['ratio'] as num?)?.toDouble(),
    trendWeeks: m['trend'] as int?,
  );
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
/// The week's wrap. The server's published week leads, the same for everyone
/// and built from approved rates; the user's own stories always come from the
/// phone. Before the first Friday publish, or offline with nothing kept, the
/// stories built on the phone stand in.
final weeklyWrapProvider = Provider.autoDispose<WeeklyWrap>((ref) {
  final local = ref.watch(localWeeklyWrapProvider);
  final server = ref.watch(serverWeekProvider);
  if (server == null) return local;
  const badgeFor = {
    'improved': ('wrap.badge.improved', WrapTone.up),
    'stable': ('wrap.badge.stable', WrapTone.info),
    'moving_up': ('wrap.badge.movingUp', WrapTone.up),
    'leader': ('wrap.badge.top', WrapTone.accent),
  };
  final badges = <String, FundBadge>{};
  for (var i = 0; i < server.slides.length; i++) {
    final s = server.slides[i];
    final b = badgeFor[s.type];
    if (b == null || s.fundId == null) continue;
    badges.putIfAbsent(s.fundId!, () => FundBadge(b.$1, b.$2, i));
  }
  return WeeklyWrap(
    from: server.from,
    to: server.to,
    market: server.slides,
    personal: local.personal,
    badges: badges,
  );
});

/// The wrap worked out on the phone from the snapshot.
final localWeeklyWrapProvider = Provider.autoDispose<WeeklyWrap>((ref) {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 7));
  final cfg = ref.watch(remoteConfigProvider);
  final field = _field(ref.watch(ratesProvider).value ?? const <Fund>[]);
  final market = <WrapSlide>[];
  final badges = <String, FundBadge>{};
  final avg = field.isEmpty
      ? null
      : field.map((f) => f.currentRate!).reduce((a, b) => a + b) / field.length;

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
        chart: WrapChartKind.line,
        refRate: avg,
        refKey: 'wrap.axis.avg',
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
        chart: WrapChartKind.step,
        refRate: avg,
        refKey: 'wrap.axis.avg',
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
        chart: WrapChartKind.band,
        windowDays: 90,
        field: [rates.first, rates.last],
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
          chart: WrapChartKind.rank,
          rankFrom: rank + places,
          rankTo: rank,
          rankOf: after.length,
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
        chart: WrapChartKind.bars,
        refRate: tb,
        refKey: 'wrap.axis.tbill',
        field: [
          for (final f in [
            ...field,
          ]..sort((a, b) => b.currentRate!.compareTo(a.currentRate!)))
            f.currentRate!,
        ],
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
      if (!next.isAfter(now)) {
        next = DateTime(now.year, now.month + 1, m.releaseDay!);
      }
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

// ── Month wrap ────────────────────────────────────────────────────────────

/// One holding's month, for the slides and the PDF table.
class MonthHolding {
  const MonthHolding(this.name, this.currency, this.earnedKes, this.verified);

  final String name;
  final String currency;
  final double earnedKes;

  /// The holding's balance is confirmed by a statement.
  final bool verified;
}

/// Last calendar month: what the user's money earned, what their statements
/// showed, and where the market stood. Pro.
class MonthWrap {
  const MonthWrap({
    required this.from,
    required this.to,
    required this.slides,
    required this.holdings,
    required this.earnedKes,
    required this.startKes,
    required this.topFunds,
    required this.tbill91,
  });

  final DateTime from;
  final DateTime to;
  final List<WrapSlide> slides;
  final List<MonthHolding> holdings;
  final double earnedKes;
  final double startKes;

  /// The five best KES money market rates now, gross: (name, rate).
  final List<(String, double)> topFunds;
  final double tbill91;

  double? get pct => startKes > 0 ? earnedKes / startKes * 100 : null;
}

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

String monthName(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// Earnings are accrual between the first and last day of the month, the same
/// method as the weekly report: a deposit made mid-month contributes only the
/// interest it earned, never its principal.
final monthWrapProvider = Provider.autoDispose<MonthWrap>((ref) {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month - 1, 1);
  final to = DateTime(
    now.year,
    now.month,
    1,
  ).subtract(const Duration(seconds: 1));
  final fx = ref.watch(usdKesProvider);
  final cfg = ref.watch(remoteConfigProvider);

  final holdings = <MonthHolding>[];
  var earned = 0.0;
  var start = 0.0;
  for (final h in ref.watch(holdingsProvider)) {
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    if (s == null) continue;
    final a = PortfolioMath.value(
      h,
      ratePercent: s.ratePercent,
      taxFree: s.taxFree,
      usdKes: fx,
      asOf: from,
    );
    final b = PortfolioMath.value(
      h,
      ratePercent: s.ratePercent,
      taxFree: s.taxFree,
      usdKes: fx,
      asOf: to,
    );
    if (a.valueKes == null || b.valueKes == null) continue;
    final e = b.valueKes! - a.valueKes!;
    holdings.add(MonthHolding(s.name, h.currency, e, h.isVerified));
    earned += e;
    start += a.valueKes!;
  }
  holdings.sort((x, y) => y.earnedKes.compareTo(x.earnedKes));

  final field = _field(ref.watch(ratesProvider).value ?? const <Fund>[])
    ..sort((a, b) => b.currentRate!.compareTo(a.currentRate!));
  final top = [for (final f in field.take(5)) (f.name, f.currentRate!)];

  final month = monthName(from);
  final slides = <WrapSlide>[];
  if (holdings.isNotEmpty) {
    final bps = start > 0 ? earned / start * 10000 : null;
    slides.add(
      WrapSlide(
        tagKey: 'wrap.tag.earned',
        title: 'Interest across your portfolio in $month',
        big: '+KES ${earned.toStringAsFixed(2)}',
        unit: bps == null
            ? 'in $month'
            : '+${bps.toStringAsFixed(0)} bps on your portfolio',
        line: holdings.length > 1
            ? 'Your biggest earner was ${holdings.first.name}.'
            : 'All of it from ${holdings.first.name}.',
        tone: WrapTone.up,
        personal: true,
      ),
    );
  }
  final statements =
      (ref.watch(statementsProvider).value ?? const <SavedStatement>[])
          .where((s) => !s.data.to.isBefore(from))
          .toList();
  for (final s in statements.take(2)) {
    final gap = ref
        .watch(statementAnalysisProvider(s.id))
        .value
        ?.analysis
        .gapPts;
    if (gap == null) continue;
    slides.add(
      WrapSlide(
        tagKey: 'wrap.tag.statement',
        title: '${s.data.managerName} \u00b7 ${s.data.currency}',
        big: _pts(gap),
        unit: 'pts a year against its published rate',
        line: 'From your statement to ${dayLabel(s.data.to)}.',
        tone: gap <= -0.25 ? WrapTone.down : WrapTone.up,
        personal: true,
      ),
    );
  }
  if (top.isNotEmpty) {
    slides.add(
      WrapSlide(
        tagKey: 'wrap.tag.top',
        title: top.first.$1,
        big: _pct(top.first.$2),
        unit: 'the best KES money market rate now, gross',
        line: holdings.isEmpty
            ? 'Followed by ${top.skip(1).take(2).map((t) => t.$1).join(' and ')}.'
            : 'Compare it with what your statement shows you were paid.',
        tone: WrapTone.accent,
      ),
    );
  }
  slides.add(
    WrapSlide(
      tagKey: 'wrap.tag.tbill',
      title: '91-day Treasury bill',
      big: _pct(cfg.tbill91Pct),
      unit: 'the benchmark every fund is measured against',
      line:
          'Money market funds above it are paying you to take a little more risk.',
      tone: WrapTone.tbill,
    ),
  );

  return MonthWrap(
    from: from,
    to: to,
    slides: slides,
    holdings: holdings,
    earnedKes: earned,
    startKes: start,
    topFunds: top,
    tbill91: cfg.tbill91Pct,
  );
});

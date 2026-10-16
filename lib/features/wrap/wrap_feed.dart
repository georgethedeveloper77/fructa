import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../data/providers.dart';
import '../reports/report_archive.dart';
import 'wrap_engine.dart';

/// The periods the server publishes stories for.
enum WrapPeriod { day, week, month, quarter, year }

/// One published wrap from the server: the same market stories for everyone,
/// built from approved rates only (build-wraps, wraps.json).
class ServerWrap {
  const ServerWrap({
    required this.id,
    required this.period,
    required this.from,
    required this.to,
    required this.label,
    required this.lead,
    required this.slides,
    this.median,
    this.move,
    this.big = false,
  });

  final String id;
  final WrapPeriod period;
  final DateTime from;
  final DateTime to;
  final String label;
  final String? lead;
  final List<WrapSlide> slides;

  /// The KES money market median at the period's end, and its move over the
  /// period, for the archive's timeline and calendar.
  final double? median;
  final double? move;

  /// The period had an unusually large story.
  final bool big;

  static ServerWrap? fromMap(Map m) {
    final period = WrapPeriod.values.asNameMap()[m['period']];
    final from = DateTime.tryParse('${m['start']}');
    final to = DateTime.tryParse('${m['end']}');
    if (period == null || from == null || to == null) return null;
    return ServerWrap(
      id: '${m['id']}',
      period: period,
      from: from,
      to: to,
      label: '${m['label'] ?? ''}',
      lead: m['lead'] as String?,
      median: (m['median'] as num?)?.toDouble(),
      move: (m['move'] as num?)?.toDouble(),
      big: m['big'] == true,
      slides: [
        for (final s in (m['stories'] as List? ?? const []))
          if (s is Map) ?slideFromServer(s),
      ],
    );
  }
}

/// A server story as a [WrapSlide]. Each one carries its own dated points, so
/// the chart draws at once with no history fetch.
WrapSlide? slideFromServer(Map s) {
  final tag = s['tag_key'];
  final title = s['title'];
  if (tag is! String || title is! String) return null;
  final chart = (s['chart'] as Map?) ?? const {};
  final stats = (s['stats'] as Map?) ?? const {};
  final points = <({DateTime day, double v})>[
    for (final p in (chart['points'] as List? ?? const []))
      if (p is List && p.length == 2 && DateTime.tryParse('${p[0]}') != null)
        (day: DateTime.parse('${p[0]}'), v: (p[1] as num).toDouble()),
  ];
  return WrapSlide(
    tagKey: tag,
    title: title,
    big: '${s['big'] ?? ''}',
    unit: '${s['unit'] ?? ''}',
    line: '${s['line'] ?? ''}',
    tone: WrapTone.values.asNameMap()[s['tone']] ?? WrapTone.info,
    series: [for (final p in points) p.v],
    points: points,
    fundId: s['fund_id'] as String?,
    chart:
        WrapChartKind.values.asNameMap()[chart['kind']] ?? WrapChartKind.none,
    windowDays: points.length < 2
        ? 7
        : points.last.day.difference(points.first.day).inDays,
    refRate: (chart['ref'] as num?)?.toDouble(),
    refKey: chart['ref_key'] as String?,
    field: [
      for (final x in (chart['field'] as List? ?? const []))
        if (x is num) x.toDouble(),
    ],
    rankFrom: (chart['rank_from'] as num?)?.toInt(),
    rankTo: (chart['rank_to'] as num?)?.toInt(),
    rankOf: (chart['rank_of'] as num?)?.toInt(),
    type: s['type'] as String?,
    ratio: (stats['ratio'] as num?)?.toDouble(),
    trendWeeks: (stats['trend_weeks'] as num?)?.toInt(),
    value: (stats['value'] as num?)?.toDouble(),
  );
}

/// Every live wrap the server lists, newest first within each period.
///
/// Fetched with ETag revalidation and kept on the phone, so it opens offline
/// and a 304 costs almost nothing. Refetched whenever rates refresh. Null when
/// it has never loaded (no network on first run), which callers treat as "no
/// server wraps yet" and fall back to the stories built on the phone.
final wrapFeedProvider = FutureProvider<List<ServerWrap>?>((ref) async {
  ref.watch(ratesProvider);
  final box = Hive.box('settings');
  const bodyKey = 'wraps_feed_body';
  const tagKey = 'wraps_feed_etag';
  String? body = box.get(bodyKey) as String?;
  // Revalidate only when there is a kept copy to fall back on after a 304.
  final etag = body == null ? null : box.get(tagKey) as String?;
  try {
    final res = await http
        .get(Uri.parse(Config.wrapsUrl), headers: {'If-None-Match': ?etag})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      body = res.body;
      await box.put(bodyKey, body);
      final etag = res.headers['etag'];
      if (etag != null) await box.put(tagKey, etag);
    }
  } catch (_) {
    // Offline or slow: the kept copy, if any, stands.
  }
  if (body == null) return null;
  try {
    final json = jsonDecode(body) as Map;
    return [
      for (final w in (json['wraps'] as List? ?? const []))
        if (w is Map) ?ServerWrap.fromMap(w),
    ];
  } catch (_) {
    return null;
  }
});

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The latest published week, while it is still the current one (it ended in
/// the last seven days). Null before the first Friday publish, or when the
/// feed is unavailable, and the phone's own weekly stories show instead.
final serverWeekProvider = Provider<ServerWrap?>((ref) {
  final feed = ref.watch(wrapFeedProvider).value;
  if (feed == null) return null;
  final today = _day(DateTime.now());
  for (final w in feed) {
    if (w.period != WrapPeriod.week || w.slides.isEmpty) continue;
    if (today.difference(_day(w.to)).inDays <= 6) return w;
    break;
  }
  return null;
});

/// Today's stories, when something moved today. Null on a quiet day.
final todayWrapProvider = Provider<ServerWrap?>((ref) {
  final feed = ref.watch(wrapFeedProvider).value;
  if (feed == null) return null;
  final today = _day(DateTime.now());
  for (final w in feed) {
    if (w.period == WrapPeriod.day &&
        _day(w.to) == today &&
        w.slides.isNotEmpty) {
      return w;
    }
  }
  return null;
});

/// A wrap in the Reports archive: the server's market stories, with the
/// user's own stories for the same week or month joined on from the phone.
class ArchiveWrap {
  const ArchiveWrap({
    required this.id,
    required this.period,
    required this.from,
    required this.to,
    required this.label,
    required this.slides,
    this.median,
    this.move,
    this.big = false,
  });

  final String id;
  final WrapPeriod period;
  final DateTime from;
  final DateTime to;
  final String label;
  final List<WrapSlide> slides;
  final double? median;
  final double? move;
  final bool big;
}

/// The archive by period, newest first. Weeks the phone kept from before the
/// server published any stay listed, so no history is lost in the switch.
final wrapArchiveByPeriodProvider =
    Provider<Map<WrapPeriod, List<ArchiveWrap>>>((ref) {
      final feed = ref.watch(wrapFeedProvider).value ?? const <ServerWrap>[];
      final local = ref.watch(wrapArchiveProvider).value ?? const <SavedWrap>[];
      final mine = <String, List<WrapSlide>>{
        for (final s in local)
          s.id: [
            for (final x in s.slides)
              if (x.personal) x,
          ],
      };
      final out = {for (final p in WrapPeriod.values) p: <ArchiveWrap>[]};
      final seenWeeks = <String>{};
      final seenMonths = <String>{};

      for (final w in feed) {
        final key = switch (w.period) {
          WrapPeriod.week => WrapArchive.weekId(w.to),
          WrapPeriod.month => 'm-${w.to.year}-${w.to.month}',
          _ => null,
        };
        if (w.period == WrapPeriod.week && key != null) seenWeeks.add(key);
        if (w.period == WrapPeriod.month && key != null) seenMonths.add(key);
        out[w.period]!.add(
          ArchiveWrap(
            id: w.id,
            period: w.period,
            from: w.from,
            to: w.to,
            label: w.label,
            slides: [...w.slides, ...?(key == null ? null : mine[key])],
            median: w.median,
            move: w.move,
            big: w.big,
          ),
        );
      }

      for (final s in local) {
        final period = s.monthly ? WrapPeriod.month : WrapPeriod.week;
        if ((s.monthly ? seenMonths : seenWeeks).contains(s.id)) continue;
        out[period]!.add(
          ArchiveWrap(
            id: s.id,
            period: period,
            from: s.from,
            to: s.to,
            label: '',
            slides: s.slides,
          ),
        );
      }
      for (final list in out.values) {
        list.sort((a, b) => b.to.compareTo(a.to));
      }
      return out;
    });

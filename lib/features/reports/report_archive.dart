import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../wrap/wrap_engine.dart';

/// A wrap kept on the phone after its week or month ends.
class SavedWrap {
  const SavedWrap({
    required this.id,
    required this.monthly,
    required this.from,
    required this.to,
    required this.slides,
  });

  /// `w-2026-10-12` (Monday of the week) or `m-2026-09`.
  final String id;
  final bool monthly;
  final DateTime from;
  final DateTime to;
  final List<WrapSlide> slides;

  Map<String, dynamic> toMap() => {
    'id': id,
    'monthly': monthly,
    'from': from.toIso8601String(),
    'to': to.toIso8601String(),
    'slides': [for (final s in slides) s.toMap()],
  };

  static SavedWrap fromMap(Map m) => SavedWrap(
    id: m['id'] as String,
    monthly: m['monthly'] as bool,
    from: DateTime.parse(m['from'] as String),
    to: DateTime.parse(m['to'] as String),
    slides: [
      for (final s in (m['slides'] as List)) WrapSlide.fromMap(s as Map),
    ],
  );
}

/// Every wrap the user has had, newest first. Saved the first time a wrap is
/// shown each week or month, in its own Hive box, opened on first use. Like
/// statements, it never leaves the phone.
class WrapArchive extends AsyncNotifier<List<SavedWrap>> {
  static const _boxName = 'wraps';

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  @override
  Future<List<SavedWrap>> build() async {
    final box = await _box();
    final out = <SavedWrap>[];
    for (final v in box.values) {
      try {
        out.add(SavedWrap.fromMap(jsonDecode(v as String) as Map));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.to.compareTo(a.to));
    return out;
  }

  static String weekId(DateTime d) {
    final monday = DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: d.weekday - 1));
    return 'w-${monday.year}-${monday.month}-${monday.day}';
  }

  /// Stores [wrap] for its week, replacing an earlier copy from the same week
  /// so the archive holds the week's final state.
  Future<void> saveWeek(WeeklyWrap wrap) async {
    if (wrap.all.isEmpty) return;
    final box = await _box();
    final s = SavedWrap(
      id: weekId(wrap.to),
      monthly: false,
      from: wrap.from,
      to: wrap.to,
      slides: wrap.all,
    );
    await box.put(s.id, jsonEncode(s.toMap()));
    ref.invalidateSelf();
  }

  Future<void> saveMonth(MonthWrap wrap) async {
    if (wrap.slides.isEmpty) return;
    final box = await _box();
    final s = SavedWrap(
      id: 'm-${wrap.from.year}-${wrap.from.month}',
      monthly: true,
      from: wrap.from,
      to: wrap.to,
      slides: wrap.slides,
    );
    if (box.containsKey(s.id)) return;
    await box.put(s.id, jsonEncode(s.toMap()));
    ref.invalidateSelf();
  }
}

final wrapArchiveProvider = AsyncNotifierProvider<WrapArchive, List<SavedWrap>>(
  WrapArchive.new,
);

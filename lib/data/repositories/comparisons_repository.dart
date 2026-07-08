import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/saved_comparison.dart';

/// Saved comparisons persisted as a JSON list under one key in the existing
/// `settings` box  no new Hive box to open in main(), consistent with the
/// rest of the app's storage. (Isar was avoided project-wide for codegen
/// fragility; this keeps parity.)
class ComparisonsRepository {
  final Box box;
  ComparisonsRepository(this.box);

  static const _key = 'saved_comparisons';

  List<SavedComparison> all() {
    final raw = box.get(_key) as String?;
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List;
    return list
        .map(
          (e) => SavedComparison.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> write(List<SavedComparison> items) =>
      box.put(_key, jsonEncode(items.map((e) => e.toMap()).toList()));
}

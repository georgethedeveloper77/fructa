/// A benchmark figure published in the snapshot config (inflation, CBR, T-bill).
class Benchmark {
  const Benchmark(this.rate, {this.asOf, this.source});
  final double rate;
  final String? asOf;
  final String? source;
}

/// Admin-editable key/value config, published inside the snapshot (`config`).
/// Every getter takes a baked-in fallback so the app renders correctly with
/// an old snapshot, an empty table, or a bad value  remote config can only
/// override copy/flags/benchmarks, never break the UI.
class RemoteConfig {
  const RemoteConfig(this._values);
  final Map<String, dynamic> _values;

  static const empty = RemoteConfig({});

  String string(String key, String fallback) {
    final v = _values[key];
    return v is String && v.isNotEmpty ? v : fallback;
  }

  bool flag(String key, bool fallback) {
    final v = _values[key];
    return v is bool ? v : fallback;
  }

  double number(String key, double fallback) {
    final v = _values[key];
    return v is num ? v.toDouble() : fallback;
  }

  /// JSON array of strings (e.g. `search.suggestions`). Non-string entries
  /// are dropped; anything malformed falls back whole.
  List<String> stringList(String key, List<String> fallback) {
    final v = _values[key];
    if (v is! List) return fallback;
    final out = v.whereType<String>().where((s) => s.isNotEmpty).toList();
    return out.isEmpty ? fallback : out;
  }

  // ── Benchmarks ──────────────────────────────────────────────────────────
  // Stored as objects: {"rate":6.7,"as_of":"2026-05-31","source":"KNBS"}.

  /// Full benchmark object (rate + as_of + source), or null if unset/malformed.
  Benchmark? benchmark(String key) {
    final v = _values[key];
    if (v is Map && v['rate'] is num) {
      return Benchmark(
        (v['rate'] as num).toDouble(),
        asOf: v['as_of'] as String?,
        source: v['source'] as String?,
      );
    }
    return null;
  }

  /// Just the rate, with a baked fallback so the triad always computes.
  double benchmarkRate(String key, double fallback) =>
      benchmark(key)?.rate ?? fallback;

  // Convenience  fallbacks are the live figures at build time (Jun 2026).
  double get inflationPct => benchmarkRate('benchmark.inflation', 6.7);
  double get cbrPct => benchmarkRate('benchmark.cbr', 8.75);
  double get tbill91Pct => benchmarkRate('benchmark.tbill_91', 8.71);
  double get tbill182Pct => benchmarkRate('benchmark.tbill_182', 8.60);
  double get tbill364Pct => benchmarkRate('benchmark.tbill_364', 8.87);
  double get whtPct => benchmarkRate('benchmark.wht_pct', 15);
}

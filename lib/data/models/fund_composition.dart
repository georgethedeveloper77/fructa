import 'package:flutter/material.dart';

/// The 8 CMA CIS asset classes (Q report section 2.7 / Table 18), in the
/// report's column order. Values are absolute KES.
enum AssetClass {
  cash,
  fixedDeposits,
  listed,
  gok,
  unlisted,
  otherCis,
  offshore,
  alternative,
}

extension AssetClassX on AssetClass {
  /// JSON key  matches `funds.composition` jsonb and the snapshot payload.
  String get key => switch (this) {
    AssetClass.cash => 'cash',
    AssetClass.fixedDeposits => 'fixed_deposits',
    AssetClass.listed => 'listed',
    AssetClass.gok => 'gok',
    AssetClass.unlisted => 'unlisted',
    AssetClass.otherCis => 'other_cis',
    AssetClass.offshore => 'offshore',
    AssetClass.alternative => 'alternative',
  };

  String get label => switch (this) {
    AssetClass.cash => 'Cash & demand deposits',
    AssetClass.fixedDeposits => 'Fixed deposits',
    AssetClass.listed => 'Listed securities',
    AssetClass.gok => 'Government securities',
    AssetClass.unlisted => 'Unlisted securities',
    AssetClass.otherCis => 'Other funds (CIS)',
    AssetClass.offshore => 'Offshore',
    AssetClass.alternative => 'Alternative',
  };

  /// Data colours (not theme tokens  asset classes are data, like brand
  /// colours). Drawn from the v5 family so nothing looks foreign.
  Color get color => switch (this) {
    AssetClass.gok => const Color(0xFF4E8FE8), // sky  sovereign paper
    AssetClass.fixedDeposits => const Color(0xFF2FB5A0), // emerald
    AssetClass.cash => const Color(0xFF3DDC97), // up-green
    AssetClass.listed => const Color(0xFF9A8BF3), // iris
    AssetClass.unlisted => const Color(0xFFF0B542), // amber
    AssetClass.offshore => const Color(0xFFE7784C), // ember
    AssetClass.otherCis => const Color(0xFF8A92A3), // muted
    AssetClass.alternative => const Color(0xFF555D6B), // faint
  };
}

/// One fund's holdings breakdown, absolute KES per class, with provenance.
/// Parsed defensively  a missing/empty jsonb yields `null` upstream and the
/// Company "What the fund holds" section stays hidden (no fabricated splits).
class FundComposition {
  const FundComposition({
    required this.kesByClass,
    this.aumKes,
    this.asOf,
    this.sourceUrl,
  });

  final Map<AssetClass, double> kesByClass;
  final double? aumKes;
  final String? asOf; // YYYY-MM-DD (CMA quarter end)
  final String? sourceUrl;

  double get total {
    final s = kesByClass.values.fold<double>(0, (a, b) => a + b);
    return s > 0 ? s : (aumKes ?? 0);
  }

  bool get isEmpty => kesByClass.values.every((v) => v <= 0);

  /// Share of [c] as a 0–100 percentage of the class sum.
  double pct(AssetClass c) {
    final t = total;
    return t <= 0 ? 0 : (kesByClass[c] ?? 0) / t * 100;
  }

  /// Non-zero classes, largest first  feed for AllocationBar/Legend.
  List<MapEntry<AssetClass, double>> get sorted =>
      (kesByClass.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value)));

  /// "KES 49.2B" / "KES 358.0M" / "KES 206,795"  legend-friendly.
  static String kesShort(num v) {
    final a = v.abs();
    String s;
    if (a >= 1e9) {
      s = '${(v / 1e9).toStringAsFixed(1)}B';
    } else if (a >= 1e6) {
      s = '${(v / 1e6).toStringAsFixed(1)}M';
    } else if (a >= 1e3) {
      s = '${(v / 1e3).toStringAsFixed(0)}K';
    } else {
      s = v.toStringAsFixed(0);
    }
    return 'KES $s';
  }

  /// Accepts the class map either flat (`{"gok": 1, ...}`) or nested under
  /// `classes`/`comp`  the snapshot emits flat, `cma_imports` staged rows
  /// may nest. Extra keys are ignored; absent classes read as 0.
  factory FundComposition.fromJson(Map<String, dynamic> j) {
    final raw = (j['classes'] ?? j['comp'] ?? j) as Map;
    final m = <AssetClass, double>{};
    for (final c in AssetClass.values) {
      final v = raw[c.key];
      if (v is num) m[c] = v.toDouble();
    }
    return FundComposition(
      kesByClass: m,
      aumKes: (j['aum_kes'] as num?)?.toDouble(),
      asOf: j['as_of'] as String?,
      sourceUrl: j['source_url'] as String?,
    );
  }
}

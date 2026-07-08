import 'package:flutter/material.dart';

import '../theme.dart';

/// Chart windows. Reused by the Company/Portfolio/Compare charts so the
/// selected range maps to a fixed trailing window when slicing history.
enum ChartRange { w1, m1, m3, m6, y1 }

extension ChartRangeX on ChartRange {
  String get label => switch (this) {
    ChartRange.w1 => '1W',
    ChartRange.m1 => '1M',
    ChartRange.m3 => '3M',
    ChartRange.m6 => '6M',
    ChartRange.y1 => '1Y',
  };

  /// Trailing window in days for slicing a history series.
  int get days => switch (this) {
    ChartRange.w1 => 7,
    ChartRange.m1 => 30,
    ChartRange.m3 => 90,
    ChartRange.m6 => 180,
    ChartRange.y1 => 365,
  };
}

/// v5 `.rangebar`  1W·1M·3M·6M·1Y. Selected segment gets an `s2` fill.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.ranges = ChartRange.values,
  });

  final ChartRange value;
  final ValueChanged<ChartRange> onChanged;
  final List<ChartRange> ranges;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          for (final r in ranges) ...[
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: r == value ? c.s2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    r.label,
                    style: TextStyle(
                      color: r == value ? c.text : c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (r != ranges.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

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

/// v5 `.rangebar`: 1W 1M 3M 6M 1Y. Selected segment gets an `s2` fill.

/// A segment styled like the fixed windows, for a range outside [ChartRange].
/// [locked] shows a padlock beside the label (a Pro window for a free user).
class RangeBarPill extends StatelessWidget {
  const RangeBarPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected ? c.text : c.faint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.s2 : c.s2.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontFamily: fructaFonts.mono,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 3),
              Icon(Icons.lock_outline_rounded, size: 11, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

///
/// [value] may be null when the [extra] segment is the active one. [extra]
/// sits after the fixed windows (the rate chart puts its Pro "All" pill there),
/// so a window outside [ChartRange] needs no new enum value and every other
/// chart that uses this bar is unaffected.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.ranges = ChartRange.values,
    this.extra,
  });

  final ChartRange? value;
  final ValueChanged<ChartRange> onChanged;
  final List<ChartRange> ranges;
  final Widget? extra;

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
                    color: r == value ? c.s2 : c.s2.withValues(alpha: 0),
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
            if (r != ranges.last || extra != null) const SizedBox(width: 4),
          ],
          if (extra != null) Expanded(child: extra!),
        ],
      ),
    );
  }
}

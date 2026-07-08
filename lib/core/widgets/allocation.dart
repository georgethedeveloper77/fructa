import 'package:flutter/material.dart';

import '../theme.dart';

/// One allocation slice, shared by [AllocationBar] (reads [weight] + [color])
/// and [Legend] (reads [color] + [label] + [valueText]).
class AllocSlice {
  const AllocSlice({
    required this.label,
    required this.color,
    required this.weight,
    required this.valueText,
  });

  final String label;
  final Color color;

  /// Relative size for the bar (any unit; normalised across the set).
  final double weight;

  /// What the legend shows on the right, e.g. "60%".
  final String valueText;
}

/// v5 `.compbar`  a 10px stacked bar, r6, with a 20px side margin.
class AllocationBar extends StatelessWidget {
  const AllocationBar(
    this.slices, {
    super.key,
    this.margin = const EdgeInsets.fromLTRB(20, 10, 20, 4),
  });

  final List<AllocSlice> slices;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, x) => s + x.weight);
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Row(
            children: [
              for (final s in slices)
                Expanded(
                  flex: total <= 0
                      ? 1
                      : (s.weight / total * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: s.color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// v5 `.leg`  colour dot + label + mono value, hairline-separated rows.
class Legend extends StatelessWidget {
  const Legend(this.slices, {super.key});

  final List<AllocSlice> slices;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < slices.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: i == slices.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: slices[i].color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      slices[i].label,
                      style: TextStyle(color: c.muted, fontSize: 12.5),
                    ),
                  ),
                  Text(
                    slices[i].valueText,
                    style: TextStyle(
                      color: c.text,
                      fontFamily: fructaFonts.mono,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund.dart';

/// The class picker for a fund sold in several classes.
///
/// Etica Special Wealth is one product, three rows: A locks 6 months at a 2.25%
/// fee for 13.38%, B locks 9 at 2.00% for 13.55%, C locks 12 at 1.75% for
/// 13.72%. Without this the app shows three near-identical funds in a list and
/// makes the reader work out that they are the same thing.
///
/// EACH CHIP CARRIES ITS LOCK-IN, and that is the design decision here rather
/// than a decoration. A bare A / B / C segmented control would present three
/// options as if the only difference were a letter, and the letter with the
/// highest yield would look like the obvious pick. It is the highest yield
/// BECAUSE it holds the money longest. Printing the lock-in on the chip means
/// the trade is visible at the moment of choosing rather than buried in the
/// terms further down the page.
class ClassSelector extends StatelessWidget {
  const ClassSelector({
    super.key,
    required this.siblings,
    required this.selectedId,
    required this.onSelect,
    this.tint,
  });

  final List<Fund> siblings;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (siblings.length < 2) return const SizedBox.shrink();
    final c = context.c;
    final colour = tint ?? c.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE FUND, ${siblings.length} CLASSES',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 9.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < siblings.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ClassChip(
                    fund: siblings[i],
                    selected: siblings[i].id == selectedId,
                    colour: colour,
                    onTap: () => onSelect(siblings[i].id),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Longer lock-in, lower fee, higher yield. The classes differ in what they ask of you, not in what they invest in.',
            style: TextStyle(color: c.faint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({
    required this.fund,
    required this.selected,
    required this.colour,
    required this.onTap,
  });

  final Fund fund;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final months = fund.lockInMonths ?? 0;
    final lock = months <= 0 ? 'No lock' : '${months}mo lock';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colour.withValues(alpha: 0.12) : c.s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colour.withValues(alpha: 0.45) : c.line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fund.classLabel ?? fund.name,
              style: TextStyle(
                color: selected ? colour : c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              lock,
              style: TextStyle(
                color: selected ? c.muted : c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 9.5,
              ),
            ),
            if (fund.mgmtFee != null) ...[
              const SizedBox(height: 1),
              Text(
                '${fund.mgmtFee!.toStringAsFixed(2)}% fee',
                style: TextStyle(
                  color: selected ? c.muted : c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 9.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

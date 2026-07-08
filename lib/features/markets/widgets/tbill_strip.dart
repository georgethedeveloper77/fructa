import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund.dart';

/// Flat treasury-bill strip (v5 `.tbrow`): three cells with left-border
/// dividers, NO card. Each cell = tenor label · mono rate · sub. The
/// highest-yield cell is tinted gold. Hidden when no bills are present.
class TbillStrip extends StatelessWidget {
  const TbillStrip(this.bills, {super.key, required this.onTap});

  final List<Fund> bills;
  final void Function(Fund) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (bills.isEmpty) return const SizedBox.shrink();
    final show = bills.take(3).toList();
    // top yield gets the gold accent (v5: 364-day cleared)
    double topRate = -1;
    for (final f in show) {
      final r = f.currentRate ?? -1;
      if (r > topRate) topRate = r;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < show.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.only(right: 13),
                color: c.line,
              ),
            Expanded(
              child: _Cell(
                show[i],
                isTop: (show[i].currentRate ?? -1) == topRate,
                onTap: () => onTap(show[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.fund, {required this.isTop, required this.onTap});
  final Fund fund;
  final bool isTop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tenor =
        RegExp(
          r'(\d+)\s*-?\s*day',
          caseSensitive: false,
        ).firstMatch(fund.name)?.group(0) ??
        fund.name;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tenor.toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            fund.currentRate != null
                ? '${fund.currentRate!.toStringAsFixed(2)}%'
                : '\u2014',
            style: TextStyle(
              color: isTop ? c.accent : c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 19,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'last auction',
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              fontFamily: fructaFonts.mono,
            ),
          ),
        ],
      ),
    );
  }
}

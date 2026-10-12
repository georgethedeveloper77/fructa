import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Gold bottom bar for compare mode: selection count, Compare (≥2), and exit.
class CompareBar extends StatelessWidget {
  const CompareBar({
    super.key,
    required this.count,
    required this.onCompare,
    required this.onExit,
  });

  final int count;
  final VoidCallback onCompare;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final canCompare = count >= 2;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: c.accent,
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onExit,
            icon: Icon(Icons.close, color: c.onAccent),
          ),
          Expanded(
            child: Text(
              t('compare.selectedCount', {'n': '$count'}),
              style: TextStyle(
                color: c.onAccent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: canCompare ? onCompare : null,
            style: FilledButton.styleFrom(
              backgroundColor: c.onAccent,
              foregroundColor: c.accent,
              disabledBackgroundColor: c.onAccent.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              canCompare ? t('markets.sort.compare') : t('compare.min2'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

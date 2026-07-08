import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Sort pills + the gold ⇄ Compare pill. v5 `.pill`: fully-round (r22), 42px
/// tall. Selected inverts to the **text** colour (white-on-dark), not the
/// accent  the accent is reserved for the Compare pill.
class SortPills extends ConsumerWidget {
  const SortPills({super.key, this.onCompare});

  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(marketSortProvider);

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final s in MarketSort.values) ...[
            _Pill(
              label: t('markets.sort.${s.name}'),
              selected: s == sort,
              onTap: () => ref.read(marketSortProvider.notifier).state = s,
            ),
            const SizedBox(width: 8),
          ],
          _ComparePill(onTap: onCompare),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: selected ? c.text : c.s1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? c.text : c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c.bg : c.muted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ComparePill extends StatelessWidget {
  const _ComparePill({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: c.accentSoft,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.compare_arrows, size: 16, color: c.accent),
              const SizedBox(width: 5),
              Text(
                t('markets.sort.compare'),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

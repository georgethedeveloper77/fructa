import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Sort pills for the SACCO tab, plus the open-bond filter.
///
/// The filter sits in the same row as the sorts, and first, because on this tab
/// it changes the list more than any sort does. Whether you can JOIN a society
/// is a harder gate than what it pays: a closed-bond SACCO at 13% is not a
/// better option than an open one at 11%, it is not an option at all.
///
/// There is no dividend sort, and that is deliberate rather than missing. See
/// the note above SaccoSort in markets_controller.dart: the tile's headline is
/// the deposit rate, and a list ordered by a number that is not the headline
/// invites the reader to take the headline as the sort key.
class SaccoSortPills extends ConsumerWidget {
  const SaccoSortPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final sort = ref.watch(saccoSortProvider);
    final openOnly = ref.watch(saccoOpenOnlyProvider);

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          GestureDetector(
            onTap: () =>
                ref.read(saccoOpenOnlyProvider.notifier).state = !openOnly,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: openOnly ? c.upSoft : c.s1,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: openOnly ? c.up.withValues(alpha: 0.4) : c.line,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    openOnly
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                    size: 15,
                    color: openOnly ? c.up : c.muted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'I can join',
                    style: TextStyle(
                      color: openOnly ? c.up : c.muted,
                      fontSize: 13,
                      fontWeight: openOnly
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: c.line, margin: const EdgeInsets.symmetric(vertical: 11)),
          const SizedBox(width: 8),
          for (final s in SaccoSort.values) ...[
            _Pill(
              label: s.label,
              selected: s == sort,
              onTap: () => ref.read(saccoSortProvider.notifier).state = s,
            ),
            const SizedBox(width: 8),
          ],
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

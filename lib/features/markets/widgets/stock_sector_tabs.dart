import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fructa/data/snapshot_providers.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Sector sub-filter under the Stocks tab. The exact sibling of
/// [MoneyCurrencyTabs] under Money Market: 38px row, small rounded chips, null
/// means All. Self-hides when there is one sector or fewer, because a filter
/// with a single option is just noise.
class StockSectorTabs extends ConsumerWidget {
  const StockSectorTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final sectors = ref.watch(stockSectorsProvider);
    final selected = ref.watch(stockSectorProvider);
    if (sectors.length < 2) return const SizedBox.shrink();

    // null leads: the All chip.
    final options = <String?>[null, ...sectors];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = options[i];
          final on = s == selected;
          return GestureDetector(
            onTap: () => ref.read(stockSectorProvider.notifier).state = s,
            behavior: HitTestBehavior.opaque,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: on ? c.accentSoft : c.s1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? c.accent : c.line),
              ),
              child: Text(
                s ?? t('stocks.sectorAll'),
                style: TextStyle(
                  color: on ? c.accent : c.muted,
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Sort pills for the Stocks tab. Same 42px row as [SortPills] on the fund
/// stream, but a different set, because stocks sort on different things.
///
/// There is no Compare pill here. Compare is built on Fund and ranks yields;
/// a stock has no yield to rank. Offering it would be a broken promise.
class StockSortPills extends ConsumerWidget {
  const StockSortPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final active = ref.watch(effectiveStockSortProvider);
    final pricesLive = ref.watch(stockPricesLiveProvider);

    final options = <StockSort>[
      // Ranking by day move needs a licensed price. No price, no pill.
      if (pricesLive) StockSort.movers,
      StockSort.dividend,
      StockSort.alpha,
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = options[i];
          final on = s == active;
          return GestureDetector(
            onTap: () => ref.read(stockSortProvider.notifier).state = s,
            behavior: HitTestBehavior.opaque,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: on ? c.accent : c.s1,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? c.accent : c.line),
              ),
              child: Text(
                s.label,
                style: TextStyle(
                  color: on ? c.onAccent : c.muted,
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

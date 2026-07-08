import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Category tabs  v5 `.cattab`: rounded-rect (r14, not fully-round), 46px
/// touch target. Selected inverts to the text colour (near-white on dark /
/// near-black on light), NOT the accent.
class CategoryTabs extends ConsumerWidget {
  const CategoryTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final selected = ref.watch(marketTabProvider);
    final tabs = ref.watch(visibleMarketTabsProvider);

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final tab = tabs[i];
          final on = tab == selected;
          return GestureDetector(
            onTap: () {
              ref.read(marketTabProvider.notifier).state = tab;
              // leaving Money Market clears its currency sub-filter
              if (tab != MarketTab.moneyMarket) {
                ref.read(marketMoneyCcyProvider.notifier).state = null;
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: on ? c.text : c.s1,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? c.text : c.line),
              ),
              child: Text(
                tab.label,
                style: TextStyle(
                  color: on ? c.bg : c.muted,
                  fontSize: 14,
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

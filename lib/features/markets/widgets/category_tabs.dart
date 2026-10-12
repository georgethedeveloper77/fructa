import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Category tabs: underlined text on a hairline, 42px tall. The selected tab
/// is bold text with an accent rule; the rest are muted. Lighter than boxed
/// pills, so the list below starts higher and reads first.
class CategoryTabs extends ConsumerWidget {
  const CategoryTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final selected = ref.watch(marketTabProvider);
    final tabs = ref.watch(visibleMarketTabsProvider);

    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
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
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: on ? c.accent : c.accent.withValues(alpha: 0),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tab.label,
                style: TextStyle(
                  color: on ? c.text : c.muted,
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

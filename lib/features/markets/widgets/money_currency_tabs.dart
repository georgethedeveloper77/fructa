import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../markets_controller.dart';

/// Second-tier currency filter. Options
/// (All, KES, USD and so on) are derived from the live data in the CURRENT tab,
/// so they track whatever currencies admin publishes and appear under any
/// category sold in more than one. Special funds are sold in KES and USD exactly
/// as money market funds are, and while this was nailed to one tab the dollar
/// version had no chip.
///
/// Self-gating: fewer than two currencies and it renders nothing, so a caller
/// does not need to know which tabs qualify. If markets_page still wraps this in
/// a `tab == MarketTab.moneyMarket` check, remove it: the widget decides now.
/// Rendered as a lighter, accent-tinted sub-row so it reads as a refinement of
/// the category above it, not a peer.
class MoneyCurrencyTabs extends ConsumerWidget {
  const MoneyCurrencyTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final ccys = ref.watch(tabCurrenciesProvider);
    final selected = ref.watch(marketMoneyCcyProvider);
    if (ccys.length < 2) return const SizedBox.shrink();

    final items = <String?>[null, ...ccys]; // null = All

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ccy = items[i];
          final on = ccy == selected;
          return GestureDetector(
            onTap: () =>
                ref.read(marketMoneyCcyProvider.notifier).state = ccy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: on ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: on ? c.accent.withValues(alpha: 0.4) : c.line),
              ),
              child: Text(
                ccy ?? 'All',
                style: TextStyle(
                  color: on ? c.accent : c.muted,
                  fontSize: 12.5,
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

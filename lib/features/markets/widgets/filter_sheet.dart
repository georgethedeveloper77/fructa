import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../markets_controller.dart';

/// One row under the category tabs: how many funds are showing, a single
/// filter button that summarises the active currency and sort, and Compare.
///
/// Replaces the stacked currency and sort pill rows. Both choices still exist;
/// they live one tap away in [showFundFilterSheet], so the list starts higher.
class FundFilterBar extends ConsumerWidget {
  const FundFilterBar({super.key, required this.label, this.onCompare});

  /// The count line, already worded by the caller.
  final String label;

  /// Enters compare mode. Null hides the button (already comparing).
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final ccy = ref.watch(marketMoneyCcyProvider);
    final sort = ref.watch(marketSortProvider);
    final hasCcy = ref.watch(tabCurrenciesProvider).length > 1;
    final summary = [
      if (hasCcy) ccy ?? t('markets.filter.allCcy'),
      t('markets.sort.${sort.name}'),
    ].join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 12.5),
            ),
          ),
          _BarButton(
            icon: Icons.tune_rounded,
            label: summary,
            onTap: () => showFundFilterSheet(context),
          ),
          if (onCompare != null) ...[
            const SizedBox(width: 6),
            _BarButton(
              icon: Icons.compare_arrows_rounded,
              label: t('markets.sort.compare'),
              onTap: onCompare!,
            ),
          ],
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.s1,
      shape: StadiumBorder(side: BorderSide(color: c.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.text),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: c.text,
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

/// Currency and sort for the fund list, in one sheet. Changes apply as they
/// are tapped, so the list behind updates live and "Done" only closes.
Future<void> showFundFilterSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _FilterSheet(),
);

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final ccys = ref.watch(tabCurrenciesProvider);
    final ccy = ref.watch(marketMoneyCcyProvider);
    final sort = ref.watch(marketSortProvider);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: c.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              t('markets.filter.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (ccys.length > 1) ...[
            heading(t('markets.filter.currency')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.s2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    for (final option in <String?>[null, ...ccys])
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              ref.read(marketMoneyCcyProvider.notifier).state =
                                  option,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 40),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: option == ccy
                                  ? c.text
                                  : c.s2.withValues(alpha: 0),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              option ?? t('markets.filter.allCcy'),
                              style: TextStyle(
                                color: option == ccy ? c.bg : c.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          heading(t('markets.filter.sort')),
          for (final s in MarketSort.values)
            InkWell(
              onTap: () => ref.read(marketSortProvider.notifier).state = s,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('markets.sort.${s.name}'),
                            style: TextStyle(color: c.text, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('markets.filter.hint.${s.name}'),
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      s == sort
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: s == sort ? c.accent : c.faint,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.text,
                  foregroundColor: c.bg,
                  minimumSize: const Size.fromHeight(50),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  t('common.done'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

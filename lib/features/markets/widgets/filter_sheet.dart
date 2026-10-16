import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/i18n.dart';
import '../../../core/motion/motion.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/rate_basis_toggle.dart';
import '../markets_controller.dart';

/// One row under the category tabs: the app-wide Gross | Net switch, how many
/// funds are showing, then filter and compare as icons. Currency and sort live
/// in [showFundFilterSheet]; the icon carries a dot while either is changed
/// from its default, so a filtered list never passes for the whole market.
///
/// The first time Markets opens on a tab with more than one currency, the
/// filter widens into KES and USD chips for five seconds, so the currency
/// filter is found without opening the sheet. It then folds back into the
/// icon and never repeats. Reduced motion skips it.
class FundFilterBar extends ConsumerStatefulWidget {
  const FundFilterBar({super.key, required this.label, this.onCompare});

  /// The count, already worded by the caller.
  final String label;

  /// Enters compare mode. Null hides the button (already comparing).
  final VoidCallback? onCompare;

  @override
  ConsumerState<FundFilterBar> createState() => _FundFilterBarState();
}

class _FundFilterBarState extends ConsumerState<FundFilterBar> {
  static const _seenKey = 'markets_ccy_reveal_seen';
  static const _hold = Duration(seconds: 5);

  bool _open = false;
  Timer? _show;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReveal());
  }

  void _maybeReveal() {
    if (!mounted) return;
    final box = Hive.box('settings');
    if (box.get(_seenKey, defaultValue: false) as bool) return;
    if (ref.read(tabCurrenciesProvider).length < 2) return;
    box.put(_seenKey, true);
    if (reduceMotion(context)) return;
    _show = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _open = true);
    });
    _hide = Timer(const Duration(milliseconds: 500) + _hold, () {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  void dispose() {
    _show?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = widget.label;
    final onCompare = widget.onCompare;
    final ccys = ref.watch(tabCurrenciesProvider);
    final ccy = ref.watch(marketMoneyCcyProvider);
    final filtered =
        ref.watch(marketMoneyCcyProvider) != null ||
        ref.watch(marketSortProvider) != MarketSort.highestYield;
    return Container(
      height: 40,
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: Row(
        children: [
          const FittedBox(fit: BoxFit.scaleDown, child: RateBasisToggle()),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(color: c.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          _RevealFilter(
            open: _open && ccys.length > 1,
            currencies: ccys,
            selected: ccy,
            dot: filtered,
            onPick: (k) => ref.read(marketMoneyCcyProvider.notifier).state =
                ccy == k ? null : k,
            onTap: () => showFundFilterSheet(context),
          ),
          if (onCompare != null) ...[
            const SizedBox(width: 6),
            _IconAction(
              icon: Icons.compare_arrows_rounded,
              tooltip: t('markets.sort.compare'),
              onTap: onCompare,
            ),
          ],
        ],
      ),
    );
  }
}

/// The filter button, which can widen to show the currency chips beside its
/// icon. Closed, it is the same 40 by 40 button as compare.
class _RevealFilter extends StatelessWidget {
  const _RevealFilter({
    required this.open,
    required this.currencies,
    required this.selected,
    required this.dot,
    required this.onPick,
    required this.onTap,
  });

  final bool open;
  final List<String> currencies;
  final String? selected;
  final bool dot;
  final ValueChanged<String> onPick;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calm = reduceMotion(context);
    return AnimatedContainer(
      duration: Duration(milliseconds: calm ? 0 : 300),
      height: 40,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? c.accent : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: Duration(milliseconds: calm ? 0 : 420),
            curve: Curves.easeOutCubic,
            child: !open
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final k in currencies.take(2)) ...[
                          Material(
                            color: selected == k ? c.text : c.s2,
                            borderRadius: BorderRadius.circular(9),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(9),
                              onTap: () => onPick(k),
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  k,
                                  style: TextStyle(
                                    color: selected == k ? c.bg : c.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
          ),
          Tooltip(
            message: t('markets.filter.title'),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: c.text),
                    if (dot)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [Icon(icon, size: 18, color: c.text)],
            ),
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

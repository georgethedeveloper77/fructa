import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/main_scaffold.dart';
import '../../core/i18n.dart';
import '../../core/motion/motion.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// What the whole book earns in a day, in basis points of its value.
///
/// Worked out from each holding's current rate (net where tax is withheld)
/// weighted by its value, so it is meaningful on the day a holding is added,
/// unlike a since-added change that reads +0.00% until interest accrues.
/// Basis points never reveal an amount, keeping Today free of balances.
final bookDailyBpsProvider = Provider<double?>((ref) {
  final holdings = ref.watch(holdingsProvider);
  if (holdings.isEmpty) return null;
  final wht = ref.watch(remoteConfigProvider).whtPct;
  final fx = ref.watch(usdKesProvider);
  var weight = 0.0;
  var rateSum = 0.0;
  for (final h in holdings) {
    final s = ref.watch(
      holdingSubjectProvider((id: h.fundId, sacco: h.isSacco)),
    );
    final r = s?.ratePercent;
    if (r == null || h.balance <= 0) continue;
    final net = s!.taxFree ? r : r * (1 - wht / 100);
    // Weight in KES so a USD holding counts at its shilling size.
    final w = h.currency == 'USD' ? h.balance * (fx ?? 0) : h.balance;
    weight += w;
    rateSum += net * w;
  }
  if (weight <= 0) return null;
  // percent a year → basis points a day.
  return rateSum / weight / 365 * 100;
});

/// The book's day as one small pill docked above the tab bar: what the whole
/// portfolio earns today, in basis points, never an amount. Tapping opens
/// Portfolio. It slides away while the page scrolls, so it never sits on top
/// of a card the user is reading.
class PortfolioPill extends ConsumerWidget {
  const PortfolioPill({super.key, required this.hidden});

  /// True while Today is scrolling.
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bps = ref.watch(bookDailyBpsProvider);
    if (bps == null) return const SizedBox.shrink();
    final c = context.c;
    final value = t('today.pill.bps', {
      'v': '${bps >= 0 ? '+' : ''}${bps.toStringAsFixed(1)}',
    });
    final tone = bps >= 0 ? c.up : c.down;
    final calm = reduceMotion(context);

    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedSlide(
        offset: hidden ? const Offset(0, 1.6) : Offset.zero,
        duration: Duration(milliseconds: calm ? 0 : 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: Duration(milliseconds: calm ? 0 : 180),
          child: Center(
            child: Semantics(
              button: true,
              label: t('today.bubble.a11y', {'v': value}),
              excludeSemantics: true,
              child: Material(
                color: c.s1,
                shape: StadiumBorder(side: BorderSide(color: c.line)),
                elevation: 0,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => ref.read(selectedTabProvider.notifier).state =
                      AppTab.portfolio,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      shadows: [
                        BoxShadow(
                          color: c.text.withValues(alpha: c.isDark ? 0 : 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tone,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          t('today.pill.label'),
                          style: TextStyle(color: c.muted, fontSize: 13),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          value,
                          style: fructaFonts.numeric(
                            color: tone,
                            size: 13,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

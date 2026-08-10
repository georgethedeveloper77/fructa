import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/quarter_stat.dart';
import '../../../data/models/remote_config.dart';
import '../../../data/snapshot_providers.dart';

/// The NSE at a quarter end: NASI, NSE 20, market capitalisation and the bond
/// index, from the CMA quarterly bulletin via `market.nse`.
///
/// THIS BLOCK IS QUARTERLY AND THE ROWS BENEATH IT ARE NOT. The stock tiles
/// under this card carry end-of-day prices that moved this morning; NASI here
/// was struck on the last day of a quarter and will be five months old by the
/// time the next bulletin lands. That adjacency is the whole design risk, so
/// the period is stated three times over: a quarter chip in the head, the
/// tabular mono treatment that the app uses for stored figures, and a dated
/// source line at the foot. If it ever stops reading as a separate thing, the
/// fix is to collapse this behind a tap rather than soften the labelling.
///
/// Listed-counter count is deliberately NOT shown. The bulletin counts 71
/// counters at 30 June 2026 including suspensions, REITs and ETFs, and the app
/// tracks the ones its price source returns. Printing both numbers one above
/// the other invites a reader to conclude the app is missing stocks when what
/// differs is what each side is counting.
class NseHeaderCard extends ConsumerWidget {
  const NseHeaderCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final nse = ref.watch(remoteConfigProvider).nse();
    if (nse == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _head(c, nse),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _IndexCell(
                    label: t('stocks.nse.nasi'),
                    value: groupedNumber(nse.nasi, 2),
                    deltaPct: nse.nasiQoqPct,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _IndexCell(
                    label: t('stocks.nse.nse20'),
                    value: groupedNumber(nse.nse20, 2),
                    deltaPct: nse.nse20QoqPct,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: c.line),
            const SizedBox(height: 13),
            _strip(c, nse),
            const SizedBox(height: 13),
            Container(height: 1, color: c.line),
            const SizedBox(height: 11),
            _sourceLine(c, nse),
          ],
        ),
      ),
    );
  }

  Widget _head(fructaColors c, NseSnapshot nse) {
    return Row(
      children: [
        Expanded(
          child: Text(
            t('stocks.nse.title'),
            style: TextStyle(
              color: c.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: c.s3,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            quarterTag(nse.asOf),
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _strip(fructaColors c, NseSnapshot nse) {
    Widget unit(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: c.faint, fontSize: 10)),
        ],
      ),
    );

    Widget rule() => Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: c.line,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        unit(_marketCap(nse.marketCapKesBn), t('stocks.nse.marketCap')),
        rule(),
        unit(groupedNumber(nse.bondIndex, 2), t('stocks.nse.bondIndex')),
        rule(),
        unit(
          '${groupedNumber(nse.foreignParticipationPct, 1)}%',
          t('stocks.nse.foreign'),
        ),
      ],
    );
  }

  Widget _sourceLine(fructaColors c, NseSnapshot nse) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.schedule, size: 12, color: c.faint),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            t('stocks.nse.asOf', {
              'source': ?nse.source,
              'date': prettyDate(nse.asOf),
            }),
            style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// One index: name, level, and the quarter move. The move is a QUARTER move,
/// never a day move, and it sits in a pill rather than beside the figure so it
/// cannot be mistaken for the day-change styling on the tiles below.
class _IndexCell extends StatelessWidget {
  const _IndexCell({
    required this.label,
    required this.value,
    required this.deltaPct,
  });

  final String label;
  final String value;
  final double? deltaPct;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = deltaPct;

    return Container(
      padding: const EdgeInsets.fromLTRB(11, 12, 11, 12),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (d != null) ...[const SizedBox(height: 7), DeltaPill(pct: d)],
        ],
      ),
    );
  }
}

/// Market cap arrives in BILLIONS of shillings, which is how the bulletin
/// prints it. 3761.74 -> "KES 3.76T".
String _marketCap(double bn) {
  if (bn >= 1000) return 'KES ${(bn / 1000).toStringAsFixed(2)}T';
  return 'KES ${bn.toStringAsFixed(0)}B';
}

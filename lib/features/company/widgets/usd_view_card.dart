import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n.dart';
import '../../../core/series_colors.dart';
import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/snapshot_providers.dart';
import '../../../engine/fx_engine.dart';

/// The same shilling return, counted in dollars.
///
/// This is the cheapest honest number in the currency feature: it needs no new
/// data, no stance, no horizon and no assumption about spreads. A KES fund that
/// paid 13.7 over a year in which the shilling gave up 6 paid about 7.3 to
/// somebody who counts in dollars, and the gap is the currency rather than
/// anything the manager did.
///
/// It sits at the foot of the fund page on purpose. It is context on a figure
/// the page has already made its case for, not a competing headline, and a
/// reader who does not think in dollars can scroll past it without ever having
/// been asked to.
///
/// Hides itself in every case where the number would be a guess: a fund that is
/// not KES denominated, a fund with neither a published return nor a yield, and
/// a snapshot whose FX history is too short to measure a year.
class UsdViewCard extends ConsumerWidget {
  const UsdViewCard(this.fund, {super.key});

  final Fund fund;

  /// A year of month ends, plus the point the year is measured from.
  static const _needed = 13;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fund.currency != 'KES') return const SizedBox.shrink();

    final series = ref.watch(fxSeriesProvider);
    if (series == null || series.mean.length < _needed) {
      return const SizedBox.shrink();
    }

    // A published trailing return where there is one, otherwise the yield a
    // money market fund is quoting today. The two are different claims and the
    // copy says which one is on screen: the first is what the fund DID, the
    // second is what a year at today's rate WOULD do.
    final realised = fund.return1y != null;
    final rate = fund.return1y ?? (fund.showsYield ? fund.currentRate : null);
    if (rate == null) return const SizedBox.shrink();

    final means = series.mean;
    final meanStart = means[means.length - _needed];
    final meanEnd = means.last;
    if (meanStart <= 0 || meanEnd <= 0) return const SizedBox.shrink();

    final inUsd =
        FxEngine.inUsd(
          kesReturn: rate / 100,
          meanStart: meanStart,
          meanEnd: meanEnd,
        ) *
        100;

    // Positive means the shilling bought fewer dollars at the end than at the
    // start, which is the direction that costs a dollar holder.
    final fxMove = (meanEnd / meanStart - 1) * 100;

    final c = context.c;
    final tint = seriesColor(2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.swap_horiz, size: 17, color: tint),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    t('fund.usd.title'),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Figure(
                  label: t('fund.usd.inKes'),
                  value: rate,
                  color: c.text,
                ),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: c.line,
                ),
                _Figure(
                  label: t('fund.usd.inUsd'),
                  value: inUsd,
                  color: inUsd >= 0 ? tint : c.down,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              t(realised ? 'fund.usd.note' : 'fund.usd.noteYield', {
                'kes': rate.toStringAsFixed(2),
                'usd': inUsd.toStringAsFixed(2),
                'move': fxMove.abs().toStringAsFixed(1),
              }),
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.faint,
              fontSize: 9.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontFamily: fructaFonts.mono,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

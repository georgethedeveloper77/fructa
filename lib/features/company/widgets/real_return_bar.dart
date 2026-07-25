import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';

/// The gross yield, carved up into the three things that happen to it.
///
/// A fund page already prints gross, net and real as three separate figures in
/// a row, and a reader takes them as a progression without ever being shown the
/// sizes. 13.74 gross against 4.67 real is a two thirds haircut, and nothing on
/// the page says so. This bar is that sentence as a shape.
///
/// The segments are differences of numbers the page already displays, so they
/// sum to the gross exactly rather than approximately:
///
///   tax        gross - net
///   inflation  net - real
///   kept       real
///
/// Deliberately presentational: no provider, no config read, no currency
/// opinion. The caller supplies the three figures for the fund's OWN currency,
/// which is the whole reason Fund.realRate takes an inflation argument rather
/// than reaching for the one CPI the app happens to hold. A dollar fund is not
/// deflated by Kenyan CPI, so the caller passes nothing and this never renders.
class RealReturnBar extends StatelessWidget {
  const RealReturnBar({
    super.key,
    required this.gross,
    required this.net,
    required this.real,
    required this.inflation,
    this.tint,
  });

  /// Headline yield, as a percentage.
  final double gross;

  /// After withholding, as a percentage.
  final double net;

  /// After withholding and inflation, as a percentage. Negative is a real
  /// outcome, not an error state, and it is the one this widget exists to make
  /// impossible to miss.
  final double real;

  /// The inflation rate used, as a percentage. Shown in the note so the figure
  /// is checkable rather than asserted.
  final double inflation;

  /// Colour of the kept segment. Defaults to the fund's own accent through
  /// `c.up`, since a positive real return is the good outcome.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final keep = tint ?? c.up;

    final tax = math.max(gross - net, 0.0);
    final infl = math.max(net - real, 0.0);
    final kept = real;

    // Two different bars, and which one you get is the finding.
    //
    // With a positive real return the bar IS the gross yield and the segments
    // divide it. With a negative one, tax and inflation together took more than
    // the fund earned, so they cannot fit inside it: the bar runs past a marker
    // set at the gross, and the overshoot is the shortfall.
    final consumed = tax + infl;
    final total = math.max(gross, consumed);
    if (total <= 0) return const SizedBox.shrink();

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t('fund.real.title'),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${real >= 0 ? '+' : ''}${real.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: real >= 0 ? keep : c.down,
                    fontFamily: fructaFonts.mono,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, cons) {
                // Flex, not pixel widths. The three segments sum to the total
                // by construction, and a Row of computed pixel widths that add
                // up to exactly the constraint overflows the moment floating
                // point rounds the wrong way.
                int flex(double pct) =>
                    math.max((pct / total * 10000).round(), 1);

                // Inflation is drawn LAST so that when it is the thing pushing
                // the bar past the gross marker, the overshoot is painted in
                // inflation's colour. That is what actually happened.
                return SizedBox(
                  height: 14,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Row(
                          children: [
                            if (kept > 0)
                              Expanded(
                                flex: flex(kept),
                                child: ColoredBox(color: keep),
                              ),
                            if (tax > 0)
                              Expanded(
                                flex: flex(tax),
                                child: ColoredBox(color: c.line2),
                              ),
                            if (infl > 0)
                              Expanded(
                                flex: flex(infl),
                                child: ColoredBox(
                                  color: c.muted.withValues(alpha: 0.55),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Where the fund's gross yield ran out. Only drawn when
                      // something is past it, because on a healthy fund the
                      // marker would sit on the bar's own right edge and read
                      // as a rendering artefact.
                      if (kept < 0)
                        Positioned(
                          left: (gross / total) * cons.maxWidth - 1,
                          top: -3,
                          bottom: -3,
                          child: Container(width: 2, color: c.text),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Key(
                  color: kept < 0 ? c.down : keep,
                  label: kept < 0
                      ? t('fund.real.shortfall')
                      : t('fund.real.kept'),
                  value: kept,
                ),
                _Key(color: c.line2, label: t('fund.real.tax'), value: tax),
                _Key(
                  color: c.muted.withValues(alpha: 0.55),
                  label: t('fund.real.inflation'),
                  value: infl,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              kept < 0
                  ? t('fund.real.noteBelow', {
                      'gross': gross.toStringAsFixed(2),
                      'infl': inflation.toStringAsFixed(1),
                    })
                  : t('fund.real.note', {
                      'gross': gross.toStringAsFixed(2),
                      'infl': inflation.toStringAsFixed(1),
                    }),
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(color: c.faint, fontSize: 11),
        ),
        const SizedBox(width: 6),
        Text(
          '${value.abs().toStringAsFixed(2)}%',
          style: TextStyle(
            color: c.text,
            fontFamily: fructaFonts.mono,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/snapshot_providers.dart';
import 'yield_curve.dart';

/// Detail for the government yield curve: the three tenors larger, the curve
/// shape read live from the 364-91 spread, benchmark context (inflation, CBK,
/// 91-day), and a plain explainer. Built entirely from the published
/// benchmarks, so nothing new is needed in the pipeline.
class MarketYieldCurvePage extends ConsumerWidget {
  const MarketYieldCurvePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final t91 = cfg.tbill91Pct;
    final t182 = cfg.tbill182Pct;
    final t364 = cfg.tbill364Pct;
    final asOf = cfg.benchmark('benchmark.tbill_91')?.asOf;
    final spread = t364 - t91;
    final (shape, blurb) = _shape(spread);
    final up = spread >= 0;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: c.text),
        title: Text(
          'Government yield curve',
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Row(
            children: [
              Text(
                'TREASURY BILLS \u00b7 LAST AUCTION',
                style: TextStyle(
                  color: c.faint,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontFamily: fructaFonts.mono,
                ),
              ),
              const Spacer(),
              if (asOf != null)
                Text(
                  asOf,
                  style: TextStyle(
                    color: c.faint,
                    fontSize: 10.5,
                    fontFamily: fructaFonts.mono,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const YieldCurveChart(height: 180),
          const SizedBox(height: 8),
          Row(
            children: [
              _Cell(label: '91-DAY', value: t91),
              _Cell(label: '182-DAY', value: t182),
              _Cell(label: '364-DAY', value: t364, accent: true),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.s2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Icon(
                  up ? Icons.trending_up : Icons.trending_down,
                  color: up ? c.up : c.down,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shape,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        blurb,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _Cell(label: 'INFLATION', value: cfg.inflationPct),
              _divider(c),
              _Cell(label: 'CBK RATE', value: cfg.cbrPct),
              _divider(c),
              _Cell(label: '91-DAY', value: t91, accent: true),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What the curve tells you',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cfg.string(
                    'yieldCurve.explainer',
                    'These are the rates the government pays to borrow for 3, 6, and 12 months. The 91-day bill is the risk-free rate every money market fund is measured against: a fund is only doing its job if it beats it. An upward curve is normal and means the market expects steady conditions.',
                  ),
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
                ),
                if (asOf != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Last auction $asOf \u00b7 source: CBK',
                    style: TextStyle(
                      color: c.faint,
                      fontSize: 10.5,
                      fontFamily: fructaFonts.mono,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ('shape name', 'plain blurb') read from the 364-91 spread. Flips
/// automatically, so an inverted or flat curve is never mislabeled.
(String, String) _shape(double spread) {
  if (spread > 0.1) {
    return (
      'Normal, upward curve',
      'Longer money earns more. The 364-day pays +${spread.toStringAsFixed(2)} pts over the 91-day.',
    );
  }
  if (spread < -0.1) {
    return (
      'Inverted curve',
      'Short money pays more than long. The 364-day is ${spread.toStringAsFixed(2)} pts under the 91-day, often a sign the market expects rates to fall.',
    );
  }
  return (
    'Flat curve',
    'Short and long tenors pay about the same. The market expects little change.',
  );
}

Widget _divider(fructaColors c) => Container(
  width: 1,
  height: 34,
  color: c.line,
  margin: const EdgeInsets.symmetric(horizontal: 12),
);

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.accent = false});

  final String label;
  final double value;
  final bool accent;

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
              fontFamily: fructaFonts.mono,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${value.toStringAsFixed(2)}%',
            style: TextStyle(
              color: accent ? c.accent : c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

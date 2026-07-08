import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/models/remote_config.dart';
import '../../../data/snapshot_providers.dart';

/// Benchmark context strip  the board's anchor. Inflation · CBR · 91-day
/// T-bill, read from remote config (config['benchmark.*']) with baked
/// fallbacks. Flat v5 `.tbrow` style: three cells, left-border dividers, no
/// card. The 91-day  the risk-free rate every fund must beat  is tinted gold.
class BenchmarkStrip extends ConsumerWidget {
  const BenchmarkStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);

    final items = <_Bench>[
      _Bench(
        'INFLATION',
        cfg.benchmark('benchmark.inflation'),
        6.7,
        'consumer prices',
      ),
      _Bench('CBR', cfg.benchmark('benchmark.cbr'), 8.75, 'policy rate'),
      _Bench(
        '91-DAY T-BILL',
        cfg.benchmark('benchmark.tbill_91'),
        8.71,
        'risk-free',
        accent: true,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 40,
                margin: const EdgeInsets.only(right: 13),
                color: c.line,
              ),
            Expanded(child: _Cell(items[i])),
          ],
        ],
      ),
    );
  }
}

class _Bench {
  _Bench(
    this.label,
    Benchmark? b,
    double fallback,
    this.sub, {
    this.accent = false,
  }) : value = b?.rate ?? fallback;
  final String label;
  final double value;
  final String sub;
  final bool accent;
}

class _Cell extends StatelessWidget {
  const _Cell(this.b);
  final _Bench b;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          b.label,
          style: TextStyle(
            color: c.faint,
            fontSize: 9.5,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${b.value.toStringAsFixed(2)}%',
          style: TextStyle(
            color: b.accent ? c.accent : c.text,
            fontFamily: fructaFonts.mono,
            fontSize: 19,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          b.sub,
          style: TextStyle(
            color: c.faint,
            fontSize: 9.5,
            fontFamily: fructaFonts.mono,
          ),
        ),
      ],
    );
  }
}

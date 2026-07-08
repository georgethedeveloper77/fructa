import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/models/fund.dart';
import '../../../data/providers.dart';
import '../../../data/snapshot_providers.dart';

/// "Vs category leaders · net yield" (v6 `.card`)  external eyebrow over a
/// panel card of horizontal bars ranking this fund against the top retail
/// peers of the same `fund_type` + currency, on the honest net comparator.
/// This fund's bar wears its brand [tint]; peers are muted. Rendered only for
/// funds that quote a yield and have at least one peer  never a single-bar
/// chart, never a fabricated ranking.
class PeerCompare extends ConsumerWidget {
  const PeerCompare(this.fund, {super.key, this.tint});

  final Fund fund;
  final Color? tint;

  static const _take = 5; // this fund + up to 4 leaders

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (!fund.showsYield || fund.currentRate == null) {
      return const SizedBox.shrink();
    }
    final wht = ref.watch(remoteConfigProvider).whtPct;
    final all = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];

    double net(Fund f) {
      final r = f.currentRate;
      if (r == null) return double.negativeInfinity;
      return f.taxFree ? r : r * (1 - wht / 100);
    }

    // Same-type, same-currency retail peers with a rate (excluding self).
    final peers =
        all
            .where(
              (f) =>
                  f.id != fund.id &&
                  f.retail &&
                  f.fundType == fund.fundType &&
                  f.currency == fund.currency &&
                  f.showsYield &&
                  f.currentRate != null,
            )
            .toList()
          ..sort((a, b) => net(b).compareTo(net(a)));
    if (peers.isEmpty) return const SizedBox.shrink();

    // This fund + the leaders, ranked together, capped at _take.
    final rows = <Fund>{fund, ...peers.take(_take - 1)}.toList()
      ..sort((a, b) => net(b).compareTo(net(a)));
    final maxNet = net(rows.first);
    if (maxNet <= 0) return const SizedBox.shrink();

    final brand = tint ?? c.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VS CATEGORY LEADERS \u00b7 NET YIELD',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in rows)
                  _Bar(
                    label: f.id == fund.id
                        ? '${_short(f.name)} (this)'
                        : _short(f.name),
                    value: net(f),
                    frac: (net(f) / maxNet).clamp(0.0, 1.0),
                    color: f.id == fund.id ? brand : c.s3,
                    valueColor: f.id == fund.id ? brand : c.muted,
                    labelColor: f.id == fund.id ? c.text : c.muted,
                    bold: f.id == fund.id,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Trim the common suffix noise so bars keep room  full names live on the
  /// tiles and detail header (this is a label, not a truncation of content).
  static String _short(String name) => name
      .replaceAll(
        RegExp(r'\s*Money Market Fund\s*$', caseSensitive: false),
        ' MMF',
      )
      .replaceAll(RegExp(r'\s*Fund\s*$', caseSensitive: false), '')
      .trim();
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.frac,
    required this.color,
    required this.valueColor,
    required this.labelColor,
    required this.bold,
  });

  final String label;
  final double value;
  final double frac;
  final Color color;
  final Color valueColor;
  final Color labelColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: c.s2),
                    FractionallySizedBox(
                      widthFactor: frac,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (_, t, child) =>
                            FractionallySizedBox(widthFactor: t, child: child),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              '${value.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontFamily: fructaFonts.mono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

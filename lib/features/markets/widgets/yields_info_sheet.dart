import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_colors.dart';
import '../../../core/theme.dart';
import '../../../data/snapshot_providers.dart';

/// Explainer for how Fructa shows yields, opened from the markets disclaimer.
/// The copy expands the published disclaimer into four plain points; each string
/// is an editable config value so it can be reworded without a release.
void showYieldsInfoSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _YieldsInfoSheet(),
  );
}

class _YieldsInfoSheet extends ConsumerWidget {
  const _YieldsInfoSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: c.line),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: c.line2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                cfg.string('yields.info.title', 'How we show yields'),
                style: TextStyle(
                  fontFamily: fructaFonts.mono,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 18),
              _Point(
                icon: Icons.percent,
                color: c.accent,
                title: cfg.string('yields.info.grossTitle', 'Gross, before tax'),
                body: cfg.string(
                  'yields.info.grossBody',
                  'Published rates are gross effective annual yields, exactly as each fund manager reports them.',
                ),
              ),
              _Point(
                icon: Icons.receipt_long_outlined,
                color: c.up,
                title: cfg.string('yields.info.netTitle', 'Net strips 15% tax'),
                body: cfg.string(
                  'yields.info.netBody',
                  'Switch to net and every rate drops by the 15% withholding tax. A 13.00% gross yield is 11.05% net.',
                ),
              ),
              _Point(
                icon: Icons.schedule,
                color: fundTypeColor('fixed_income'),
                title: cfg.string(
                  'yields.info.traceTitle',
                  'Timestamped and traceable',
                ),
                body: cfg.string(
                  'yields.info.traceBody',
                  'Every figure carries its source and the time it was pulled, so you can check it.',
                ),
              ),
              _Point(
                icon: Icons.verified_user_outlined,
                color: fundTypeColor('equity'),
                title: cfg.string(
                  'yields.info.custodyTitle',
                  'fructa never holds your funds',
                ),
                body: cfg.string(
                  'yields.info.custodyBody',
                  'We show and compare rates. Your money stays with the fund manager, never with us.',
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(cfg.string('common.gotIt', 'Got it')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

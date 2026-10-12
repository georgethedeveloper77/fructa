import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/pro/pro_providers.dart';
import 'paywall_page.dart';

/// Open the paywall. Resolves true when the user leaves it with Pro active.
///
/// [source] is the analytics label for the entry point, so conversion can be
/// read per surface.
Future<bool> openPaywall(BuildContext context, {required String source}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'paywall'),
      builder: (_) => PaywallPage(source: source),
    ),
  );
  return result ?? false;
}

/// Gate for a Pro action. Returns true straight away for Pro users, otherwise
/// shows the paywall and returns whether they came back subscribed. Use it in
/// front of any Pro-only tap:
///
///   if (!await ensurePro(context, ref, source: 'statement_import')) return;
Future<bool> ensurePro(
  BuildContext context,
  WidgetRef ref, {
  required String source,
}) async {
  if (ref.read(isProProvider)) return true;
  return openPaywall(context, source: source);
}

/// Small mono `PRO` pill. Accent fill, so it follows the selected accent.
class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.label = 'PRO'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.onAccent,
          fontFamily: fructaFonts.mono,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Portfolio upsell for free users: what Pro adds to the holdings they already
/// track. Renders nothing for Pro users or while Pro is switched off remotely.
class ProUpsellCard extends ConsumerWidget {
  const ProUpsellCard({super.key, required this.source});

  /// Analytics label passed through to the paywall.
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(proEnabledProvider) || ref.watch(isProProvider)) {
      return const SizedBox.shrink();
    }
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Material(
        color: c.s2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPaywall(context, source: source),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.insights_outlined,
                        color: c.accentInk,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'See what you really earned',
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ProBadge(),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Import your fund statements to track returns after tax, '
                  'the yield you were actually credited, and withholding tax '
                  'per year.',
                  style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Try Fructa Pro',
                      style: TextStyle(
                        color: c.accentInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: c.accentInk),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fund_logo.dart';
import '../../../data/models/stock.dart';

/// One broker, with a Trade button that opens the firm's own site.
///
/// Shared between the stock page (which shows a few) and the full directory
/// (which shows all of them), because two copies of the control that sends a
/// user off to place real money would inevitably drift.
///
/// "Trade" routes OUT. Fructa does not hold money, does not take an order and
/// does not have a position in whether you buy. The moment this button posts an
/// order instead of opening a browser, Fructa is a different, licensed product.
class BrokerRow extends StatelessWidget {
  const BrokerRow(this.broker, {super.key, required this.tint});

  final Broker broker;
  final Color tint;

  static Future<void> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      // No handler on the device at all. Nothing useful to do here, but the
      // button must not look broken, so the caller should surface it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = broker;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: c.s1,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            FundLogo(
              domain: null,
              logoUrl: b.logoUrl,
              seed: b.name,
              size: 40,
              brandColor: tint,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.name,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // The blurb is admin-entered and usually empty: the CMA
                  // register carries a name, a licence number and a website,
                  // and nothing else. So the licence number is the fallback
                  // subtitle. It is the fact that matters here anyway, and it
                  // is verifiable, which "mobile app, fast onboarding" is not.
                  const SizedBox(height: 3),
                  Text(
                    b.blurb ??
                        (b.licenseNo != null
                            ? t('stocks.broker.licensed', {'no': b.licenseNo!})
                            : t('stocks.broker.cma')),
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (b.openUrl != null)
              GestureDetector(
                onTap: () => open(b.openUrl!),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t('stocks.trade'),
                    style: TextStyle(
                      color: c.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

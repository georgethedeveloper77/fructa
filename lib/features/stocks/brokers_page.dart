import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/snapshot_providers.dart';
import 'widgets/broker_row.dart';

/// Every CMA-licensed firm you can buy NSE shares through.
///
/// The stock page shows only the first few, in the order the admin set. This is
/// the rest. There is deliberately no ranking, no rating, no "best broker" and
/// no sponsored slot: Fructa has no basis for preferring one licensed firm over
/// another, and pretending otherwise would be the moment this directory became
/// an advertisement.
///
/// The order is the admin's `sort_order`. It is NOT a claim about popularity,
/// because we have no usage data and would be inventing one.
class BrokersPage extends ConsumerWidget {
  const BrokersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final brokers = ref.watch(brokersProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text(
          t('stocks.brokers.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              t('stocks.brokers.sub'),
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
            ),
          ),
          for (final b in brokers) BrokerRow(b, tint: c.accent),
          if (brokers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  t('stocks.brokers.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              t('stocks.brokers.register'),
              style: TextStyle(color: c.faint, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

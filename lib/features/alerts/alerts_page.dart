import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/alert.dart';
import '../../data/providers.dart';

class AlertsPage extends ConsumerStatefulWidget {
  const AlertsPage({super.key});
  @override
  ConsumerState<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends ConsumerState<AlertsPage> {
  @override
  void initState() {
    super.initState();
    // Mark everything seen when the feed opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = DateTime.now();
      Hive.box('settings').put('alertsSeen', now.toIso8601String());
      ref.read(alertsSeenProvider.notifier).state = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final alerts = ref.watch(alertsProvider);
    final byId = ref.watch(fundsByIdProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        elevation: 0,
        title: const Text('Alerts', style: TextStyle(fontSize: 16)),
      ),
      body: alerts.isEmpty
          ? _Empty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: alerts.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: c.line, indent: 20, endIndent: 20),
              itemBuilder: (context, i) => _AlertRow(
                alerts[i],
                byId[alerts[i].fundId]?.name,
                byId[alerts[i].fundId]?.logoDomain,
                byId[alerts[i].fundId]?.manager,
              ),
            ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final RateAlert a;
  final String? name;
  final String? logoDomain;
  final String? manager;
  const _AlertRow(this.a, this.name, this.logoDomain, this.manager);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = a.up ? c.up : c.down;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          FundLogo(
            domain: logoDomain,
            seed: manager ?? name ?? a.fundId,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(color: c.text, fontSize: 14),
                    children: [
                      TextSpan(text: name ?? a.fundId),
                      TextSpan(
                        text: a.up ? ' rate rose to ' : ' rate fell to ',
                      ),
                      TextSpan(
                        text: '${a.newRate.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'from ${a.oldRate.toStringAsFixed(2)}% · ${timeAgo(a.at)}',
                  style: TextStyle(color: c.faint, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            a.up ? Icons.arrow_upward : Icons.arrow_downward,
            color: color,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, color: c.faint, size: 44),
            const SizedBox(height: 16),
            Text(
              'No alerts yet',
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Follow a fund from its page and fructa tells you here when its rate changes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/models/alert.dart';
import '../../data/models/smart_alert.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../pro/pro_widgets.dart';

/// Alerts: the smart-alert switches, then one feed of everything raised, rate
/// moves on followed funds and smart alerts together, newest first.
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
    final rate = ref.watch(alertsProvider);
    final smart = ref.watch(smartAlertsProvider);
    final byId = ref.watch(fundsByIdProvider);

    // One feed, newest first, across both kinds.
    final feed = <(DateTime, Widget)>[
      for (final a in rate)
        (
          a.at,
          _RateRow(
            a,
            byId[a.fundId]?.name,
            byId[a.fundId]?.logoDomain,
            byId[a.fundId]?.manager,
          ),
        ),
      for (final s in smart) (s.at, _SmartRow(s)),
    ]..sort((x, y) => y.$1.compareTo(x.$1));

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        elevation: 0,
        title: Text(t('alerts.title'), style: const TextStyle(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const _SmartSettings(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 6),
            child: Text(
              t('alerts.recent'),
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (feed.isEmpty)
            const _Empty()
          else
            for (var i = 0; i < feed.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: c.line, indent: 20, endIndent: 20),
              feed[i].$2,
            ],
        ],
      ),
    );
  }
}

/// The four smart-alert switches. Pro; while Pro is off remotely they are open
/// to everyone, as elsewhere.
class _SmartSettings extends ConsumerWidget {
  const _SmartSettings();

  static const _rows = [
    (
      SmartAlertType.underpaid,
      'alerts.smart.underpaid',
      'alerts.smart.underpaidSub',
    ),
    (
      SmartAlertType.betterFund,
      'alerts.smart.better',
      'alerts.smart.betterSub',
    ),
    (SmartAlertType.rankDrop, 'alerts.smart.rank', 'alerts.smart.rankSub'),
    (
      SmartAlertType.noInterest,
      'alerts.smart.noInterest',
      'alerts.smart.noInterestSub',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final unlocked = !ref.watch(proEnabledProvider) || ref.watch(isProProvider);
    final prefs = ref.watch(smartAlertPrefsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Material(
        color: c.s1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('alerts.smart.title'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!unlocked) const ProBadge(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                t('alerts.smart.sub'),
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
              ),
            ),
            for (final r in _rows)
              SwitchListTile.adaptive(
                value: unlocked && (prefs[r.$1] ?? true),
                activeTrackColor: c.accent,
                onChanged: (v) async {
                  if (!unlocked) {
                    await ensurePro(context, ref, source: 'smart_alerts');
                    return;
                  }
                  await ref.read(smartAlertPrefsProvider.notifier).set(r.$1, v);
                },
                title: Text(
                  t(r.$2),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  t(r.$3),
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.35),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _SmartRow extends StatelessWidget {
  const _SmartRow(this.a);

  final SmartAlert a;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, tone) = switch (a.type) {
      SmartAlertType.underpaid => (Icons.fact_check_outlined, c.down),
      SmartAlertType.noInterest => (
        Icons.report_gmailerrorred_outlined,
        c.down,
      ),
      SmartAlertType.betterFund => (Icons.trending_up_rounded, c.up),
      SmartAlertType.rankDrop => (Icons.south_rounded, c.accentInk),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: c.isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  a.body,
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 3),
                Text(
                  timeAgo(a.at),
                  style: TextStyle(color: c.faint, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RateRow extends StatelessWidget {
  final RateAlert a;
  final String? name;
  final String? logoDomain;
  final String? manager;
  const _RateRow(this.a, this.name, this.logoDomain, this.manager);

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
                        text: a.up ? t('alerts.rose') : t('alerts.fell'),
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
                  t('alerts.from', {
                    'rate': '${a.oldRate.toStringAsFixed(2)}%',
                    'ago': timeAgo(a.at),
                  }),
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
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 0),
      child: Column(
        children: [
          Icon(Icons.notifications_none, color: c.faint, size: 44),
          const SizedBox(height: 16),
          Text(
            t('alerts.emptyTitle'),
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('alerts.emptyBody'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

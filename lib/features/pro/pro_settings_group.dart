import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/pro/pro_service.dart';
import 'pro_widgets.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Settings block for Fructa Pro: current status, restore, and a route to the
/// store's own subscription page. Hidden entirely while Pro is switched off
/// remotely, so it ships dark with everything else.
class ProSettingsGroup extends ConsumerStatefulWidget {
  const ProSettingsGroup({super.key});

  @override
  ConsumerState<ProSettingsGroup> createState() => _ProSettingsGroupState();
}

class _ProSettingsGroupState extends ConsumerState<ProSettingsGroup> {
  bool _restoring = false;

  /// One line describing where the subscription stands. Billing trouble wins
  /// over everything else because it is the only state that needs action.
  String _statusLine(ProState s) {
    if (!s.active) return t('you.pro.pitch');
    if (s.billingIssue) return t('you.pro.billing');
    final end = s.expiresAt;
    if (end == null) return t('you.pro.active');
    final d = {'date': _date(end)};
    if (s.inTrial) {
      return t(s.willRenew ? 'you.pro.trialRenews' : 'you.pro.trialEnds', d);
    }
    return t(s.willRenew ? 'you.pro.renews' : 'you.pro.ends', d);
  }

  Future<void> _manage(ProState s) async {
    final fallback = defaultTargetPlatform == TargetPlatform.iOS
        ? Config.appleManageSubscriptionsUrl
        : Config.googleManageSubscriptionsUrl;
    final uri = Uri.tryParse(s.managementUrl ?? fallback);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[fructa] manage subscription link failed: $e');
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    final messenger = ScaffoldMessenger.of(context);
    final c = context.c;
    setState(() => _restoring = true);

    final outcome = await ref.read(proProvider.notifier).restore();
    Analytics.restorePurchases(outcome: outcome.name);
    if (!mounted) return;
    setState(() => _restoring = false);

    final msg = switch (outcome) {
      PurchaseOutcome.success => t('you.restore.done'),
      PurchaseOutcome.offline => t('you.restore.offline'),
      _ => t('you.restore.none'),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Subscribers keep Restore and Manage even while sales are switched off.
    if (!ref.watch(proEnabledProvider) && !ref.watch(isProProvider)) {
      return const SizedBox.shrink();
    }

    final c = context.c;
    final s = ref.watch(proProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SettingsGroup(
        children: [
          SettingsRow(
            icon: Icons.workspace_premium_outlined,
            iconTint: s.billingIssue ? c.down : c.accent,
            // Subscribers see their membership, never the word Pro.
            title: t(s.active ? 'you.membership' : 'you.pro.title'),
            sub: _statusLine(s),
            trailing: s.active
                ? Icon(Icons.open_in_new, color: c.faint, size: 18)
                : const ProBadge(),
            onTap: s.active
                ? () => _manage(s)
                : () => openPaywall(context, source: 'settings'),
          ),
          SettingsRow(
            icon: Icons.restore,
            iconTint: c.accent,
            title: t('you.restore'),
            sub: t('you.restoreSub'),
            showDivider: false,
            trailing: _restoring
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accent,
                    ),
                  )
                : null,
            onTap: _restoring ? null : _restore,
          ),
        ],
      ),
    );
  }
}

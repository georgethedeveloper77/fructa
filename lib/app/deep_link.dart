import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../features/alerts/alerts_page.dart';
import '../features/company/company_page.dart';
import 'main_scaffold.dart';

/// Global navigator + notification-tap router.
///
/// The OneSignal click handler (wired to [Push.onOpenTarget] in main) calls
/// [handlePushTarget]. If the app is still starting and no navigator exists
/// yet (a cold start FROM a notification), the target is buffered and
/// [drainPendingTarget] replays it once the scaffold is mounted.
///
/// Targets:
///   markets | portfolio | settings   -> switch bottom tab
///   alerts                           -> push the Alerts feed
///   fund/<id>                        -> push the fund's detail page
final rootNavigatorKey = GlobalKey<NavigatorState>();

String? _pending;

void handlePushTarget(String target) {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) {
    _pending = target; // navigator not ready yet  replay after mount
    return;
  }
  _route(ctx, target);
}

/// Called once the main scaffold is mounted, to replay a cold-start tap.
void drainPendingTarget() {
  final t = _pending;
  if (t == null) return;
  _pending = null;
  handlePushTarget(t);
}

void _route(BuildContext ctx, String target) {
  final c = ProviderScope.containerOf(ctx, listen: false);
  void tab(int i) => c.read(selectedTabProvider.notifier).state = i;

  switch (target) {
    case 'markets':
      return tab(0);
    case 'portfolio':
      return tab(1);
    case 'settings':
      return tab(2);
    case 'alerts':
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const AlertsPage()),
      );
      return;
  }

  if (target.startsWith('fund/')) {
    final id = target.substring('fund/'.length);
    final fund = c.read(fundsByIdProvider)[id];
    if (fund != null) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => CompanyPage(fund)),
      );
    } else {
      tab(0); // fund not in the snapshot yet  land on Markets
    }
  }
}

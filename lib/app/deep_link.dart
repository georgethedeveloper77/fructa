import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/fund.dart';
import '../data/providers.dart';
import '../features/alerts/alerts_page.dart';
import '../features/company/company_page.dart';
import '../features/reports/reports_page.dart';
import '../features/wrap/wrap_viewer.dart';
import 'main_scaffold.dart';

/// Global navigator + notification-tap router.
///
/// The OneSignal click handler (wired to [Push.onOpenTarget] in main) calls
/// [handlePushTarget]. If the app is still starting and no navigator exists
/// yet (a cold start FROM a notification), the target is buffered and
/// [drainPendingTarget] replays it once the scaffold is mounted.
///
/// Targets:
///   `markets` | `portfolio` | `settings`   switch bottom tab
///   `today`                               switch to Today
///   `alerts`                              push the Alerts feed
///   `reports`                             push Reports
///   `wrap` | `wrap/<i>`                   open this week's wrap (at story i)
///   `fund/<id>`                           push the fund's detail page
///   `fundslug/<slug>`                     the same, from a fructa.africa link
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
    case 'today':
      return tab(3);
    case 'reports':
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ReportsPage()),
      );
      return;
    case 'alerts':
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const AlertsPage()),
      );
      return;
  }

  if (target == 'wrap' || target.startsWith('wrap/')) {
    final at = int.tryParse(
      target.substring('wrap'.length).replaceAll('/', ''),
    );
    tab(3);
    openWeeklyWrap(ctx, start: at ?? 0);
    return;
  }

  if (target.startsWith('fundslug/')) {
    final slug = target.substring('fundslug/'.length);
    final fund = _fundForSlug(c.read(fundsByIdProvider).values, slug);
    if (fund != null) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => CompanyPage(fund)),
      );
    } else {
      tab(0);
    }
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

// ── fructa.africa links ────────────────────────────────────────────────────

/// The web's slug for a fund name: lowercase, every run of other characters
/// a dash, no dash at either end. Matches slugify() in fructa-admin, so a
/// `/funds/<slug>` link finds the same fund here.
String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// The fund a web slug names. The site adds the currency, or the id, when two
/// funds share a name, so all three forms are tried.
Fund? _fundForSlug(Iterable<Fund> funds, String slug) {
  for (final f in funds) {
    final base = _slugify(f.name);
    if (slug == base ||
        slug == '$base-${f.currency.toLowerCase()}' ||
        slug == '$base-${_slugify(f.id)}') {
      return f;
    }
  }
  return null;
}

/// The app target a fructa.africa link points at, or null for one it does
/// not handle (it then stays in the browser on the next tap).
String? targetForWebLink(Uri uri) {
  if (uri.host != 'fructa.africa' && uri.host != 'www.fructa.africa') {
    return null;
  }
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2 && parts.first == 'funds') {
    return 'fundslug/${parts[1]}';
  }
  if (parts.isNotEmpty && parts.first == 'rates') {
    return 'markets';
  }
  return null;
}

StreamSubscription<Uri>? _links;

/// Listens for fructa.africa links opening the app, the first one included,
/// and routes them like a notification tap (buffered until the app is up).
void startWebLinks() {
  _links ??= AppLinks().uriLinkStream.listen((uri) {
    final target = targetForWebLink(uri);
    if (target != null) handlePushTarget(target);
  });
}

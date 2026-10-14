import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/analytics.dart';
import '../../core/config.dart';
import '../../core/theme_controller.dart' show settingsBoxProvider;
import '../snapshot_providers.dart';
import 'pro_service.dart';

/// Everything the UI needs to know about the user's Pro access.
@immutable
class ProState {
  const ProState({
    required this.active,
    this.willRenew = false,
    this.inTrial = false,
    this.billingIssue = false,
    this.expiresAt,
    this.managementUrl,
  });

  final bool active;
  final bool willRenew;
  final bool inTrial;

  /// The store failed to charge a renewal. Access continues through the grace
  /// period, but the user should hear about it before it lapses.
  final bool billingIssue;

  final DateTime? expiresAt;

  /// Store page where this subscription is managed or cancelled.
  final String? managementUrl;

  static const free = ProState(active: false);

  factory ProState.fromInfo(CustomerInfo info) {
    final e = info.entitlements.active[Config.proEntitlement];
    if (e == null || !e.isActive) {
      return ProState(active: false, managementUrl: info.managementURL);
    }
    return ProState(
      active: true,
      willRenew: e.willRenew,
      inTrial: e.periodType == PeriodType.trial,
      billingIssue: e.billingIssueDetectedAt != null,
      expiresAt: e.expirationDate == null
          ? null
          : DateTime.tryParse(e.expirationDate!)?.toLocal(),
      managementUrl: info.managementURL,
    );
  }
}

/// Live Pro state.
///
/// First frame reads a cached flag from the Hive `settings` box so a paying
/// user never sees a paywall flash on launch. The authoritative answer arrives
/// from RevenueCat once [ProService] is ready, and every later change (renewal,
/// expiry, refund, a pending payment clearing) lands through the listener.
class ProController extends Notifier<ProState> {
  static const _cacheKey = 'pro_active';

  @override
  ProState build() {
    ref.onDispose(() => ProService.removeListener(_onInfo));
    // Deferred past build: RevenueCat invokes a new listener synchronously
    // with its last known info, and assigning state inside build throws.
    Future.microtask(() {
      ProService.addListener(_onInfo);
      refresh();
    });
    final cached =
        ref.read(settingsBoxProvider).get(_cacheKey, defaultValue: false)
            as bool;
    return cached ? const ProState(active: true) : ProState.free;
  }

  void _onInfo(CustomerInfo info) => _apply(ProState.fromInfo(info));

  void _apply(ProState next) {
    state = next;
    ref.read(settingsBoxProvider).put(_cacheKey, next.active);
    Analytics.setProStatus(next.active, trial: next.inTrial);
  }

  /// Ask RevenueCat for the current answer. Keeps the cached state when the
  /// SDK is dormant or unreachable rather than downgrading a paying user.
  Future<void> refresh() async {
    final info = await ProService.customerInfo();
    if (info != null) _apply(ProState.fromInfo(info));
  }

  Future<PurchaseOutcome> purchase(Package package) async {
    final (outcome, info) = await ProService.purchase(package);
    if (info != null) _apply(ProState.fromInfo(info));
    return outcome;
  }

  Future<PurchaseOutcome> restore() async {
    final (outcome, info) = await ProService.restore();
    if (info != null) _apply(ProState.fromInfo(info));
    return outcome;
  }
}

final proProvider = NotifierProvider<ProController, ProState>(
  ProController.new,
);

/// Debug builds only: a switch in You that unlocks Pro locally, so reports,
/// statements and the wrap can be tested before a store purchase syncs.
/// Release builds ignore it entirely.
class DebugProNotifier extends Notifier<bool> {
  static const _key = 'debug_pro';

  @override
  bool build() =>
      kDebugMode &&
      (ref.read(settingsBoxProvider).get(_key, defaultValue: false) as bool);

  Future<void> set(bool on) async {
    if (!kDebugMode) return;
    state = on;
    await ref.read(settingsBoxProvider).put(_key, on);
  }
}

final debugProProvider = NotifierProvider<DebugProNotifier, bool>(
  DebugProNotifier.new,
);

/// Shorthand for gates that only need the yes or no.
final isProProvider = Provider<bool>(
  (ref) =>
      ref.watch(debugProProvider) ||
      ref.watch(proProvider.select((s) => s.active)),
);

/// Whether any Pro surface is shown at all.
///
/// Off in release until `pro.enabled` is set true in admin Config, so the
/// paywall and upsells ship dark and go live without a new build once the
/// store products are approved and the importer is ready. Always on in debug
/// builds so the flow can be tested against sandbox accounts.
final proEnabledProvider = Provider<bool>(
  (ref) =>
      kDebugMode || ref.watch(remoteConfigProvider).flag('pro.enabled', false),
);

/// The plans to show on the paywall. autoDispose so each paywall open gets a
/// fresh read, which matters after a price change in the store consoles.
final proOfferingProvider = FutureProvider.autoDispose<Offering?>(
  (ref) => ProService.currentOffering(),
);

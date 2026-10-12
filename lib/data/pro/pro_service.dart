import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/config.dart';

/// How a purchase or restore attempt ended, in the terms the UI cares about.
///
/// The store SDKs report dozens of error codes. The paywall only ever needs to
/// decide between five reactions, so the mapping lives here once instead of in
/// every caller.
enum PurchaseOutcome {
  /// Entitlement is now active.
  success,

  /// The user closed the store sheet. Not an error, say nothing.
  cancelled,

  /// Payment awaits approval (Google Play cash or family approval). Access
  /// arrives through the customer info listener when it clears.
  pending,

  /// The store says this account already owns it. A restore resolves it.
  alreadyOwned,

  /// No network. Worth a retry rather than a support email.
  offline,

  /// Anything else: store unavailable, not allowed, misconfiguration.
  failed,
}

/// RevenueCat, wrapped so the rest of the app never touches the SDK.
///
/// Same three rules as [Analytics]:
///
///   1. Nothing here throws into a caller. Every failure becomes a value.
///   2. Nothing here runs before first paint. [init] is called from the
///      post-runApp block in main() and is time-boxed there.
///   3. Without real API keys the service stays dormant and every query answers
///      "not Pro", so a build cut before the dashboard is ready behaves exactly
///      like the current release.
class ProService {
  ProService._();

  static final Completer<bool> _ready = Completer<bool>();

  /// Completes once configuration has been attempted: true when the SDK is
  /// live, false when it was skipped or failed. Callers await this rather than
  /// racing [init], because providers can build before main() reaches it.
  static Future<bool> get whenReady => _ready.future;

  static bool _configured = false;

  /// [whenReady] with a ceiling, so a store SDK that never answers leaves the
  /// caller with "not available" instead of a spinner that never ends.
  static Future<bool> _live() => whenReady.timeout(
    const Duration(seconds: 12),
    onTimeout: () => false,
  );

  /// Whether the SDK came up. False means every query below answers empty.
  static bool get configured => _configured;

  /// The key for this platform, or null when the platform is unsupported or
  /// the placeholder is still in [Config].
  static String? get _apiKey {
    if (kIsWeb) return null;
    final key = Platform.isIOS
        ? Config.revenueCatAppleKey
        : Platform.isAndroid
        ? Config.revenueCatGoogleKey
        : null;
    if (key == null || key.contains('REPLACE_ME')) return null;
    return key;
  }

  /// Configure RevenueCat. Safe to call twice; the second call is a no-op.
  static Future<void> init() async {
    if (_ready.isCompleted) return;
    final key = _apiKey;
    if (key == null) {
      debugPrint('[fructa] ProService dormant: no RevenueCat key for platform');
      _ready.complete(false);
      return;
    }
    try {
      if (kDebugMode) await Purchases.setLogLevel(LogLevel.debug);
      // Anonymous app user ids. Fructa has no accounts, and the store receipt
      // is what restores access on a new phone, so there is nothing to log in.
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
    } catch (e, st) {
      debugPrint('[fructa] ProService.init failed: $e\n$st');
    } finally {
      if (!_ready.isCompleted) _ready.complete(_configured);
    }
  }

  /// Register for entitlement changes: renewals, expiries, refunds, a pending
  /// payment clearing, a purchase made on another device with the same store
  /// account. Safe before [init]; RevenueCat queues the listener.
  static void addListener(void Function(CustomerInfo) listener) {
    try {
      Purchases.addCustomerInfoUpdateListener(listener);
    } catch (e) {
      debugPrint('[fructa] ProService.addListener: $e');
    }
  }

  static void removeListener(void Function(CustomerInfo) listener) {
    try {
      Purchases.removeCustomerInfoUpdateListener(listener);
    } catch (e) {
      debugPrint('[fructa] ProService.removeListener: $e');
    }
  }

  /// Current customer info, or null when the SDK is dormant or unreachable.
  /// RevenueCat serves this from its own on-device cache when offline, so a
  /// paying user keeps access on a plane.
  static Future<CustomerInfo?> customerInfo() async {
    if (!await _live()) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('[fructa] ProService.customerInfo: $e');
      return null;
    }
  }

  /// The current offering (the plans the paywall shows), or null.
  static Future<Offering?> currentOffering() async {
    if (!await _live()) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      debugPrint('[fructa] ProService.currentOffering: $e');
      return null;
    }
  }

  /// Buy [package]. Returns the outcome and, on success, fresh customer info.
  static Future<(PurchaseOutcome, CustomerInfo?)> purchase(
    Package package,
  ) async {
    if (!await _live()) return (PurchaseOutcome.failed, null);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final info = result.customerInfo;
      return (
        isPro(info) ? PurchaseOutcome.success : PurchaseOutcome.pending,
        info,
      );
    } on PlatformException catch (e) {
      return (_outcomeFor(e), null);
    } catch (e) {
      debugPrint('[fructa] ProService.purchase: $e');
      return (PurchaseOutcome.failed, null);
    }
  }

  /// Restore previous purchases from the signed-in store account.
  static Future<(PurchaseOutcome, CustomerInfo?)> restore() async {
    if (!await _live()) return (PurchaseOutcome.failed, null);
    try {
      final info = await Purchases.restorePurchases();
      return (
        isPro(info) ? PurchaseOutcome.success : PurchaseOutcome.failed,
        info,
      );
    } on PlatformException catch (e) {
      return (_outcomeFor(e), null);
    } catch (e) {
      debugPrint('[fructa] ProService.restore: $e');
      return (PurchaseOutcome.failed, null);
    }
  }

  /// The one definition of "is this person Pro".
  static bool isPro(CustomerInfo? info) =>
      info?.entitlements.active[Config.proEntitlement]?.isActive ?? false;

  static PurchaseOutcome _outcomeFor(PlatformException e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    debugPrint('[fructa] ProService store error: $code ${e.message}');
    return switch (code) {
      PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
      PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
      PurchasesErrorCode.productAlreadyPurchasedError ||
      PurchasesErrorCode.receiptAlreadyInUseError =>
        PurchaseOutcome.alreadyOwned,
      PurchasesErrorCode.networkError ||
      PurchasesErrorCode.offlineConnectionError => PurchaseOutcome.offline,
      _ => PurchaseOutcome.failed,
    };
  }
}

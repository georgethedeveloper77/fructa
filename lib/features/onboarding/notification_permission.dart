import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// Raises the OS notification-permission prompt at the onboarding "Turn on
// alerts" moment (and reusable from Settings). Kept behind a provider so
// onboarding stays testable  override `notificationPermissionProvider` with a
// fake in widget tests.
//
// onesignal_flutter v5: requestPermission(true) returns a Future<bool>.

typedef PermissionRequester = Future<bool> Function();

Future<bool> _requestViaOneSignal() async {
  try {
    return await OneSignal.Notifications.requestPermission(true);
  } catch (_) {
    return false;
  }
}

final notificationPermissionProvider = Provider<PermissionRequester>(
  (_) => _requestViaOneSignal,
);

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push.dart';
import 'theme_controller.dart' show settingsBoxProvider;

/// Notification + security preferences. Persisted in the shared Hive `settings`
/// box. Per spec, all notification toggles default **ON**; security toggles
/// default OFF. The weekly-digest toggle mirrors to the OneSignal
/// `digest_weekly` tag so the server can segment the digest broadcast.
@immutable
class SettingsPrefs {
  const SettingsPrefs({
    required this.masterAlerts,
    required this.rateMoves,
    required this.savedComparisons,
    required this.couponsMaturities,
    required this.weeklyDigest,
    required this.biometricLock,
    required this.hideBalances,
  });

  // Notifications  default ON.
  final bool masterAlerts;
  final bool rateMoves; // ±0.15 pts
  final bool savedComparisons; // leader flip / gap > 0.25
  final bool couponsMaturities;
  final bool weeklyDigest;

  // Security  default OFF.
  final bool biometricLock;
  final bool hideBalances;

  static const initial = SettingsPrefs(
    masterAlerts: true,
    rateMoves: true,
    savedComparisons: true,
    couponsMaturities: true,
    weeklyDigest: true,
    biometricLock: false,
    hideBalances: false,
  );

  SettingsPrefs copyWith({
    bool? masterAlerts,
    bool? rateMoves,
    bool? savedComparisons,
    bool? couponsMaturities,
    bool? weeklyDigest,
    bool? biometricLock,
    bool? hideBalances,
  }) {
    return SettingsPrefs(
      masterAlerts: masterAlerts ?? this.masterAlerts,
      rateMoves: rateMoves ?? this.rateMoves,
      savedComparisons: savedComparisons ?? this.savedComparisons,
      couponsMaturities: couponsMaturities ?? this.couponsMaturities,
      weeklyDigest: weeklyDigest ?? this.weeklyDigest,
      biometricLock: biometricLock ?? this.biometricLock,
      hideBalances: hideBalances ?? this.hideBalances,
    );
  }
}

class SettingsController extends Notifier<SettingsPrefs> {
  bool _get(String k, bool d) =>
      ref.read(settingsBoxProvider).get('pref_$k', defaultValue: d) as bool;

  void _put(String k, bool v) =>
      ref.read(settingsBoxProvider).put('pref_$k', v);

  @override
  SettingsPrefs build() {
    const i = SettingsPrefs.initial;
    return SettingsPrefs(
      masterAlerts: _get('masterAlerts', i.masterAlerts),
      rateMoves: _get('rateMoves', i.rateMoves),
      savedComparisons: _get('savedComparisons', i.savedComparisons),
      couponsMaturities: _get('couponsMaturities', i.couponsMaturities),
      weeklyDigest: _get('weeklyDigest', i.weeklyDigest),
      biometricLock: _get('biometricLock', i.biometricLock),
      hideBalances: _get('hideBalances', i.hideBalances),
    );
  }

  void setMasterAlerts(bool v) {
    state = state.copyWith(masterAlerts: v);
    _put('masterAlerts', v);
    // Master switch drives the device-level push opt-in/out at OneSignal.
    Push.setEnabled(v);
  }

  void setRateMoves(bool v) {
    state = state.copyWith(rateMoves: v);
    _put('rateMoves', v);
  }

  void setSavedComparisons(bool v) {
    state = state.copyWith(savedComparisons: v);
    _put('savedComparisons', v);
  }

  void setCouponsMaturities(bool v) {
    state = state.copyWith(couponsMaturities: v);
    _put('couponsMaturities', v);
  }

  void setWeeklyDigest(bool v) {
    state = state.copyWith(weeklyDigest: v);
    _put('weeklyDigest', v);
    // Mirror to the server segment so the weekly digest reaches (only) opt-ins.
    Push.setDigest(v);
  }

  void setBiometricLock(bool v) {
    state = state.copyWith(biometricLock: v);
    _put('biometricLock', v);
  }

  void setHideBalances(bool v) {
    state = state.copyWith(hideBalances: v);
    _put('hideBalances', v);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsPrefs>(SettingsController.new);

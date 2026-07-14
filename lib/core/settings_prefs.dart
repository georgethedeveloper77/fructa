import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'push.dart';
import 'theme_controller.dart' show settingsBoxProvider;

/// Notification + security preferences. Persisted in the shared Hive `settings`
/// box. Per spec, all notification toggles default ON; security toggles default
/// OFF.
///
/// Every notification toggle now mirrors to OneSignal. Until this change only
/// `weeklyDigest` did, and the other three wrote to Hive and stopped there. The
/// server targets a fund by `follow_<id>` and knows nothing about a user's
/// preferences, so a user who turned "Rate moves" OFF kept receiving rate-move
/// pushes indefinitely, with no way to stop them short of killing every alert
/// the app sends. The toggle was decorative.
///
/// The mirroring is by MUTE tag, not by opt-in tag. See Push.setMuted for why:
/// an opt-in tag would have required every device already installed to write it
/// before the server could filter on it, and until they did the filter would
/// have matched nobody and shipped silence to the entire user base.
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

  // Notifications: default ON.
  final bool masterAlerts;
  final bool rateMoves; // 0.15 pts either way
  final bool savedComparisons; // leader flip / gap > 0.25
  final bool couponsMaturities;
  final bool weeklyDigest;

  // Security: default OFF.
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

  /// The mute tags this device should be carrying, derived from the toggles.
  /// A toggle that is ON contributes nothing: no tag is the default state, and
  /// that is what makes the whole scheme backward compatible.
  Set<String> get muteTags => {
        if (!rateMoves) Push.muteRateMoves,
        if (!savedComparisons) Push.muteSaved,
        if (!couponsMaturities) Push.muteCoupons,
      };

  /// Same derivation, straight off the Hive box.
  ///
  /// main() has to reconcile tags before the ProviderScope exists, so it cannot
  /// read `settingsControllerProvider`. Rather than let it hand-roll the key
  /// names (and drift), it calls this. One definition of what a mute tag is.
  static Set<String> muteTagsFrom(Box box) {
    bool on(String k) => box.get('pref_$k', defaultValue: true) as bool;
    return {
      if (!on('rateMoves')) Push.muteRateMoves,
      if (!on('savedComparisons')) Push.muteSaved,
      if (!on('couponsMaturities')) Push.muteCoupons,
    };
  }

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

  void _put(String k, bool v) => ref.read(settingsBoxProvider).put('pref_$k', v);

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

  /// Turning the master switch ON has to do more than flip a bool.
  ///
  /// On a device that never granted the OS notification permission, opting the
  /// push subscription back in changes nothing: Android and iOS still drop every
  /// alert silently. So the master switch prompts. Returns whether alerts can now
  /// actually reach this phone, so the caller can say so if they cannot.
  Future<bool> setMasterAlerts(bool v) async {
    state = state.copyWith(masterAlerts: v);
    _put('masterAlerts', v);

    if (!v) {
      Push.setEnabled(false);
      return false;
    }
    // optIn plus the OS prompt if it has never been granted.
    return Push.ensureDeliverable();
  }

  void setRateMoves(bool v) {
    state = state.copyWith(rateMoves: v);
    _put('rateMoves', v);
    Push.setMuted(Push.muteRateMoves, !v);
  }

  void setSavedComparisons(bool v) {
    state = state.copyWith(savedComparisons: v);
    _put('savedComparisons', v);
    Push.setMuted(Push.muteSaved, !v);
  }

  void setCouponsMaturities(bool v) {
    state = state.copyWith(couponsMaturities: v);
    _put('couponsMaturities', v);
    Push.setMuted(Push.muteCoupons, !v);
  }

  void setWeeklyDigest(bool v) {
    state = state.copyWith(weeklyDigest: v);
    _put('weeklyDigest', v);
    // Mirror to the server segment so the weekly digest reaches (only) opt-ins.
    // This one stays an opt-IN tag: the digest is a broadcast, so there is no
    // per-user hook like `follow_<id>` for the server to hang a mute off.
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

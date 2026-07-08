import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../backup/backup_ui.dart';
import '../learn/learn_home_page.dart';
import 'widgets/appearance_section.dart';

/// v5 `.pg-settings` — flat rows from the kit, no cards. Sections: Learn
/// (stub until D2, no fabricated streak/star stats), Notifications (master
/// gates children AND drives the OneSignal subscription), Appearance
/// (mode segmented + accent swatches), Security & data.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final prefs = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final master = prefs.masterAlerts;
    // Live value the LockGate actually reads; the pref persists the choice.
    final lockOn = ref.watch(appLockProvider);
    final cfg = ref.watch(remoteConfigProvider); // V6 admin-controlled copy

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 120),
          children: [
            const DisplayHeader(
              title: 'Settings',
              sub: 'No account needed \u00b7 everything on this device',
            ),
            const SizedBox(height: 16),

            // ── Learn (D2 stub — honest copy, no fake streaks) ────────────
            LearnCard(
              title: cfg.string('learn.card.title', 'Learn'),
              subtitle: cfg.string('learn.card.subtitle',
                  'MMFs, gross vs net, why rates move'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LearnHomePage()),
              ),
            ),

            const SectionHeader(
                title: 'Notifications', trailing: 'on by default'),
            const SizedBox(height: 4),
            SettingsRow(
              icon: Icons.notifications_none,
              title: 'Push notifications',
              sub: 'Master switch',
              trailing: fructaToggle(
                value: master,
                onChanged: (v) {
                  ctrl.setMasterAlerts(v);
                  Push.setEnabled(v); // opt the device in/out at OneSignal
                },
              ),
            ),
            _Gated(
              enabled: master,
              child: Column(children: [
                SettingsRow(
                  icon: Icons.trending_up,
                  title: 'Rate moves',
                  sub: 'Followed funds past \u00b1 0.15 pts',
                  trailing: fructaToggle(
                      value: prefs.rateMoves, onChanged: ctrl.setRateMoves),
                ),
                SettingsRow(
                  icon: Icons.swap_horiz,
                  title: 'Saved comparisons',
                  sub: 'When the leader flips or the gap moves > 0.25 pts',
                  trailing: fructaToggle(
                      value: prefs.savedComparisons,
                      onChanged: ctrl.setSavedComparisons),
                ),
                SettingsRow(
                  icon: Icons.paid_outlined,
                  title: 'Coupons & maturities',
                  trailing: fructaToggle(
                      value: prefs.couponsMaturities,
                      onChanged: ctrl.setCouponsMaturities),
                ),
                SettingsRow(
                  icon: Icons.newspaper_outlined,
                  title: 'Weekly digest',
                  sub: 'Fridays',
                  showDivider: false,
                  trailing: fructaToggle(
                      value: prefs.weeklyDigest,
                      onChanged: ctrl.setWeeklyDigest),
                ),
              ]),
            ),

            const SectionHeader(title: 'Appearance'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: AppearanceSection(),
            ),

            const SectionHeader(title: 'Security & data'),
            const SizedBox(height: 4),
            SettingsRow(
              icon: Icons.lock_outline,
              title: 'Face ID / Touch ID',
              sub: 'Require unlock to open fructa',
              trailing: fructaToggle(
                value: lockOn,
                onChanged: (v) {
                  ref.read(appLockProvider.notifier).state = v;
                  ctrl.setBiometricLock(v); // persisted mirror
                },
              ),
            ),
            SettingsRow(
              icon: Icons.visibility_off_outlined,
              title: 'Hide balances',
              sub: 'Mask amounts across the app',
              trailing: fructaToggle(
                  value: prefs.hideBalances,
                  onChanged: ctrl.setHideBalances),
            ),
            SettingsRow(
              icon: Icons.cloud_upload_outlined,
              title: 'Back up portfolio',
              sub: 'Recovery code \u00b7 restore on any device',
              onTap: () => showBackupSheet(context, ref),
            ),
            SettingsRow(
              icon: Icons.settings_backup_restore,
              title: 'Restore from backup',
              sub: 'Enter a code from another phone',
              showDivider: false,
              onTap: () => showRestoreSheet(context, ref),
            ),

            const Disclaimer(
              'fructa \u00b7 v1.0 \u00b7 rates from licensed sources, '
              'timestamped & traceable',
              center: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Children of the master switch: dimmed + inert while master is off,
/// keeping each child's own stored value intact.
class _Gated extends StatelessWidget {
  const _Gated({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !enabled,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.45,
          child: child,
        ),
      );
}

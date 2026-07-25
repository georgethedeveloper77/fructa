import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../backup/backup_ui.dart';
import '../blog/blog_page.dart';
import '../learn/learn_home_page.dart';
import '../learn/learn_progress.dart';
import '../learn/learn_reminder.dart';
import 'following_page.dart';
import 'widgets/app_version_footer.dart';
import 'widgets/appearance_section.dart';

/// Settings, grouped. Related rows sit in rounded [SettingsGroup] cards, each
/// section tinted one calm colour, so the screen reads as organized rather than
/// a wall of flat rows. The developer notification-diagnostics panel is gone:
/// the master switch already tells a user (via snackbar) when push can't land,
/// so the four-condition dev readout has no place in user settings.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// The master switch used to flip a bool and call Push.setEnabled. On a phone
  /// that never granted the OS notification permission that was a no-op dressed
  /// up as a control: the toggle went green, and every alert kept being dropped
  /// silently by the OS. It now prompts, and if the user declines, says so
  /// rather than leaving a green switch that means nothing.
  Future<void> _setMaster(BuildContext context, WidgetRef ref, bool on) async {
    final deliverable = await ref
        .read(settingsControllerProvider.notifier)
        .setMasterAlerts(on);

    if (!context.mounted || !on || deliverable) return;

    final c = context.c;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: c.s3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            t('settings.notif.blocked'),
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final prefs = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final master = prefs.masterAlerts;
    // Live value the LockGate actually reads; the pref persists the choice.
    final lockOn = ref.watch(appLockProvider);
    final followCount = ref.watch(subscriptionsProvider).length;
    final reminder = ref.watch(learnReminderProvider);
    final learnStreak = ref.watch(learnProgressProvider).streak;
    final cfg = ref.watch(remoteConfigProvider); // V6 admin-controlled copy

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 120),
          children: [
            DisplayHeader(title: t('settings.title'), sub: t('settings.sub')),
            const SizedBox(height: 18),

            // Learn (D2 stub - honest copy, no fake streaks)
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.school_outlined,
                  iconTint: c.accent,
                  title: cfg.string(
                    'learn.card.title',
                    t('settings.learn.title'),
                  ),
                  sub: cfg.string(
                    'learn.card.subtitle',
                    t('settings.learn.subtitle'),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LearnHomePage()),
                  ),
                ),
                SettingsRow(
                  icon: Icons.menu_book_outlined,
                  iconTint: c.accent,
                  title: t('settings.blog.title'),
                  sub: t('settings.blog.subtitle'),
                  showDivider: false,
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const BlogPage())),
                ),
              ],
            ),

            SectionHeader(
              title: t('settings.notifications'),
              //trailing: t('settings.notif.trailing'),
            ),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.star_outline,
                  iconTint: c.accent,
                  title: 'Following',
                  sub: '$followCount ${followCount == 1 ? 'fund' : 'funds'}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FollowingPage()),
                  ),
                ),
                SettingsRow(
                  icon: Icons.notifications_none,
                  iconTint: c.accent,
                  title: t('settings.notif.master'),
                  sub: t('settings.notif.masterSub'),
                  trailing: fructaToggle(
                    value: master,
                    // setMasterAlerts already drives Push.setEnabled and the OS
                    // prompt. No duplicate side effect here: two owners of one
                    // side effect is how they drift.
                    onChanged: (v) => _setMaster(context, ref, v),
                  ),
                ),
                // Children of the master switch: dimmed + inert while master is
                // off, keeping each child's own stored value intact.
                _Gated(
                  enabled: master,
                  child: Column(
                    children: [
                      SettingsRow(
                        icon: Icons.trending_up,
                        iconTint: c.accent,
                        title: t('settings.notif.rateMoves'),
                        sub: t('settings.notif.rateMovesSub'),
                        trailing: fructaToggle(
                          value: prefs.rateMoves,
                          onChanged: ctrl.setRateMoves,
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.swap_horiz,
                        iconTint: c.accent,
                        title: t('settings.notif.saved'),
                        sub: t('settings.notif.savedSub'),
                        trailing: fructaToggle(
                          value: prefs.savedComparisons,
                          onChanged: ctrl.setSavedComparisons,
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.paid_outlined,
                        iconTint: c.accent,
                        title: t('settings.notif.coupons'),
                        trailing: fructaToggle(
                          value: prefs.couponsMaturities,
                          onChanged: ctrl.setCouponsMaturities,
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.newspaper_outlined,
                        iconTint: c.accent,
                        title: t('settings.notif.digest'),
                        sub: t('settings.notif.digestSub'),
                        showDivider: false,
                        trailing: fructaToggle(
                          value: prefs.weeklyDigest,
                          onChanged: ctrl.setWeeklyDigest,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.local_fire_department_rounded,
                  iconTint: c.accent,
                  title: 'Learn reminder',
                  sub: 'Daily nudge to keep your streak',
                  showDivider: reminder.enabled,
                  trailing: fructaToggle(
                    value: reminder.enabled,
                    onChanged: (v) => ref
                        .read(learnReminderProvider.notifier)
                        .setEnabled(v, streak: learnStreak),
                  ),
                ),
                if (reminder.enabled)
                  SettingsRow(
                    icon: Icons.schedule,
                    iconTint: c.accent,
                    title: 'Reminder time',
                    showDivider: false,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: reminder.time,
                      );
                      if (picked != null) {
                        ref
                            .read(learnReminderProvider.notifier)
                            .setTime(
                              picked.hour,
                              picked.minute,
                              streak: learnStreak,
                            );
                      }
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmtTime(reminder.time),
                          style: TextStyle(
                            color: c.accent,
                            fontFamily: fructaFonts.mono,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: c.faint, size: 18),
                      ],
                    ),
                  ),
              ],
            ),

            SectionHeader(title: t('settings.appearance')),
            const SizedBox(height: 4),
            const SettingsGroup(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: AppearanceSection(),
                ),
              ],
            ),

            SectionHeader(title: t('settings.security')),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.lock_outline,
                  iconTint: c.accent,
                  title: t('settings.security.biometric'),
                  sub: t('settings.security.biometricSub'),
                  trailing: fructaToggle(
                    value: lockOn,
                    onChanged: (v) {
                      // set() persists to Hive AND updates the live value; the
                      // old direct `.state = v` bypassed persistence.
                      ref.read(appLockProvider.notifier).set(v);
                      ctrl.setBiometricLock(v); // persisted mirror
                    },
                  ),
                ),
                SettingsRow(
                  icon: Icons.visibility_off_outlined,
                  iconTint: c.accent,
                  title: t('settings.security.hideBalances'),
                  sub: t('settings.security.hideBalancesSub'),
                  trailing: fructaToggle(
                    value: prefs.hideBalances,
                    onChanged: ctrl.setHideBalances,
                  ),
                ),
                SettingsRow(
                  icon: Icons.cloud_upload_outlined,
                  iconTint: c.accent,
                  title: t('settings.data.backup'),
                  sub: t('settings.data.backupSub'),
                  onTap: () => showBackupSheet(context, ref),
                ),
                SettingsRow(
                  icon: Icons.settings_backup_restore,
                  iconTint: c.accent,
                  title: t('settings.data.restore'),
                  sub: t('settings.data.restoreSub'),
                  showDivider: false,
                  onTap: () => showRestoreSheet(context, ref),
                ),
              ],
            ),

            const SizedBox(height: 22),
            const AppVersionFooter(),
          ],
        ),
      ),
    );
  }
}

/// Children of the master switch: dimmed + inert while master is off, keeping
/// each child's own stored value intact.
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

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final m = t.minute.toString().padLeft(2, '0');
  final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$m $ap';
}

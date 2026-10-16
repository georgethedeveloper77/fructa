import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../core/widgets/rate_basis_toggle.dart';
import '../../data/pro/pro_providers.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../backup/backup_ui.dart';
import '../blog/blog_page.dart';
import '../learn/learn_home_page.dart';
import '../pro/pro_settings_group.dart';
import '../reports/report_notify.dart';
import '../reports/reports_page.dart';
import '../wrap/wrap_engine.dart';
import '../wrap/wrap_viewer.dart';
import 'following_page.dart';
import 'notifications_page.dart';
import 'widgets/app_version_footer.dart';
import 'widgets/appearance_section.dart';
import '../../data/drive_sync.dart';
import '../backup/drive_backup_page.dart';

/// The You tab. Membership first, then one row into every notification
/// switch, the user's reports, how the app looks, learning, privacy and
/// their data. Each group holds one kind of thing, so a setting is found by
/// what it is about rather than by remembering where it was put.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final prefs = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    // Live value the LockGate actually reads; the pref persists the choice.
    final lockOn = ref.watch(appLockProvider);
    final followCount = ref.watch(subscriptionsProvider).length;
    final cfg = ref.watch(remoteConfigProvider);
    final wrap = ref.watch(weeklyWrapProvider);
    final wrapNew = ref.watch(wrapUnseenProvider);
    final report = ref.watch(newReportProvider);

    void push(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 120),
          children: [
            DisplayHeader(title: t('nav.you'), sub: t('settings.sub')),
            const SizedBox(height: 18),

            // Membership: status, restore, manage. Renders nothing while the
            // `pro.enabled` remote flag is off.
            const ProSettingsGroup(),
            if (kDebugMode) const _DebugProSwitch(),

            SectionHeader(title: t('settings.notifications')),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.notifications_none,
                  iconTint: c.accent,
                  title: t('settings.notifications'),
                  sub: t(prefs.masterAlerts ? 'you.notif.on' : 'you.notif.off'),
                  onTap: () => push(const NotificationsPage()),
                ),
                SettingsRow(
                  icon: Icons.star_outline,
                  iconTint: c.accent,
                  title: t('you.following'),
                  sub: t(
                    followCount == 1 ? 'you.followingOne' : 'you.followingMany',
                    {'n': '$followCount'},
                  ),
                  showDivider: false,
                  onTap: () => push(const FollowingPage()),
                ),
              ],
            ),

            SectionHeader(title: t('reports.title')),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                if (wrap.market.isNotEmpty)
                  SettingsRow(
                    icon: Icons.play_circle_outline,
                    iconTint: c.accent,
                    title: t('you.wrap'),
                    sub: t('wrap.card.count', {'n': '${wrap.market.length}'}),
                    trailing: wrapNew ? const NewTag() : null,
                    onTap: () => openWeeklyWrap(context),
                  ),
                SettingsRow(
                  icon: Icons.summarize_outlined,
                  iconTint: c.accent,
                  title: t('reports.title'),
                  sub: report == null
                      ? t('reports.entrySub')
                      : t('reports.ready', {
                          'month': monthName(report.from).split(' ').first,
                        }),
                  trailing: report == null ? null : const NewTag(),
                  showDivider: false,
                  onTap: () => push(const ReportsPage()),
                ),
              ],
            ),

            SectionHeader(title: t('settings.appearance')),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: AppearanceSection(),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: SettingsRow(
                    icon: Icons.percent_rounded,
                    iconTint: c.accent,
                    title: t('you.basis'),
                    sub: t('you.basisSub'),
                    trailing: const RateBasisToggle(),
                    showDivider: false,
                  ),
                ),
              ],
            ),

            SectionHeader(title: t('settings.learn.title')),
            const SizedBox(height: 4),
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
                  onTap: () => push(const LearnHomePage()),
                ),
                SettingsRow(
                  icon: Icons.menu_book_outlined,
                  iconTint: c.accent,
                  title: t('settings.blog.title'),
                  sub: t('settings.blog.subtitle'),
                  showDivider: false,
                  onTap: () => push(const BlogPage()),
                ),
              ],
            ),

            SectionHeader(title: t('you.privacy')),
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
                      // set() persists to Hive and updates the live value.
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
                  showDivider: false,
                  trailing: fructaToggle(
                    value: prefs.hideBalances,
                    onChanged: ctrl.setHideBalances,
                  ),
                ),
              ],
            ),

            SectionHeader(title: t('you.data')),
            const SizedBox(height: 4),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.add_to_drive_rounded,
                  iconTint: c.accent,
                  title: t('drive.name'),
                  sub: ref.watch(driveStatusProvider).connected
                      ? t('drive.settingsOn', {
                          'when':
                              ref.watch(driveStatusProvider).lastBackup == null
                              ? t('drive.never')
                              : driveAgo(
                                  ref.watch(driveStatusProvider).lastBackup!,
                                ),
                        })
                      : t('drive.notConnected'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriveBackupPage()),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Text(
                t('you.dataNote'),
                style: TextStyle(color: c.faint, fontSize: 12, height: 1.45),
              ),
            ),

            const SizedBox(height: 22),
            const AppVersionFooter(),
          ],
        ),
      ),
    );
  }
}

/// Debug builds only: unlock Pro on this phone for testing.
class _DebugProSwitch extends ConsumerWidget {
  const _DebugProSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final on = ref.watch(debugProProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      // Material, not a coloured DecoratedBox: ListTile paints its ripple on
      // the nearest Material, which a coloured box above it would hide.
      child: Material(
        color: c.s1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: SwitchListTile.adaptive(
          value: on,
          activeTrackColor: c.accent,
          onChanged: (v) => ref.read(debugProProvider.notifier).set(v),
          title: Text(
            'Developer: Pro unlocked',
            style: TextStyle(
              color: c.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Debug builds only. Tests Pro screens without a purchase.',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

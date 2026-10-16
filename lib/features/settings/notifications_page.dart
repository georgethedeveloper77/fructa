import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/local_notify.dart';
import '../../core/push.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/smart_alert.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import '../learn/learn_progress.dart';
import '../learn/learn_reminder.dart';
import '../pro/pro_widgets.dart';
import '../wrap/wrap_engine.dart';

/// Every notification Fructa can send, in one place, grouped by what it is
/// about. The master switch dims and freezes everything under it while
/// keeping each switch's own value, so turning it back on restores the user's
/// choices rather than resetting them.
///
/// Pro types show a PRO badge to free users and open the paywall on tap;
/// subscribers just get the switch.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage>
    with WidgetsBindingObserver {
  bool _testSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the phone's settings may have changed the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  /// The master switch prompts for the OS permission and says so if the user
  /// declines, rather than leaving a green switch that means nothing.
  Future<void> _setMaster(bool on) async {
    final deliverable = await ref
        .read(settingsControllerProvider.notifier)
        .setMasterAlerts(on);
    if (!mounted) return;
    setState(() {});
    if (!on || deliverable) return;
    final c = context.c;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: c.s3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text(
            t('settings.notif.blocked'),
            style: TextStyle(color: c.text, fontSize: 13.5, height: 1.4),
          ),
        ),
      );
  }

  Future<void> _allow() async {
    await Push.promptPermission();
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    await LocalNotify.test();
    if (mounted) setState(() => _testSent = true);
  }

  /// The learn reminder is a ladder of dated notifications rebuilt from live
  /// progress, so the caller passes the content and progress it can reach.
  Future<void> _syncLearn() => syncLearnReminders(
    content: ref.read(learnProvider),
    progress: ref.read(learnProgressProvider),
    prefs: ref.read(learnReminderProvider),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final prefs = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final master = prefs.masterAlerts;
    final unlocked = ref.watch(wrapPersonalUnlockedProvider);
    final smart = ref.watch(smartAlertPrefsProvider);
    final reminder = ref.watch(learnReminderProvider);
    final blocked = master && !Push.permitted;

    Widget toggle(bool value, ValueChanged<bool> onChanged) =>
        fructaToggle(value: value, onChanged: onChanged);

    /// A Pro switch: the switch itself when unlocked, a PRO badge otherwise.
    SettingsRow pro({
      required IconData icon,
      required String title,
      String? sub,
      required bool value,
      required ValueChanged<bool> onChanged,
      bool last = false,
    }) => SettingsRow(
      icon: icon,
      iconTint: c.accent,
      title: title,
      sub: sub,
      showDivider: !last,
      trailing: unlocked ? toggle(value, onChanged) : const ProBadge(),
      onTap: unlocked
          ? null
          : () => openPaywall(context, source: 'notifications'),
    );

    SettingsRow smartRow(
      SmartAlertType type,
      IconData icon,
      String key, {
      bool last = false,
    }) => pro(
      icon: icon,
      title: t(key),
      value: smart[type] ?? true,
      onChanged: (v) => ref.read(smartAlertPrefsProvider.notifier).set(type, v),
      last: last,
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('settings.notifications'),
          style: TextStyle(
            color: c.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 48),
        children: [
          if (blocked) _Blocked(onAllow: _allow),

          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.notifications_none,
                iconTint: c.accent,
                title: t('notif.master'),
                sub: t('notif.masterSub'),
                showDivider: false,
                trailing: toggle(master, _setMaster),
              ),
            ],
          ),

          _Gated(
            enabled: master,
            child: Column(
              children: [
                _Heading(t('notif.rates')),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: Icons.trending_up,
                      iconTint: c.accent,
                      title: t('settings.notif.rateMoves'),
                      sub: t('settings.notif.rateMovesSub'),
                      trailing: toggle(prefs.rateMoves, ctrl.setRateMoves),
                    ),
                    SettingsRow(
                      icon: Icons.swap_horiz,
                      iconTint: c.accent,
                      title: t('settings.notif.saved'),
                      sub: t('notif.savedSub'),
                      trailing: toggle(
                        prefs.savedComparisons,
                        ctrl.setSavedComparisons,
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.paid_outlined,
                      iconTint: c.accent,
                      title: t('settings.notif.coupons'),
                      sub: t('settings.notif.couponsSub'),
                      showDivider: false,
                      trailing: toggle(
                        prefs.couponsMaturities,
                        ctrl.setCouponsMaturities,
                      ),
                    ),
                  ],
                ),

                _Heading(t('notif.stories')),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: Icons.play_circle_outline,
                      iconTint: c.accent,
                      title: t('notif.wrap'),
                      sub: t('notif.wrapSub'),
                      // Also mirrors the server digest tag, so one switch
                      // covers every weekly message.
                      trailing: toggle(
                        prefs.weeklyDigest,
                        ctrl.setWeeklyDigest,
                      ),
                    ),
                    SettingsRow(
                      icon: Icons.bar_chart_rounded,
                      iconTint: c.accent,
                      title: t('notif.fundStories'),
                      sub: t('notif.fundStoriesSub'),
                      trailing: toggle(prefs.fundStories, ctrl.setFundStories),
                    ),
                    pro(
                      icon: Icons.summarize_outlined,
                      title: t('notif.month'),
                      sub: t('notif.monthSub'),
                      value: prefs.monthlyReport,
                      onChanged: ctrl.setMonthlyReport,
                      last: true,
                    ),
                  ],
                ),
                _Foot(t('notif.storiesFoot')),

                _Heading(t('notif.money')),
                SettingsGroup(
                  children: [
                    smartRow(
                      SmartAlertType.underpaid,
                      Icons.fact_check_outlined,
                      'notif.underpaid',
                    ),
                    smartRow(
                      SmartAlertType.betterFund,
                      Icons.trending_up_rounded,
                      'notif.betterFund',
                    ),
                    smartRow(
                      SmartAlertType.rankDrop,
                      Icons.south_rounded,
                      'notif.rankDrop',
                    ),
                    smartRow(
                      SmartAlertType.noInterest,
                      Icons.do_not_disturb_on_outlined,
                      'notif.noInterest',
                    ),
                    pro(
                      icon: Icons.event_outlined,
                      title: t('notif.stmtDue'),
                      sub: t('notif.stmtDueSub'),
                      value: prefs.statementDue,
                      onChanged: ctrl.setStatementDue,
                      last: true,
                    ),
                  ],
                ),
              ],
            ),
          ),

          _Heading(t('settings.learn.title')),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.local_fire_department_outlined,
                iconTint: c.accent,
                title: t('notif.learn'),
                sub: t('notif.learnSub'),
                showDivider: reminder.enabled,
                trailing: toggle(reminder.enabled, (v) async {
                  await ref.read(learnReminderProvider.notifier).setEnabled(v);
                  await _syncLearn();
                }),
              ),
              if (reminder.enabled)
                SettingsRow(
                  icon: Icons.schedule,
                  iconTint: c.accent,
                  title: t('notif.learnTime'),
                  showDivider: false,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: reminder.time,
                    );
                    if (picked == null) return;
                    await ref
                        .read(learnReminderProvider.notifier)
                        .setTime(picked.hour, picked.minute);
                    await _syncLearn();
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmtTime(reminder.time),
                        style: fructaFonts.numeric(
                          color: c.accentInk,
                          size: 14,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Icon(Icons.chevron_right, color: c.faint, size: 18),
                    ],
                  ),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.text,
                backgroundColor: c.s1,
                side: BorderSide(color: c.line2),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _test,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(t('notif.test')),
            ),
          ),
          if (_testSent) _Foot(t('notif.testSent')),
        ],
      ),
    );
  }
}

/// Small caps heading over a group.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.c.muted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );
}

/// Faint note under a group.
class _Foot extends StatelessWidget {
  const _Foot(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
    child: Text(
      text,
      style: TextStyle(color: context.c.faint, fontSize: 12, height: 1.45),
    ),
  );
}

/// The phone itself is blocking Fructa, so no switch below can reach the user.
class _Blocked extends StatelessWidget {
  const _Blocked({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.downSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('notif.blocked.title'),
            style: TextStyle(
              color: c.down,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('notif.blocked.body'),
            style: TextStyle(color: c.text, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.text,
              foregroundColor: c.bg,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onAllow,
            child: Text(t('notif.blocked.allow')),
          ),
        ],
      ),
    );
  }
}

/// Children of the master switch: dimmed and inert while it is off, keeping
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

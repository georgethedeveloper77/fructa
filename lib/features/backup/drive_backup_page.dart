import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/settings_prefs.dart';
import '../../core/theme.dart';
import '../../core/widgets/fund_logo.dart';
import '../../data/backup_service.dart';
import '../../data/drive_backup_service.dart';
import '../../data/drive_sync.dart';
import '../../data/models/holding.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';
import 'backup_ui.dart';

/// "2 minutes ago", for the backup lines.
String driveAgo(DateTime at) {
  final s = DateTime.now().difference(at).inSeconds;
  if (s < 60) return t('drive.ago.now');
  if (s < 3600) return t('drive.ago.min', {'n': '${s ~/ 60}'});
  if (s < 86400) return t('drive.ago.hour', {'n': '${s ~/ 3600}'});
  return t('drive.ago.day', {'n': '${s ~/ 86400}'});
}

void _toast(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg)));

/// Connect Google Drive, then settle what is on the phone against what is in
/// Drive's Fructa folder:
///   nothing in Drive          back the phone up now
///   phone empty, Drive not    ask to restore it
///   both                      merge on their own; ask only when a fund was
///                             changed on both sides with no way to tell
///                             which is newer
Future<void> connectDrive(BuildContext context, WidgetRef ref) async {
  final svc = ref.read(driveBackupServiceProvider);
  final status = ref.read(driveStatusProvider.notifier);
  try {
    final email = await svc.connect();
    if (email == null) return;
    await status.connected(email);
    final found = await svc.restore(interactive: false);
    final phone = ref.read(holdingsProvider);
    if (!context.mounted) return;

    Future<void> backupNow() async {
      final at = await svc.backup(interactive: false);
      if (at != null) {
        await status.backedUp(at);
      }
    }

    Future<void> apply(List<Holding> items, DateTime? at) async {
      await ref.read(backupServiceProvider).applyRestore(items);
      ref.invalidate(holdingsProvider);
      if (at != null) {
        await status.backedUp(at);
      }
    }

    if (found == null || found.isEmpty) {
      if (phone.isNotEmpty) await backupNow();
      if (context.mounted) {
        _toast(context, t('drive.toast.connected'));
      }
      return;
    }

    if (phone.isEmpty) {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _FoundSheet(found: found),
      );
      if (ok == true) {
        await apply(found.holdings, found.modifiedAt);
        if (context.mounted) {
          _toast(
            context,
            t('backup.restored', {'n': '${found.holdings.length}'}),
          );
        }
      }
      return;
    }

    final plan = mergeBackup(phone, found.holdings);
    if (plan.conflicts.isEmpty) {
      if (plan.fromDrive == 0) {
        await backupNow();
        if (context.mounted) {
          _toast(context, t('drive.toast.phoneNewest'));
        }
      } else {
        await apply(plan.merged, null);
        await backupNow();
        if (context.mounted) {
          _toast(
            context,
            t('drive.toast.merged', {
              'drive': '${plan.fromDrive}',
              'phone': '${plan.keptPhone}',
            }),
          );
        }
      }
      return;
    }

    final keepDrive = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChooseSheet(phone: phone, drive: found),
    );
    if (keepDrive == null) return;
    await apply(keepDrive ? plan.preferDrive() : plan.merged, null);
    await backupNow();
    if (context.mounted) {
      _toast(context, t('drive.toast.done'));
    }
  } on DriveSignInFailed catch (e) {
    // Say what Google said, so a setup problem is visible, not silent.
    if (context.mounted) {
      _toast(context, t('drive.toast.signIn', {'why': '$e'}));
    }
  } catch (_) {
    if (context.mounted) {
      _toast(context, t('backup.driveFailed'));
    }
  }
}

/// You › Backup: Google Drive, connected or not, and the other ways to keep a
/// copy.
class DriveBackupPage extends ConsumerStatefulWidget {
  const DriveBackupPage({super.key});

  @override
  ConsumerState<DriveBackupPage> createState() => _DriveBackupPageState();
}

class _DriveBackupPageState extends ConsumerState<DriveBackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(driveStatusProvider);

    Widget fact(String k, Widget v) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: TextStyle(color: c.muted, fontSize: 11)),
            const SizedBox(height: 2),
            v,
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: c.bg.withValues(alpha: 0),
        foregroundColor: c.text,
        title: Text(
          t('drive.title'),
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: s.connected ? c.line : c.accent,
                width: s.connected ? 1 : 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const _DriveIcon(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('drive.name'),
                            style: TextStyle(
                              color: c.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            s.email ?? t('drive.notConnected'),
                            style: TextStyle(color: c.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (s.connected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.upSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 14, color: c.up),
                            const SizedBox(width: 4),
                            Text(
                              t('drive.connected'),
                              style: TextStyle(
                                color: c.up,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (s.connected) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      fact(
                        t('drive.last'),
                        Text(
                          s.lastBackup == null
                              ? t('drive.never')
                              : driveAgo(s.lastBackup!),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      fact(
                        t('drive.where'),
                        Row(
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 16,
                              color: c.accentInk,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t('drive.folder'),
                              style: TextStyle(
                                color: c.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: s.auto,
                    onChanged: (v) =>
                        ref.read(driveStatusProvider.notifier).setAuto(v),
                    title: Text(
                      t('drive.auto'),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      t('drive.autoSub'),
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final at = await ref
                                      .read(driveBackupServiceProvider)
                                      .backup();
                                  if (at != null) {
                                    await ref
                                        .read(driveStatusProvider.notifier)
                                        .backedUp(at);
                                    if (context.mounted) {
                                      _toast(
                                        context,
                                        t('backup.driveBackedUp'),
                                      );
                                    }
                                  }
                                }),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: c.text,
                            side: BorderSide(color: c.line2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(t('drive.now')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  await ref
                                      .read(driveBackupServiceProvider)
                                      .disconnect();
                                  await ref
                                      .read(driveStatusProvider.notifier)
                                      .disconnected();
                                }),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: c.down,
                            side: BorderSide(color: c.line2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(t('drive.disconnect')),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    t('drive.pitch'),
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => connectDrive(context, ref)),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(t('drive.connect')),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            child: Text(
              t('drive.other'),
              style: TextStyle(
                color: c.faint,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Material(
            color: c.s1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 58,
              leading: Icon(Icons.lock_outline_rounded, color: c.accentInk),
              title: Text(
                t('drive.file'),
                style: TextStyle(
                  color: c.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
              onTap: () => showBackupSheet(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriveIcon extends StatelessWidget {
  const _DriveIcon();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.add_to_drive_rounded, size: 20, color: c.accentInk),
    );
  }
}

/// Portfolio, under the total: a card to connect Drive, or once connected, one
/// line saying when the last backup landed.
class DriveBackupStrip extends ConsumerWidget {
  const DriveBackupStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    if (ref.watch(holdingsProvider).isEmpty) return const SizedBox.shrink();
    final s = ref.watch(driveStatusProvider);
    void open() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DriveBackupPage()));

    if (s.connected) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: c.upSoft,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: open,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: c.up),
                    const SizedBox(width: 6),
                    Text(
                      s.lastBackup == null
                          ? t('drive.strip.connected')
                          : t('drive.strip.backed', {
                              'when': driveAgo(s.lastBackup!),
                            }),
                      style: TextStyle(
                        color: c.up,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.accent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _DriveIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('drive.strip.title'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        t('drive.strip.sub'),
                        style: TextStyle(color: c.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => connectDrive(context, ref),
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(t('drive.connect')),
            ),
          ],
        ),
      ),
    );
  }
}

String _total(WidgetRef ref, List<Holding> items) {
  final kes = items
      .where((h) => h.currency == 'KES')
      .fold(0.0, (n, h) => n + h.balance);
  final hide = ref.read(settingsControllerProvider).hideBalances;
  return hide ? 'KES \u2022\u2022\u2022\u2022' : money('KES', kes);
}

String _dayMonth(DateTime d) {
  const m = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${d.day} ${m[d.month - 1]}';
}

/// New phone, empty: the backup found in Drive, and whether to restore it.
class _FoundSheet extends ConsumerWidget {
  const _FoundSheet({required this.found});

  final DriveRestore found;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final byId = ref.watch(fundsByIdProvider);
    final at = found.modifiedAt;
    final now = DateTime.now();
    final hide = ref.watch(settingsControllerProvider).hideBalances;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _DriveIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('drive.found.title'),
                        style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        at == null
                            ? t('drive.found.where')
                            : t('drive.found.whereWhen', {
                                'date': _dayMonth(at),
                              }),
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('drive.holdings', {
                            'n': '${found.holdings.length}',
                          }),
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                      ),
                      Text(
                        _total(ref, found.holdings),
                        style: fructaFonts.numeric(
                          color: c.text,
                          size: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final h in found.holdings.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          FundLogo(
                            domain: byId[h.fundId]?.logoDomain,
                            seed: byId[h.fundId]?.manager ?? h.fundId,
                            logoUrl: ref.watch(logoUrlProvider(h.fundId)),
                            brandColor: ref.watch(brandColorProvider(h.fundId)),
                            size: 28,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              byId[h.fundId]?.name ?? h.fundId,
                              style: TextStyle(color: c.text, fontSize: 14),
                            ),
                          ),
                          Text(
                            hide
                                ? '\u2022\u2022\u2022\u2022'
                                : money(h.currency, h.balance),
                            style: fructaFonts.numeric(
                              color: c.text,
                              size: 13.5,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (at != null &&
                (at.year != now.year || at.month != now.month)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  t('drive.found.since', {'date': _dayMonth(at)}),
                  style: TextStyle(color: c.accentInk, fontSize: 12.5),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: c.text,
                      side: BorderSide(color: c.line2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(t('drive.found.fresh')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.onAccent,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(t('drive.found.restore')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Both sides changed the same fund and nothing says which is newer: which
/// one the user wants. Everything else has already merged.
class _ChooseSheet extends ConsumerStatefulWidget {
  const _ChooseSheet({required this.phone, required this.drive});

  final List<Holding> phone;
  final DriveRestore drive;

  @override
  ConsumerState<_ChooseSheet> createState() => _ChooseSheetState();
}

class _ChooseSheetState extends ConsumerState<_ChooseSheet> {
  bool _drive = true;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget card(
      bool drive,
      IconData icon,
      String title,
      String when,
      List<Holding> items,
    ) {
      final on = _drive == drive;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _drive = drive),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.s1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: on ? c.accent : c.line,
                width: on ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: c.accentInk),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      on
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      size: 20,
                      color: on ? c.accent : c.line2,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(when, style: TextStyle(color: c.muted, fontSize: 12)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _total(ref, items),
                    style: fructaFonts.numeric(
                      color: c.text,
                      size: 19,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  t('drive.holdings', {'n': '${items.length}'}),
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final at = widget.drive.modifiedAt;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('drive.choose.title'),
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('drive.choose.sub'),
              style: TextStyle(color: c.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                card(
                  false,
                  Icons.smartphone_rounded,
                  t('drive.choose.phone'),
                  t('drive.choose.today'),
                  widget.phone,
                ),
                const SizedBox(width: 10),
                card(
                  true,
                  Icons.add_to_drive_rounded,
                  t('drive.choose.drive'),
                  at == null ? '' : _dayMonth(at),
                  widget.drive.holdings,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              t('drive.choose.note'),
              style: TextStyle(color: c.faint, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_drive),
              style: FilledButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.onAccent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                t(_drive ? 'drive.choose.keepDrive' : 'drive.choose.keepPhone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

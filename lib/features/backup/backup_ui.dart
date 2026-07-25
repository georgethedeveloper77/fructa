import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loader.dart';
import '../../data/backup_service.dart';
import '../../data/providers.dart';
import 'cloud_backup_ui.dart';

// ── Public entry points ─────────────────────────────────────────────────────

/// Run once when the main scaffold mounts: offer a restore if this device is
/// empty but a backup exists, then (Android) prompt for a store update.
Future<void> runLaunchTasks(BuildContext context, WidgetRef ref) async {
  if (ref.read(holdingsProvider).isEmpty) {
    final svc = ref.read(backupServiceProvider);
    final code = await svc.currentCode();
    if (code != null) {
      try {
        final r = await svc.restore(code);
        if (r != null && !r.isEmpty && context.mounted) {
          await _showFoundSheet(context, ref, r);
        }
      } catch (_) {/* offline or transient, stay silent */}
    }
  }
  if (context.mounted) await _maybePromptUpdate(context);
}

Future<void> showBackupSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BackupSheet(),
    );

Future<void> showRestoreSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RestoreSheet(),
    );

// ── Android in-app update ───────────────────────────────────────────────────

Future<void> _maybePromptUpdate(BuildContext context) async {
  if (!Platform.isAndroid) return; // iOS: the App Store handles updates
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UpdateSheet(),
    );
    if (go == true) {
      await InAppUpdate.startFlexibleUpdate(); // downloads in the background
      await InAppUpdate.completeFlexibleUpdate(); // installs on confirm
    }
  } catch (_) {/* not installed from Play, or offline, so ignore */}
}

// ── Shared chrome ───────────────────────────────────────────────────────────

Widget _grabber(BuildContext context) => Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: context.c.line2,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

Widget _primaryBtn(BuildContext context,
        {required String label, required VoidCallback? onTap, bool busy = false}) {
  final c = context.c;
  return SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.s3,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? AppLoader(wave: true, size: 20, color: c.onAccent)
          : Text(label),
    ),
  );
}

String _fmtWhen(DateTime? d) {
  if (d == null) return '';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${m[l.month - 1]} ${l.day}, $hh:$mm';
}

// ── Back up sheet (shows the recovery code) ─────────────────────────────────

class _BackupSheet extends ConsumerStatefulWidget {
  const _BackupSheet();
  @override
  ConsumerState<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<_BackupSheet> {
  String? _code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(backupServiceProvider).ensureCode().then((c) {
      if (mounted) setState(() => _code = c);
    });
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      final at = await ref.read(backupServiceProvider).backup();
      ref.read(lastBackupProvider.notifier).state = at;
      if (mounted) {
        _toast(context, t('backup.backedUp'));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _toast(context, t('backup.failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final last = ref.watch(lastBackupProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _grabber(context),
              Row(children: [
                Icon(Icons.cloud_upload_outlined, color: c.accent, size: 22),
              const SizedBox(width: 10),
              Text(t('settings.data.backup'),
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              t('backup.body'),
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _code ?? '\u2026',
                      style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5),
                    ),
                  ),
                  IconButton(
                    onPressed: _code == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _code!));
                            _toast(context, t('backup.codeCopied'));
                          },
                    icon: Icon(Icons.copy_rounded, color: c.muted, size: 20),
                  ),
                ],
              ),
            ),
            if (last != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.check_circle_outline, size: 14, color: c.up),
                const SizedBox(width: 6),
                Text(t('backup.lastBackup', {'when': _fmtWhen(last)}),
                    style: TextStyle(color: c.faint, fontSize: 11.5)),
              ]),
            ],
            const SizedBox(height: 18),
            _primaryBtn(context,
                label: t('backup.now'), onTap: _backupNow, busy: _busy),
            const CloudBackupSection(mode: CloudMode.backup),
          ],
          ),
        ),
      ),
    );
  }
}

// ── Restore-by-code sheet ───────────────────────────────────────────────────

class _RestoreSheet extends ConsumerStatefulWidget {
  const _RestoreSheet();
  @override
  ConsumerState<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends ConsumerState<_RestoreSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final code = _ctrl.text.trim();
    if (code.length < 12) {
      setState(() => _error = t('backup.codeTooShort'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = ref.read(backupServiceProvider);
      final r = await svc.restore(code);
      if (r == null || r.isEmpty) {
        setState(() => _error = t('backup.notFound'));
        return;
      }
      await svc.applyRestore(r.holdings);
      await svc.adoptCode(code);
      ref.invalidate(holdingsProvider);
      if (mounted) {
        _toast(context,
            t('backup.restored', {'n': '${r.holdings.length}'}));
        Navigator.of(context).pop();
      }
    } catch (_) {
      setState(() => _error = t('backup.restoreFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(context),
            Row(children: [
              Icon(Icons.settings_backup_restore, color: c.accent, size: 22),
              const SizedBox(width: 10),
              Text(t('settings.data.restore'),
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(t('backup.restoreBody'),
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 17,
                  letterSpacing: 1.2),
              decoration: InputDecoration(
                hintText: t('backup.codeHint'),
                hintStyle: TextStyle(color: c.faint),
                filled: true,
                fillColor: c.s2,
                errorText: _error,
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.line2)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.accent, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            _primaryBtn(context,
                label: t('backup.restore'), onTap: _restore, busy: _busy),
            const CloudBackupSection(mode: CloudMode.restore),
          ],
          ),
        ),
      ),
    );
  }
}

// ── Launch "backup found" sheet ─────────────────────────────────────────────

Future<void> _showFoundSheet(
    BuildContext context, WidgetRef ref, RestoreResult r) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final c = sheetCtx.c;
      var busy = false;
      return StatefulBuilder(builder: (sheetCtx, setSheet) {
        Future<void> doRestore() async {
          setSheet(() => busy = true);
          await ref.read(backupServiceProvider).applyRestore(r.holdings);
          ref.invalidate(holdingsProvider);
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        }

        final vars = {
          'n': '${r.holdings.length}',
          'when': _fmtWhen(r.updatedAt),
          if (r.deviceLabel != null) 'device': r.deviceLabel!,
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _grabber(sheetCtx),
                Row(children: [
                  Icon(Icons.cloud_done_outlined, color: c.accent, size: 22),
                  const SizedBox(width: 10),
                  Text(t('backup.foundTitle'),
                      style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(
                  t(
                    r.deviceLabel != null
                        ? 'backup.foundBodyFrom'
                        : 'backup.foundBody',
                    vars,
                  ),
                  style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 18),
                _primaryBtn(sheetCtx,
                    label: t('backup.restore'), onTap: doRestore, busy: busy),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed:
                        busy ? null : () => Navigator.of(sheetCtx).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: Text(t('common.notNow')),
                  ),
                ),
              ],
            ),
          ),
        );
      });
    },
  );
}

// ── Update sheet ────────────────────────────────────────────────────────────

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet();
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(context),
            Row(children: [
              Icon(Icons.system_update, color: c.accent, size: 22),
              const SizedBox(width: 10),
              Text(t('update.title'),
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              t('update.body'),
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            _primaryBtn(context,
                label: t('update.cta'),
                onTap: () => Navigator.of(context).pop(true)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: Text(t('common.later')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

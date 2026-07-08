import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../core/theme.dart';
import '../../data/backup_service.dart';
import '../../data/providers.dart';

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
      } catch (_) {/* offline / transient — silent */}
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
  } catch (_) {/* not installed from Play, or offline — ignore */}
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
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: c.onAccent))
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
        _toast(context, 'Backed up');
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _toast(context, "Couldn't back up — check your connection");
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(context),
            Row(children: [
              Icon(Icons.cloud_upload_outlined, color: c.accent, size: 22),
              const SizedBox(width: 10),
              Text('Back up portfolio',
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              'No account needed. Save this recovery code — it\u2019s the only '
              'way to restore on a new phone or after clearing app data.',
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
                            _toast(context, 'Code copied');
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
                Text('Last backup ${_fmtWhen(last)}',
                    style: TextStyle(color: c.faint, fontSize: 11.5)),
              ]),
            ],
            const SizedBox(height: 18),
            _primaryBtn(context,
                label: 'Back up now', onTap: _backupNow, busy: _busy),
          ],
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
      setState(() => _error = 'Enter your full recovery code');
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
        setState(() => _error = 'No backup found for that code');
        return;
      }
      await svc.applyRestore(r.holdings);
      await svc.adoptCode(code);
      ref.invalidate(holdingsProvider);
      if (mounted) {
        _toast(context, 'Restored ${r.holdings.length} holdings');
        Navigator.of(context).pop();
      }
    } catch (_) {
      setState(() => _error = "Couldn't restore — check your connection");
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grabber(context),
            Row(children: [
              Icon(Icons.settings_backup_restore, color: c.accent, size: 22),
              const SizedBox(width: 10),
              Text('Restore from backup',
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text('Enter the recovery code from your other device. This replaces '
                'whatever is on this phone.',
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
                hintText: 'AKB-XXXX-XXXX-XXXX-XXXX',
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
                label: 'Restore', onTap: _restore, busy: _busy),
          ],
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

        final where = r.deviceLabel != null ? ' from ${r.deviceLabel}' : '';
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
                  Text('Backup found',
                      style: TextStyle(
                          color: c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'A saved portfolio$where (${r.holdings.length} holdings, '
                  '${_fmtWhen(r.updatedAt)}) is linked to this device. Restore it?',
                  style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
                ),
                const SizedBox(height: 18),
                _primaryBtn(sheetCtx,
                    label: 'Restore', onTap: doRestore, busy: busy),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed:
                        busy ? null : () => Navigator.of(sheetCtx).pop(),
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Not now'),
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
              Text('Update available',
                  style: TextStyle(
                      color: c.text, fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              'A new version of fructa is ready. It downloads in the background '
              'and installs when you\u2019re done.',
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 18),
            _primaryBtn(context,
                label: 'Update',
                onTap: () => Navigator.of(context).pop(true)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Later'),
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

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loader.dart';
import '../../data/backup_service.dart';
import '../../data/drive_backup_service.dart';
import '../../data/portfolio_codec.dart';
import '../../data/providers.dart';

enum CloudMode { backup, restore }

/// The Google Drive + encrypted-file block shared by the backup and restore
/// sheets. It carries its own chrome so it can drop into either sheet without
/// reaching for that sheet's private helpers.
///
/// Drive is the same-account phone upgrade path (appDataFolder, private). The
/// encrypted file is the portable path: an AES-256-GCM blob keyed off the
/// recovery code, shared out through the OS sheet on backup and picked back on
/// restore. The file path needs no Google account at all.
class CloudBackupSection extends ConsumerStatefulWidget {
  const CloudBackupSection({super.key, required this.mode});

  final CloudMode mode;

  @override
  ConsumerState<CloudBackupSection> createState() => _CloudBackupSectionState();
}

class _CloudBackupSectionState extends ConsumerState<CloudBackupSection> {
  String? _email;
  bool _drive = false;
  bool _file = false;

  bool get _busy => _drive || _file;
  bool get _isBackup => widget.mode == CloudMode.backup;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(driveBackupServiceProvider);
    svc.isConnected().then((ok) {
      if (mounted && ok) setState(() => _email = svc.email);
    });
  }

  // Drive ----------------------------------------------------------------------

  Future<void> _connect() async {
    setState(() => _drive = true);
    try {
      final email = await ref.read(driveBackupServiceProvider).connect();
      if (mounted && email != null) setState(() => _email = email);
    } catch (_) {
      if (mounted) _toast(t('backup.driveFailed'));
    } finally {
      if (mounted) setState(() => _drive = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(driveBackupServiceProvider).disconnect();
    ref.read(lastDriveSyncProvider.notifier).state = null;
    if (mounted) setState(() => _email = null);
  }

  Future<void> _driveBackup() async {
    setState(() => _drive = true);
    try {
      final at = await ref.read(driveBackupServiceProvider).backup();
      if (at == null) return; // user backed out of the Google prompt
      ref.read(lastDriveSyncProvider.notifier).state = at;
      if (mounted) {
        setState(() => _email = ref.read(driveBackupServiceProvider).email);
        _toast(t('backup.driveBackedUp'));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _toast(t('backup.driveFailed'));
    } finally {
      if (mounted) setState(() => _drive = false);
    }
  }

  Future<void> _driveRestore() async {
    setState(() => _drive = true);
    try {
      final r = await ref.read(driveBackupServiceProvider).restore();
      if (r == null) {
        if (mounted) {
          setState(() => _email = ref.read(driveBackupServiceProvider).email);
          _toast(t('backup.driveNone'));
        }
        return;
      }
      await ref.read(backupServiceProvider).applyRestore(r.holdings);
      ref.invalidate(holdingsProvider);
      if (mounted) {
        _toast(t('backup.restored', {'n': '${r.holdings.length}'}));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _toast(t('backup.driveFailed'));
    } finally {
      if (mounted) setState(() => _drive = false);
    }
  }

  // Encrypted file -------------------------------------------------------------

  Future<void> _exportFile() async {
    setState(() => _file = true);
    try {
      final code = await ref.read(backupServiceProvider).ensureCode();
      final bytes = await PortfolioCodec.encodeEncrypted(
        ref.read(holdingsProvider),
        code,
      );
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final name =
          'fructa-backup-${now.year}-${_two(now.month)}-${_two(now.day)}.fructa';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/octet-stream')],
          text: t('backup.exportShareText'),
        ),
      );
    } catch (_) {
      if (mounted) _toast(t('backup.exportFailed'));
    } finally {
      if (mounted) setState(() => _file = false);
    }
  }

  Future<void> _importFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      if (mounted) _toast(t('backup.importBadFile'));
      return;
    }

    final stored = await ref.read(backupServiceProvider).currentCode();
    if (!mounted) return;
    final code = await _promptCode(initial: stored);
    if (code == null || code.isEmpty) return;

    setState(() => _file = true);
    try {
      final holdings = await PortfolioCodec.decodeEncrypted(bytes, code);
      await ref.read(backupServiceProvider).applyRestore(holdings);
      await ref.read(backupServiceProvider).adoptCode(code);
      ref.invalidate(holdingsProvider);
      if (mounted) {
        _toast(t('backup.restored', {'n': '${holdings.length}'}));
        Navigator.of(context).pop();
      }
    } on NotAFructaBackup {
      if (mounted) _toast(t('backup.importBadFile'));
    } on BadRecoveryCode {
      if (mounted) _toast(t('backup.importWrongCode'));
    } catch (_) {
      if (mounted) _toast(t('backup.restoreFailed'));
    } finally {
      if (mounted) setState(() => _file = false);
    }
  }

  Future<String?> _promptCode({String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (dctx) {
        final c = dctx.c;
        return AlertDialog(
          backgroundColor: c.s2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            t('backup.importCodeTitle'),
            style: TextStyle(
                color: c.text, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: ctrl,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 16,
                letterSpacing: 1.2),
            decoration: InputDecoration(
              hintText: t('backup.codeHint'),
              hintStyle: TextStyle(color: c.faint),
              filled: true,
              fillColor: c.s3,
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line2)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.accent, width: 1.5)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: Text(t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(ctrl.text.trim()),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: Text(t('backup.restore')),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return res;
  }

  // View -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final connected = _email != null;
    final sync = ref.watch(lastDriveSyncProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _divider(context, t('backup.orLabel')),
        const SizedBox(height: 16),

        // Google Drive
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.s2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cloud_outlined, color: c.accent, size: 20),
                const SizedBox(width: 10),
                Text(
                  t('backup.driveTitle'),
                  style: TextStyle(
                      color: c.text, fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ]),
              if (connected) ...[
                const SizedBox(height: 8),
                Text(
                  t('backup.driveConnected', {'email': _email!}),
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
                if (_isBackup && sync != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    t('backup.driveSynced', {'when': _fmtWhen(sync)}),
                    style: TextStyle(color: c.faint, fontSize: 11.5),
                  ),
                ],
                const SizedBox(height: 12),
                _outlinedBtn(
                  context,
                  icon: _isBackup
                      ? Icons.cloud_upload_outlined
                      : Icons.cloud_download_outlined,
                  label: _isBackup
                      ? t('backup.driveBackupNow')
                      : t('backup.driveRestore'),
                  busy: _drive,
                  onTap: _busy
                      ? null
                      : (_isBackup ? _driveBackup : _driveRestore),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _disconnect,
                    style: TextButton.styleFrom(
                      foregroundColor: c.faint,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(t('backup.driveDisconnect'),
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  _isBackup
                      ? t('backup.driveConnectBackupBody')
                      : t('backup.driveConnectRestoreBody'),
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 12),
                _outlinedBtn(
                  context,
                  icon: Icons.link,
                  label: t('backup.driveConnect'),
                  busy: _drive,
                  onTap: _busy ? null : _connect,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Encrypted file
        _outlinedBtn(
          context,
          icon: _isBackup
              ? Icons.ios_share
              : Icons.folder_open_outlined,
          label: _isBackup ? t('backup.exportFile') : t('backup.importFile'),
          busy: _file,
          onTap: _busy ? null : (_isBackup ? _exportFile : _importFile),
        ),
        const SizedBox(height: 6),
        Text(
          _isBackup ? t('backup.exportHint') : t('backup.importHint'),
          style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.5),
        ),
      ],
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}

// Shared bits ------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtWhen(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  return '${m[l.month - 1]} ${l.day}, ${_two(l.hour)}:${_two(l.minute)}';
}

Widget _divider(BuildContext context, String label) {
  final c = context.c;
  final line = Expanded(child: Divider(color: c.line2, height: 1));
  return Row(children: [
    line,
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        label,
        style: TextStyle(
            color: c.faint, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    ),
    line,
  ]);
}

Widget _outlinedBtn(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
  bool busy = false,
}) {
  final c = context.c;
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.line2),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: busy
          ? AppLoader(size: 18, color: c.accent)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: c.accent),
                const SizedBox(width: 8),
                Text(label),
              ],
            ),
    ),
  );
}

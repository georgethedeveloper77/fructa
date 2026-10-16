import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loader.dart';
import '../../data/backup_service.dart';
import '../../data/drive_sync.dart';
import '../../data/portfolio_codec.dart';
import '../../data/providers.dart';
import 'drive_backup_page.dart';

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
  bool _file = false;

  bool get _busy => _file;
  bool get _isBackup => widget.mode == CloudMode.backup;

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
    final picked = await FilePicker.pickFiles(type: FileType.any);
    if (picked.isEmpty) return;

    // readAsBytes() rather than withData + .bytes. Both of those are deprecated
    // precisely because withData eagerly loads the whole file into memory at
    // pick time, which is an out-of-memory risk on a large or malicious file,
    // and this is the one path in the app that accepts a file from outside it.
    // Reading here also means a pick the user cancels costs nothing.
    Uint8List? bytes;
    try {
      bytes = await picked.single.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            t('backup.importCodeTitle'),
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              hintText: t('backup.codeHint'),
              hintStyle: TextStyle(color: c.faint),
              filled: true,
              fillColor: c.s3,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.accent, width: 1.5),
              ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _divider(context, t('backup.orLabel')),
        const SizedBox(height: 16),

        // Google Drive lives on its own page now; this row says whether it
        // is connected and goes there.
        Consumer(
          builder: (context, ref, _) {
            final drive = ref.watch(driveStatusProvider);
            return Material(
              color: c.s2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.line2),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                minTileHeight: 56,
                leading: Icon(Icons.add_to_drive_rounded, color: c.accent),
                title: Text(
                  t('drive.name'),
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  drive.connected
                      ? t('drive.connected')
                      : t('drive.notConnected'),
                  style: TextStyle(
                    color: drive.connected ? c.up : c.muted,
                    fontSize: 12.5,
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DriveBackupPage()),
                  );
                },
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // Encrypted file
        _outlinedBtn(
          context,
          icon: _isBackup ? Icons.ios_share : Icons.folder_open_outlined,
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

Widget _divider(BuildContext context, String label) {
  final c = context.c;
  final line = Expanded(child: Divider(color: c.line2, height: 1));
  return Row(
    children: [
      line,
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          style: TextStyle(
            color: c.faint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      line,
    ],
  );
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

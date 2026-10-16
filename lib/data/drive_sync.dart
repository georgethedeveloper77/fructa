import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'drive_backup_service.dart';
import 'models/holding.dart';
import 'providers.dart';

/// Whether Google Drive is connected, as whom, when the last backup landed,
/// and whether backups run on their own. Kept on the phone, so the Backup
/// screen and Portfolio can say "Connected" at once, without a network call.
class DriveStatus {
  const DriveStatus({this.email, this.lastBackup, this.auto = true});

  final String? email;
  final DateTime? lastBackup;
  final bool auto;

  bool get connected => email != null;
}

class DriveStatusNotifier extends Notifier<DriveStatus> {
  Box get _box => Hive.box('settings');

  @override
  DriveStatus build() => DriveStatus(
    email: _box.get('drive_email') as String?,
    lastBackup: DateTime.tryParse('${_box.get('drive_last') ?? ''}'),
    auto: (_box.get('drive_auto') as bool?) ?? true,
  );

  Future<void> connected(String email) async {
    await _box.put('drive_email', email);
    state = DriveStatus(
      email: email,
      lastBackup: state.lastBackup,
      auto: state.auto,
    );
  }

  Future<void> backedUp(DateTime at) async {
    await _box.put('drive_last', at.toIso8601String());
    state = DriveStatus(email: state.email, lastBackup: at, auto: state.auto);
  }

  Future<void> setAuto(bool on) async {
    await _box.put('drive_auto', on);
    state = DriveStatus(
      email: state.email,
      lastBackup: state.lastBackup,
      auto: on,
    );
  }

  Future<void> disconnected() async {
    await _box.delete('drive_email');
    await _box.delete('drive_last');
    state = DriveStatus(auto: state.auto);
  }
}

final driveStatusProvider = NotifierProvider<DriveStatusNotifier, DriveStatus>(
  DriveStatusNotifier.new,
);

/// Backs up on its own while Drive is connected and automatic backup is on:
/// a few seconds after any change to the holdings, and once a day when the
/// app opens. Each backup replaces the last. Silent: it never shows a Google
/// prompt, so a lapsed sign-in simply waits for the user to reconnect.
final driveAutoBackupProvider = Provider<void>((ref) {
  Timer? debounce;
  var running = false;

  Future<void> run() async {
    final s = ref.read(driveStatusProvider);
    if (!s.connected || !s.auto || running) return;
    running = true;
    try {
      final at = await ref
          .read(driveBackupServiceProvider)
          .backup(interactive: false);
      if (at != null) await ref.read(driveStatusProvider.notifier).backedUp(at);
    } catch (_) {
      // Offline or Drive unavailable: the next change or the next day retries.
    } finally {
      running = false;
    }
  }

  ref.listen(holdingsProvider, (prev, next) {
    if (prev == null) return;
    debounce?.cancel();
    debounce = Timer(const Duration(seconds: 4), run);
  });

  final last = ref.read(driveStatusProvider).lastBackup;
  if (last == null || DateTime.now().difference(last).inHours >= 24) {
    Future<void>.delayed(const Duration(seconds: 6), run);
  }
  ref.onDispose(() => debounce?.cancel());
});

// ── Merging a backup into the phone ─────────────────────────────────────────

/// The result of laying a Drive backup over what is on the phone. Holdings
/// only one side has are kept; for a fund both have, the one with the newer
/// activity wins. Only a fund both have, changed on both sides with nothing
/// to tell which is newer, needs the user.
class DriveMerge {
  const DriveMerge({
    required this.merged,
    required this.fromDrive,
    required this.keptPhone,
    required this.conflicts,
  });

  /// Everything, with each conflict resolved towards the phone.
  final List<Holding> merged;

  /// Holdings the backup adds or updates.
  final int fromDrive;

  /// Holdings only the phone has, kept.
  final int keptPhone;

  /// Funds changed on both sides with no way to tell which is newer, as
  /// (phone, drive).
  final List<(Holding, Holding)> conflicts;

  /// [merged] with every conflict resolved towards the backup instead.
  List<Holding> preferDrive() {
    final drive = {for (final c in conflicts) _key(c.$2): c.$2};
    return [for (final h in merged) drive[_key(h)] ?? h];
  }
}

String _key(Holding h) => '${h.kind.name}:${h.fundId}';

/// The last time anything happened to a holding: opened, a transaction, or a
/// statement-confirmed balance.
DateTime _lastActivity(Holding h) {
  var at = h.openedAt;
  for (final t in h.transactions) {
    if (t.date.isAfter(at)) at = t.date;
  }
  final a = h.anchor;
  if (a != null && a.date.isAfter(at)) at = a.date;
  return at;
}

DriveMerge mergeBackup(List<Holding> phone, List<Holding> drive) {
  final byPhone = {for (final h in phone) _key(h): h};
  final byDrive = {for (final h in drive) _key(h): h};
  final out = <Holding>[];
  final conflicts = <(Holding, Holding)>[];
  var fromDrive = 0;
  var keptPhone = 0;

  for (final k in {...byPhone.keys, ...byDrive.keys}) {
    final p = byPhone[k];
    final d = byDrive[k];
    if (p == null) {
      out.add(d!);
      fromDrive++;
      continue;
    }
    if (d == null) {
      out.add(p);
      keptPhone++;
      continue;
    }
    if (jsonEncode(p.toMap()) == jsonEncode(d.toMap())) {
      out.add(p);
      continue;
    }
    final lp = _lastActivity(p);
    final ld = _lastActivity(d);
    if (ld.isAfter(lp)) {
      out.add(d);
      fromDrive++;
    } else if (lp.isAfter(ld)) {
      out.add(p);
    } else if (d.transactions.length != p.transactions.length) {
      // Same last date, but one side recorded more: that one is fuller.
      final drive = d.transactions.length > p.transactions.length;
      out.add(drive ? d : p);
      if (drive) fromDrive++;
    } else {
      out.add(p);
      conflicts.add((p, d));
    }
  }
  return DriveMerge(
    merged: out,
    fromDrive: fromDrive,
    keptPhone: keptPhone,
    conflicts: conflicts,
  );
}

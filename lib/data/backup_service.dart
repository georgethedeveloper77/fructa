import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'models/holding.dart';
import 'providers.dart';
import 'repositories/holdings_repository.dart';

/// Result of a restore lookup.
class RestoreResult {
  final List<Holding> holdings;
  final DateTime? updatedAt;
  final String? deviceLabel;
  const RestoreResult(this.holdings, this.updatedAt, this.deviceLabel);
  bool get isEmpty => holdings.isEmpty;
}

/// No-login portfolio backup. The user's device holds a high-entropy recovery
/// code (secure storage); backups are stored server-side keyed by a hash of it
/// via the `portfolio-backup` / `portfolio-restore` edge functions. The code is
/// the capability — it restores on any device and survives a data wipe, which a
/// per-device anonymous session does not.
class BackupService {
  BackupService(this._holdings, this._store);

  final HoldingsRepository _holdings;
  final FlutterSecureStorage _store;

  static const _codeKey = 'fructa_recovery_code';
  static const _schema = 1;

  static const _headers = {
    'Content-Type': 'application/json',
    'apikey': Config.anonKey,
    'Authorization': 'Bearer ${Config.anonKey}',
  };

  // Confusable-free alphabet (no 0/O/1/I/L). 4 groups of 4 ≈ 78 bits.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  Future<String?> currentCode() => _store.read(key: _codeKey);

  /// The stored code, generating and persisting one on first use.
  Future<String> ensureCode() async {
    final existing = await _store.read(key: _codeKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final code = _generateCode();
    await _store.write(key: _codeKey, value: code);
    return code;
  }

  /// Adopt a code from another device (restore-by-code), so subsequent backups
  /// continue writing to the same slot.
  Future<void> adoptCode(String code) =>
      _store.write(key: _codeKey, value: code.trim().toUpperCase());

  String _generateCode() {
    final rnd = Random.secure();
    String grp() => List.generate(
        4, (_) => _alphabet[rnd.nextInt(_alphabet.length)]).join();
    return 'AKB-${grp()}-${grp()}-${grp()}-${grp()}';
  }

  String get _device => Platform.operatingSystem; // 'android' | 'ios'

  /// Push the current portfolio to the cloud under the device's code.
  /// Returns the server timestamp on success.
  Future<DateTime?> backup() async {
    final code = await ensureCode();
    final items = _holdings.all().map((h) => h.toMap()).toList();
    final res = await http.post(
      Uri.parse('${Config.functionsBase}/portfolio-backup'),
      headers: _headers,
      body: jsonEncode({
        'code': code,
        'device': _device,
        'schema': _schema,
        'data': {'schema': _schema, 'holdings': items},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('backup HTTP ${res.statusCode}');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime.tryParse((m['updated_at'] ?? '') as String);
  }

  /// Look up a backup for [code]. Null when none exists.
  Future<RestoreResult?> restore(String code) async {
    final res = await http.post(
      Uri.parse('${Config.functionsBase}/portfolio-restore'),
      headers: _headers,
      body: jsonEncode({'code': code.trim().toUpperCase()}),
    );
    if (res.statusCode != 200) {
      throw Exception('restore HTTP ${res.statusCode}');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    if (m['found'] != true) return null;
    final data = (m['data'] as Map).cast<String, dynamic>();
    final holdings = ((data['holdings'] as List?) ?? const [])
        .map((e) => Holding.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
    return RestoreResult(
      holdings,
      DateTime.tryParse((m['updated_at'] ?? '') as String),
      m['device_label'] as String?,
    );
  }

  /// Write a restored set into local storage (authoritative replace).
  Future<void> applyRestore(List<Holding> items) =>
      _holdings.importAll(items);
}

final _secureStorageProvider =
    Provider<FlutterSecureStorage>((_) => const FlutterSecureStorage());

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      ref.read(holdingsRepositoryProvider),
      ref.read(_secureStorageProvider),
    ));

/// Last successful cloud backup time (session state; drives the Settings line).
final lastBackupProvider = StateProvider<DateTime?>((ref) => null);

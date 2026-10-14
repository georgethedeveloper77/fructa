import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../../engine/statement/statement_model.dart';

/// A checked statement, kept on the device.
///
/// The full lines are stored, not just the result, so a statement can be
/// re-analysed when Fructa's published-rate history fills in or the analysis
/// improves, and so two statements can be compared line by line.
class SavedStatement {
  const SavedStatement({
    required this.id,
    required this.data,
    required this.checkedAt,
    this.fundId,
  });

  /// `<manager>|<account>|<last day>`: the same statement checked twice is one
  /// entry, a newer statement for the same account is another.
  final String id;
  final StatementData data;
  final DateTime checkedAt;

  /// The fund this statement was matched to, when known.
  final String? fundId;

  static String idFor(StatementData d) =>
      '${d.managerKey}|${d.accountNo ?? '?'}|${d.to.toIso8601String().substring(0, 10)}';

  Map<String, dynamic> toMap() => {
    'id': id,
    'checkedAt': checkedAt.toIso8601String(),
    'fundId': fundId,
    'managerKey': data.managerKey,
    'managerName': data.managerName,
    'currency': data.currency,
    'accountNo': data.accountNo,
    'memberNo': data.memberNo,
    'statementDate': data.statementDate?.toIso8601String(),
    'printedTotals': data.printedTotals,
    'warnings': data.warnings,
    'entries': [
      for (final e in data.entries)
        {
          'ref': e.ref,
          'date': e.date.toIso8601String(),
          'desc': e.description,
          'kind': e.kind.name,
          'amount': e.amount,
          'tax': e.tax,
          'balance': e.balance,
        },
    ],
  };

  static SavedStatement fromMap(Map m) => SavedStatement(
    id: m['id'] as String,
    checkedAt: DateTime.parse(m['checkedAt'] as String),
    fundId: m['fundId'] as String?,
    data: StatementData(
      managerKey: m['managerKey'] as String,
      managerName: (m['managerName'] as String?) ?? '',
      currency: (m['currency'] as String?) ?? 'KES',
      accountNo: m['accountNo'] as String?,
      memberNo: m['memberNo'] as String?,
      statementDate: m['statementDate'] == null
          ? null
          : DateTime.parse(m['statementDate'] as String),
      printedTotals: (m['printedTotals'] as List?)
          ?.map((x) => (x as num).toDouble())
          .toList(),
      warnings: ((m['warnings'] as List?) ?? const []).cast<String>(),
      entries: [
        for (final e in (m['entries'] as List))
          StatementEntry(
            ref: e['ref'] as String,
            date: DateTime.parse(e['date'] as String),
            description: (e['desc'] as String?) ?? '',
            kind: StatementEntryKind.values.byName(e['kind'] as String),
            amount: (e['amount'] as num).toDouble(),
            tax: (e['tax'] as num).toDouble(),
            balance: (e['balance'] as num).toDouble(),
          ),
      ],
    ),
  );
}

/// Checked statements, newest statement period first. Stored as JSON strings
/// in their own Hive box, opened on first use, so nothing changes at startup.
class StatementsNotifier extends AsyncNotifier<List<SavedStatement>> {
  static const _boxName = 'statements';

  Future<Box> _box() => Hive.isBoxOpen(_boxName)
      ? Future.value(Hive.box(_boxName))
      : Hive.openBox(_boxName);

  @override
  Future<List<SavedStatement>> build() async {
    final box = await _box();
    final out = <SavedStatement>[];
    for (final v in box.values) {
      try {
        out.add(SavedStatement.fromMap(jsonDecode(v as String) as Map));
      } catch (_) {
        // A corrupt entry is skipped rather than breaking the whole list.
      }
    }
    out.sort((a, b) => b.data.to.compareTo(a.data.to));
    return out;
  }

  Future<SavedStatement> save(StatementData d, {String? fundId}) async {
    final box = await _box();
    final s = SavedStatement(
      id: SavedStatement.idFor(d),
      data: d,
      checkedAt: DateTime.now(),
      fundId: fundId,
    );
    await box.put(s.id, jsonEncode(s.toMap()));
    ref.invalidateSelf();
    return s;
  }

  Future<void> setFund(String id, String fundId) async {
    final box = await _box();
    final raw = box.get(id);
    if (raw == null) return;
    final m = (jsonDecode(raw as String) as Map).cast<String, dynamic>();
    m['fundId'] = fundId;
    await box.put(id, jsonEncode(m));
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final box = await _box();
    await box.delete(id);
    ref.invalidateSelf();
  }
}

final statementsProvider =
    AsyncNotifierProvider<StatementsNotifier, List<SavedStatement>>(
      StatementsNotifier.new,
    );

/// Statement passwords, per manager, in the platform keychain / keystore.
/// Never in Hive, never in backups, never sent anywhere.
abstract final class StatementPasswords {
  static const _store = FlutterSecureStorage();
  static String _key(String managerKey) => 'stmt_pw_$managerKey';
  static const _index = 'stmt_pw_index';

  /// Every remembered password, most recent manager first. Tried in order on
  /// a locked file before the user is asked.
  static Future<List<String>> all() async {
    final idx = await _store.read(key: _index);
    final keys = idx == null ? <String>[] : idx.split(',');
    final out = <String>[];
    for (final k in keys) {
      final v = await _store.read(key: _key(k));
      if (v != null && !out.contains(v)) out.add(v);
    }
    return out;
  }

  static Future<List<String>> managers() async {
    final idx = await _store.read(key: _index);
    return idx == null || idx.isEmpty ? const [] : idx.split(',');
  }

  static Future<void> remember(String managerKey, String password) async {
    await _store.write(key: _key(managerKey), value: password);
    final keys = [
      managerKey,
      ...(await managers()).where((k) => k != managerKey),
    ];
    await _store.write(key: _index, value: keys.join(','));
  }

  static Future<void> forget(String managerKey) async {
    await _store.delete(key: _key(managerKey));
    final keys = (await managers()).where((k) => k != managerKey).join(',');
    await _store.write(key: _index, value: keys);
  }
}

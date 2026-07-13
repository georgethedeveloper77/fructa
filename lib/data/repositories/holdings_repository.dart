import 'package:hive/hive.dart';

import '../models/holding.dart';

// On-device holdings (Hive). Keyed by the subject id  one holding per fund or
// SACCO; deposits and withdrawals are recorded as transactions.
//
// The key stays the bare id (not 'sacco:<id>') so every holding already written
// to an installed device keeps resolving. `Holding.kind` carries the table.
class HoldingsRepository {
  final Box box;
  HoldingsRepository(this.box);

  List<Holding> all() => box.values
      .map((v) => Holding.fromMap(Map<String, dynamic>.from(v as Map)))
      .toList();

  Holding? byFund(String fundId) {
    final v = box.get(fundId);
    return v == null
        ? null
        : Holding.fromMap(Map<String, dynamic>.from(v as Map));
  }

  /// [kind] is only consulted when the holding is NEW. On an edit the existing
  /// kind is preserved: a holding cannot change what it is held in, and reading
  /// the caller's argument on every save is how a stray default silently
  /// rewrites a SACCO into a fund.
  Future<void> setBalance(
    String fundId,
    String currency,
    double newBalance, {
    HoldingKind kind = HoldingKind.fund,
  }) async {
    final now = DateTime.now();
    final existing = byFund(fundId);
    if (existing == null) {
      await box.put(
        fundId,
        Holding(
          fundId: fundId,
          kind: kind,
          balance: newBalance,
          currency: currency,
          openedAt: now,
          transactions: [Txn(amount: newBalance, type: 'deposit', date: now)],
        ).toMap(),
      );
    } else {
      final delta = newBalance - existing.balance;
      await box.put(
        fundId,
        Holding(
          fundId: fundId,
          kind: existing.kind,
          balance: newBalance,
          currency: currency,
          openedAt: existing.openedAt,
          transactions: [
            ...existing.transactions,
            Txn(
              amount: delta,
              type: delta >= 0 ? 'deposit' : 'withdrawal',
              date: now,
            ),
          ],
        ).toMap(),
      );
    }
  }

  Future<void> remove(String fundId) => box.delete(fundId);

  /// Replace all holdings with a restored set (backup restore). Clears first so
  /// a restore is authoritative, not a merge.
  Future<void> importAll(List<Holding> items) async {
    await box.clear();
    for (final h in items) {
      await box.put(h.fundId, h.toMap());
    }
  }
}

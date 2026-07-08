import 'package:hive/hive.dart';

import '../models/holding.dart';

// On-device holdings (Hive). Keyed by fundId  one holding per fund; deposits
// and withdrawals are recorded as transactions.
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

  Future<void> setBalance(
    String fundId,
    String currency,
    double newBalance,
  ) async {
    final now = DateTime.now();
    final existing = byFund(fundId);
    if (existing == null) {
      await box.put(
        fundId,
        Holding(
          fundId: fundId,
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

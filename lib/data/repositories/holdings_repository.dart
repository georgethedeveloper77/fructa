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
          anchor: existing.anchor,
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

  /// Records a dated deposit (positive) or withdrawal (negative) on an
  /// existing holding. The balance moves by the amount and the ledger stays in
  /// date order, so valuation accrues each lot from its own day. Returns false
  /// when there is no such holding or a withdrawal exceeds the balance.
  Future<bool> addTxn(String fundId, double amount, DateTime date) async {
    final h = byFund(fundId);
    if (h == null || amount == 0) return false;
    if (amount < 0 && -amount > h.balance + 0.005) return false;
    final txns = [
      ...h.transactions,
      Txn(
        amount: amount,
        type: amount >= 0 ? 'deposit' : 'withdrawal',
        date: date,
      ),
    ]..sort((a, b) => a.date.compareTo(b.date));
    await box.put(
      fundId,
      h.copyWith(balance: h.balance + amount, transactions: txns).toMap(),
    );
    return true;
  }

  /// Deletes one ledger entry and reverses its effect on the balance. Only
  /// entries the user typed can be removed; statement lines are owned by the
  /// statement and change only when a newer statement is matched.
  Future<void> removeTxn(String fundId, Txn txn) async {
    final h = byFund(fundId);
    if (h == null || txn.fromStatement) return;
    final i = h.transactions.indexWhere(
      (t) =>
          t.date == txn.date &&
          t.amount == txn.amount &&
          t.source == txn.source,
    );
    if (i < 0) return;
    final txns = [...h.transactions]..removeAt(i);
    await box.put(
      fundId,
      h.copyWith(balance: h.balance - txn.amount, transactions: txns).toMap(),
    );
  }

  /// Makes a statement the source of truth for a holding, creating the holding
  /// when it does not exist yet.
  ///
  /// [flows] are the statement's deposits and withdrawals (interest is not a
  /// flow: it is what the anchor balance already contains). Statement lines
  /// replace any earlier statement lines; the user's own entries are kept only
  /// when [keepYourEntries] is true and they fall AFTER the statement's last
  /// day, because anything before it is covered by the statement.
  Future<void> applyStatement({
    required String fundId,
    required String currency,
    required HoldingKind kind,
    required List<Txn> flows,
    required BalanceAnchor anchor,
    bool keepYourEntries = true,
  }) async {
    final h = byFund(fundId);
    final yours = keepYourEntries && h != null
        ? h.transactions
              .where((t) => !t.fromStatement && t.date.isAfter(anchor.date))
              .toList()
        : const <Txn>[];
    final txns = [...flows, ...yours]..sort((a, b) => a.date.compareTo(b.date));
    final principal = txns.fold(0.0, (s, t) => s + t.amount);
    final opened = txns.isEmpty ? anchor.date : txns.first.date;
    final next = Holding(
      fundId: fundId,
      kind: h?.kind ?? kind,
      currency: currency,
      // `balance` is cost basis (money in minus money out), as everywhere else.
      balance: principal < 0 ? 0 : principal,
      openedAt: opened,
      transactions: txns,
      anchor: anchor,
    );
    await box.put(fundId, next.toMap());
  }

  /// Drops the statement anchor so the holding is estimated again.
  Future<void> clearAnchor(String fundId) async {
    final h = byFund(fundId);
    if (h == null) return;
    await box.put(fundId, h.copyWith(clearAnchor: true).toMap());
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

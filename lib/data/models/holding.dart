class Txn {
  final double amount; // + deposit, - withdrawal
  final String type; // 'deposit' | 'withdrawal'
  final DateTime date;
  const Txn({required this.amount, required this.type, required this.date});

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'type': type,
    'date': date.toIso8601String(),
  };

  factory Txn.fromMap(Map m) => Txn(
    amount: (m['amount'] as num).toDouble(),
    type: m['type'] as String,
    date: DateTime.parse(m['date'] as String),
  );
}

/// What a holding is held IN. The id alone cannot tell you.
///
/// Fund ids and SACCO ids are both slugs living in different tables, so one
/// id-keyed box cannot distinguish them, and a collision would not throw: it
/// would quietly value someone's SACCO savings at some unrelated fund's rate.
/// This is the same reasoning that gave stock follows their own namespace in
/// providers.dart, and it is worth four lines here for the same reason.
enum HoldingKind { fund, sacco }

class Holding {
  /// The id of the thing held. Still named `fundId` because it is the Hive key
  /// on every holding already written to every installed device, and renaming
  /// it would orphan them. Read it as "subject id"; [kind] says which table.
  final String fundId;
  final HoldingKind kind;
  final double balance;
  final String currency;
  final DateTime openedAt;
  final List<Txn> transactions;

  const Holding({
    required this.fundId,
    required this.balance,
    required this.currency,
    required this.openedAt,
    this.kind = HoldingKind.fund,
    this.transactions = const [],
  });

  bool get isSacco => kind == HoldingKind.sacco;

  Map<String, dynamic> toMap() => {
    'fundId': fundId,
    'kind': kind.name,
    'balance': balance,
    'currency': currency,
    'openedAt': openedAt.toIso8601String(),
    'transactions': transactions.map((t) => t.toMap()).toList(),
  };

  /// A holding written before this field existed has no `kind` key. It defaults
  /// to `fund`, which is what every one of them is, so the box migrates itself
  /// on read and nothing on an installed device needs rewriting.
  factory Holding.fromMap(Map m) => Holding(
    fundId: m['fundId'] as String,
    kind: (m['kind'] as String?) == 'sacco'
        ? HoldingKind.sacco
        : HoldingKind.fund,
    balance: (m['balance'] as num).toDouble(),
    currency: m['currency'] as String,
    openedAt: DateTime.parse(m['openedAt'] as String),
    transactions: ((m['transactions'] as List?) ?? const [])
        .map((e) => Txn.fromMap(e as Map))
        .toList(),
  );
}

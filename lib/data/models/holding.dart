/// One money movement on a holding.
class Txn {
  final double amount; // + deposit, - withdrawal
  final String type; // 'deposit' | 'withdrawal'
  final DateTime date;

  /// Who recorded it: 'you' (entered in the app) or 'statement' (read from a
  /// manager's statement). Older entries have none and read as 'you'.
  final String source;

  /// The manager's transaction number for statement lines, so a line already
  /// imported is recognised when the next statement repeats it.
  final String? ref;

  const Txn({
    required this.amount,
    required this.type,
    required this.date,
    this.source = 'you',
    this.ref,
  });

  bool get isWithdrawal => amount < 0;
  bool get fromStatement => source == 'statement';

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'type': type,
    'date': date.toIso8601String(),
    'source': source,
    if (ref != null) 'ref': ref,
  };

  factory Txn.fromMap(Map m) => Txn(
    amount: (m['amount'] as num).toDouble(),
    type: m['type'] as String,
    date: DateTime.parse(m['date'] as String),
    source: (m['source'] as String?) ?? 'you',
    ref: m['ref'] as String?,
  );
}

/// A balance confirmed by a manager's statement on a given day.
///
/// When present, valuation starts from this known balance instead of
/// re-accruing every deposit from scratch, so a holding matched to a statement
/// shows what the manager says, not Fructa's estimate.
class BalanceAnchor {
  final double balance;
  final DateTime date;

  /// Short human label, e.g. "Lofty-Corban statement, 30 Sep 2026".
  final String label;

  const BalanceAnchor({
    required this.balance,
    required this.date,
    required this.label,
  });

  Map<String, dynamic> toMap() => {
    'balance': balance,
    'date': date.toIso8601String(),
    'label': label,
  };

  static BalanceAnchor? fromMap(Object? m) {
    if (m is! Map) return null;
    return BalanceAnchor(
      balance: (m['balance'] as num).toDouble(),
      date: DateTime.parse(m['date'] as String),
      label: (m['label'] as String?) ?? '',
    );
  }
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

  /// Last statement-confirmed balance, or null when the holding is estimated.
  final BalanceAnchor? anchor;

  const Holding({
    required this.fundId,
    required this.balance,
    required this.currency,
    required this.openedAt,
    this.kind = HoldingKind.fund,
    this.transactions = const [],
    this.anchor,
  });

  bool get isSacco => kind == HoldingKind.sacco;

  /// Confirmed by a statement.
  bool get isVerified => anchor != null;

  Holding copyWith({
    double? balance,
    DateTime? openedAt,
    List<Txn>? transactions,
    BalanceAnchor? anchor,
    bool clearAnchor = false,
  }) => Holding(
    fundId: fundId,
    kind: kind,
    balance: balance ?? this.balance,
    currency: currency,
    openedAt: openedAt ?? this.openedAt,
    transactions: transactions ?? this.transactions,
    anchor: clearAnchor ? null : (anchor ?? this.anchor),
  );

  Map<String, dynamic> toMap() => {
    'fundId': fundId,
    'kind': kind.name,
    'balance': balance,
    'currency': currency,
    'openedAt': openedAt.toIso8601String(),
    'transactions': transactions.map((t) => t.toMap()).toList(),
    if (anchor != null) 'anchor': anchor!.toMap(),
  };

  /// A holding written before a field existed has no key for it. `kind`
  /// defaults to `fund`, `source` to 'you' and `anchor` to none, which is what
  /// every one of them is, so the box migrates itself on read and nothing on
  /// an installed device (or in an old backup) needs rewriting.
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
    anchor: BalanceAnchor.fromMap(m['anchor']),
  );
}

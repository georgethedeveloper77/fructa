/// A fund statement, read from a manager's PDF and held only on the device.
library;

/// What one statement line did to the account.
enum StatementEntryKind { deposit, withdrawal, interest }

/// One transaction line from a statement.
class StatementEntry {
  const StatementEntry({
    required this.ref,
    required this.date,
    required this.description,
    required this.kind,
    required this.amount,
    required this.tax,
    required this.balance,
  });

  /// The manager's transaction number, used to recognise a line seen before.
  final String ref;
  final DateTime date;
  final String description;
  final StatementEntryKind kind;

  /// Signed money movement: deposits positive, withdrawals negative. For an
  /// interest line this is the GROSS interest; [tax] is withheld from it.
  final double amount;

  /// Withholding tax on an interest line, zero otherwise.
  final double tax;

  /// Running balance printed on the line, after it.
  final double balance;

  /// What the line changed the balance by.
  double get net => kind == StatementEntryKind.interest ? amount - tax : amount;
}

/// Everything read from one statement.
class StatementData {
  const StatementData({
    required this.managerKey,
    required this.managerName,
    required this.currency,
    required this.entries,
    this.accountNo,
    this.memberNo,
    this.statementDate,
    this.warnings = const [],
    this.printedTotals,
  });

  /// The statement's own totals row as printed (deposits, interest,
  /// withdrawals, tax, balance), when it has one. Compared against the sum of
  /// the lines, because a totals row that does not add up is itself a finding.
  final List<double>? printedTotals;

  /// Stable id for the manager (`lofty_corban`), or `unknown`.
  final String managerKey;
  final String managerName;
  final String currency;
  final String? accountNo;
  final String? memberNo;
  final DateTime? statementDate;

  /// Oldest first.
  final List<StatementEntry> entries;

  /// Lines whose arithmetic did not reconcile with the running balance. Kept,
  /// not dropped, so the user sees the statement as printed.
  final List<String> warnings;

  DateTime get from => entries.first.date;
  DateTime get to => statementDate ?? entries.last.date;
  double get closingBalance => entries.last.balance;

  /// Last four characters of the account number, for display.
  String get accountTail {
    final a = accountNo ?? '';
    return a.length <= 4 ? a : a.substring(a.length - 4);
  }

  double _sum(StatementEntryKind k, double Function(StatementEntry) f) =>
      entries.where((e) => e.kind == k).fold(0.0, (s, e) => s + f(e));

  double get deposits => _sum(StatementEntryKind.deposit, (e) => e.amount);
  double get withdrawals =>
      -_sum(StatementEntryKind.withdrawal, (e) => e.amount);
  double get interest => _sum(StatementEntryKind.interest, (e) => e.amount);
  double get tax => _sum(StatementEntryKind.interest, (e) => e.tax);
}

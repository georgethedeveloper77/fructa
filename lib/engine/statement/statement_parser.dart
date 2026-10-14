import 'statement_model.dart';

/// The statement could not be read as a fund statement.
class StatementParseException implements Exception {
  const StatementParseException(this.reason);

  /// i18n key describing why, for the UI.
  final String reason;

  @override
  String toString() => 'StatementParseException($reason)';
}

/// A manager the parser recognises, with how to spot its statements.
class StatementManager {
  const StatementManager(this.key, this.name, this.pattern);

  final String key;
  final String name;
  final RegExp pattern;
}

/// Turns the text of a fund statement PDF into [StatementData].
///
/// Layout-free on purpose. PDF text extraction does not preserve columns, and
/// a row's numbers shift with what it is (a deposit has two numbers, an
/// interest line three). So each row is read as: transaction number, date,
/// description, then its numbers in order, and what the numbers mean is
/// decided by the RUNNING BALANCE, not by position:
///
/// * interest rows (description starts "INTEREST"): gross, tax, balance, and
///   previous balance + gross - tax must equal the new balance;
/// * every other row: amount, balance, and the sign of the balance change
///   says whether it was a deposit or a withdrawal.
///
/// Rows are found by their transaction-number-and-date opening wherever they
/// sit in the text, so line breaks inside a row do not matter.
abstract final class StatementParser {
  /// Managers recognised by name. Unknown managers still parse if their rows
  /// follow the same number, date, description, amounts, balance shape.
  static final managers = <StatementManager>[
    StatementManager('lofty_corban', 'Lofty-Corban', _ci(r'lofty[\s-]*corban')),
    StatementManager('cytonn', 'Cytonn', _ci(r'cytonn')),
    StatementManager('cic', 'CIC', _ci(r'\bcic\s+asset')),
    StatementManager('sanlam', 'Sanlam', _ci(r'sanlam')),
    StatementManager('etica', 'Etica', _ci(r'etica\s+capital')),
  ];

  static RegExp _ci(String p) => RegExp(p, caseSensitive: false);

  static final _row = RegExp(
    r'(?:^|\s)(\d{4,})\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+',
  );
  static final _num = RegExp(r'^-?\d{1,3}(?:,\d{3})*\.\d{2}$|^-?\d+\.\d{2}$');
  static final _memberNo = RegExp(
    r'Member\s*No\.?\s*:?\s*([A-Za-z0-9-]+)',
    caseSensitive: false,
  );
  static final _accountNo = RegExp(
    r'Account\s*No\.?\s*:?\s*([A-Za-z0-9-]+)',
    caseSensitive: false,
  );
  static final _stmtDate = RegExp(
    r'Statement\s*Date\s*:?\s*([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{4})',
    caseSensitive: false,
  );
  static final _ccy = RegExp(
    r'Summation\s*\((KES|USD)\)|\b(USD)\b',
    caseSensitive: false,
  );
  static final _summation = RegExp(
    r'Summation\s*\((?:KES|USD)\)\s*((?:-?[\d,]+\.\d{2}\s*){3,6})',
    caseSensitive: false,
  );

  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Reads [text], the concatenated page text of one statement. [extra] are
  /// managers described in admin config; they are tried before the built-in
  /// list so the admin can correct or add a manager without an app release.
  static StatementData parse(
    String text, {
    List<StatementManager> extra = const [],
  }) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final manager = _manager(flat, extra);

    final heads = _row.allMatches(flat).toList();
    if (heads.isEmpty) {
      throw const StatementParseException('statement.err.noRows');
    }

    final entries = <StatementEntry>[];
    final warnings = <String>[];
    var prev = 0.0;
    for (var i = 0; i < heads.length; i++) {
      final m = heads[i];
      final end = i + 1 < heads.length ? heads[i + 1].start : flat.length;
      final body = flat.substring(m.end, end).trim().split(' ');

      // Description is every token before the first amount; amounts run until
      // the first token that is not one (a footer such as "Summation").
      final desc = <String>[];
      final nums = <double>[];
      for (final tok in body) {
        if (_num.hasMatch(tok)) {
          nums.add(double.parse(tok.replaceAll(',', '')));
        } else if (nums.isEmpty) {
          desc.add(tok);
        } else {
          break;
        }
      }
      if (nums.length < 2) continue;

      final ref = m.group(1)!;
      final date = _date(m.group(2)!);
      if (date == null) continue;
      final description = desc.join(' ');
      final balance = nums.last;

      if (description.toUpperCase().startsWith('INTEREST') &&
          nums.length >= 3) {
        final gross = nums[0];
        final tax = nums[1];
        if ((prev + gross - tax - balance).abs() > 0.05) {
          warnings.add(ref);
        }
        entries.add(
          StatementEntry(
            ref: ref,
            date: date,
            description: description,
            kind: StatementEntryKind.interest,
            amount: gross,
            tax: tax,
            balance: balance,
          ),
        );
      } else {
        final flow = double.parse((balance - prev).toStringAsFixed(2));
        if ((flow.abs() - nums.first.abs()).abs() > 0.05) {
          warnings.add(ref);
        }
        entries.add(
          StatementEntry(
            ref: ref,
            date: date,
            description: description,
            kind: flow >= 0
                ? StatementEntryKind.deposit
                : StatementEntryKind.withdrawal,
            amount: flow,
            tax: 0,
            balance: balance,
          ),
        );
      }
      prev = balance;
    }

    if (entries.isEmpty) {
      throw const StatementParseException('statement.err.noRows');
    }

    final ccy = _ccy.firstMatch(flat);
    final sd = _stmtDate.firstMatch(flat);
    DateTime? statementDate;
    if (sd != null) {
      final mon = _months[sd.group(1)!.substring(0, 3).toLowerCase()];
      if (mon != null) {
        statementDate = DateTime(
          int.parse(sd.group(3)!),
          mon,
          int.parse(sd.group(2)!),
        );
      }
    }

    final sum = _summation.firstMatch(flat);
    final printed = sum
        ?.group(1)!
        .trim()
        .split(' ')
        .where((x) => x.isNotEmpty)
        .map((x) => double.parse(x.replaceAll(',', '')))
        .toList();

    return StatementData(
      printedTotals: printed,
      managerKey: manager?.key ?? 'unknown',
      managerName: manager?.name ?? '',
      currency: (ccy?.group(1) ?? ccy?.group(2) ?? 'KES').toUpperCase(),
      accountNo: _accountNo.firstMatch(flat)?.group(1),
      memberNo: _memberNo.firstMatch(flat)?.group(1),
      statementDate: statementDate,
      entries: entries,
      warnings: warnings,
    );
  }

  static StatementManager? _manager(String flat, List<StatementManager> extra) {
    for (final m in [...extra, ...managers]) {
      if (m.pattern.hasMatch(flat)) return m;
    }
    return null;
  }

  /// `2025-03-28` or `28/03/2025`.
  static DateTime? _date(String s) {
    if (s.contains('-')) return DateTime.tryParse(s);
    final p = s.split('/');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
  }
}

import 'dart:math' as math;

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

/// Rows read from a statement, and the refs of rows that did not reconcile.
typedef _Read = ({List<StatementEntry> entries, List<String> warnings});

/// One dated line found in the text, before it is classified.
class _Line {
  const _Line(this.date, this.text, this.nums, this.ref);

  final DateTime date;
  final String text;
  final List<double> nums;
  final String ref;
}

/// Turns the text of a fund statement PDF into [StatementData], whoever the
/// manager is.
///
/// Every manager lays statements out differently: some number each line,
/// some print debit and credit columns, some list newest first, some put tax
/// on its own line, some print no running balance at all. PDF text extraction
/// keeps none of the columns. So nothing here depends on position. A line is
/// found by its date, its numbers are read in order, and what they mean is
/// decided by the RUNNING BALANCE: the change from the previous line's balance
/// is the money that moved, and the line's other numbers must account for it.
///
/// Two readers run. The numbered reader (transaction number, then date) is
/// the original, exact for statements laid out that way. The any-layout
/// reader is tried when that one finds little or does not reconcile, and the
/// better result is kept.
abstract final class StatementParser {
  /// Managers recognised by name, kept for their stable keys (saved passwords
  /// and statement-day tags use them). Any other manager is still read; the
  /// app also passes every manager it tracks as [parse]'s `known`.
  static final managers = <StatementManager>[
    StatementManager('lofty_corban', 'Lofty-Corban', _ci(r'lofty[\s-]*corban')),
    StatementManager('cytonn', 'Cytonn', _ci(r'cytonn')),
    StatementManager('cic', 'CIC', _ci(r'\bcic\s+asset')),
    StatementManager('sanlam', 'Sanlam', _ci(r'sanlam')),
    StatementManager('etica', 'Etica', _ci(r'etica\s+capital')),
  ];

  static RegExp _ci(String p) => RegExp(p, caseSensitive: false);

  // ── Numbered layout ───────────────────────────────────────────────────────

  static final _row = RegExp(
    r'(?:^|\s)(\d{4,})\s+(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+',
  );
  static final _num = RegExp(r'^-?\d{1,3}(?:,\d{3})*\.\d{2}$|^-?\d+\.\d{2}$');

  // ── Header fields ─────────────────────────────────────────────────────────

  static final _memberNo = RegExp(
    r'(?:Member|Client|Investor|Customer)\s*(?:No|Number|ID)\.?\s*:?\s*([A-Za-z0-9-]*\d[A-Za-z0-9-]*)',
    caseSensitive: false,
  );
  static final _accountNo = RegExp(
    r'Acc(?:ount|t)?\.?\s*(?:No|Number|#)\.?\s*:?\s*([A-Za-z0-9-]*\d[A-Za-z0-9-]*)',
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
  static final _usd = RegExp(
    r'\bUSD\b|US\$|\bdollars?\b',
    caseSensitive: false,
  );
  static final _kes = RegExp(
    r'\bKES\b|\bKSHS?\b|\bshillings?\b',
    caseSensitive: false,
  );
  static final _summation = RegExp(
    r'Summation\s*\((?:KES|USD)\)\s*((?:-?[\d,]+\.\d{2}\s*){3,6})',
    caseSensitive: false,
  );

  // ── Any layout ────────────────────────────────────────────────────────────

  static const _monthNames = {
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

  static const _mon =
      r'(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?';

  /// Dates as Kenyan managers print them: 2026-09-30, 30/09/2026, 30.09.26,
  /// 30-Sep-2026, 30 September 2026, Sep 30, 2026.
  static final _anyDate = RegExp(
    '(?<![\\d,.])(?:'
    '(\\d{4})-(\\d{1,2})-(\\d{1,2})'
    '|(\\d{1,2})[/.\\-](\\d{1,2})[/.\\-](\\d{4}|\\d{2})'
    '|(\\d{1,2})[\\s\\-]+($_mon)[\\s\\-,]+(\\d{4}|\\d{2})'
    '|($_mon)\\s+(\\d{1,2}),?\\s+(\\d{4})'
    ')(?![\\d,])',
    caseSensitive: false,
  );

  /// Money: 1,234.56 · 1234.56 · (1,234.56) · -1,234.56 · 1,234 · KES1,234.56
  /// · 1,234.56CR. A bare whole number without commas is a reference or a
  /// year, never money.
  static final _money = RegExp(
    r'^\(?(-)?(?:KES|KSHS?|USD|US\$)?(-)?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+\.\d{1,2})\)?(CR|DR)?$',
    caseSensitive: false,
  );

  /// Tokens that sit between amounts in a row without meaning anything.
  static final _filler = RegExp(
    r'^(?:-|–|KES|KSHS?|USD|CR|DR|\|)$',
    caseSensitive: false,
  );

  static final _opening = RegExp(
    r'\b(?:opening\s+balance|balance\s+b/?f|balance\s+brought\s+forward|brought\s+forward|b/f)\b',
    caseSensitive: false,
  );
  static final _openingAmount = RegExp(
    r'(?:opening\s+balance|balance\s+b/?f|balance\s+brought\s+forward|brought\s+forward)\s*:?\s*(?:KES|KSHS?|USD)?\s*\(?(-?\d{1,3}(?:,\d{3})*\.\d{2}|-?\d+\.\d{2})',
    caseSensitive: false,
  );
  static final _closing = RegExp(
    r'\b(?:closing\s+balance|balance\s+c/?f|carried\s+forward|c/f|total|totals|summation)\b',
    caseSensitive: false,
  );
  static final _tax = RegExp(
    r'\b(?:tax|wht|w/tax|withholding)\b',
    caseSensitive: false,
  );
  static final _interest = RegExp(
    r'\b(?:interest|int\.?|earnings?|accru\w*|capitali[sz]\w*|dividends?|income|yield)\b',
    caseSensitive: false,
  );
  static final _out = RegExp(
    r'\b(?:withdraw\w*|redemp\w*|redeem\w*|payout|paid\s+out|transfer\s+out|switch\s+out|debit|fees?|charges?|levy)\b',
    caseSensitive: false,
  );
  static final _refToken = RegExp(r'^[A-Za-z0-9/-]*\d[A-Za-z0-9/-]*$');

  static final _fundType = RegExp(
    r'\b(?:money\s+market|fixed\s+income|unit\s+trust|cash\s+management|mmf)\b',
    caseSensitive: false,
  );
  static const _nameStop = {
    'of',
    'the',
    'for',
    'statement',
    'account',
    'investor',
    'member',
    'client',
    'name',
    'fund',
    'funds',
    'and',
    'to',
    'from',
  };
  static const _nameTail = {
    'asset',
    'assets',
    'investment',
    'investments',
    'management',
    'managers',
    'manager',
    'limited',
    'ltd',
    'plc',
    'kenya',
    'group',
    'kes',
    'usd',
  };

  /// Reads [text], the concatenated page text of one statement.
  ///
  /// [extra] are managers described in admin config; they are tried before
  /// the built-in list so the admin can correct or add a manager without an
  /// app release. [known] are the managers the app tracks, tried after the
  /// built-ins. When none match, the fund's own name on the statement
  /// ("Zeta Money Market Fund") names the manager.
  static StatementData parse(
    String text, {
    List<StatementManager> extra = const [],
    List<StatementManager> known = const [],
  }) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final manager =
        _manager(flat, [...extra, ...managers]) ?? _earliest(flat, known);

    var read = _numbered(flat);
    if (!_trustworthy(read)) {
      final any = _anyLayout(flat);
      if (read.entries.isEmpty || _score(any) > _score(read)) read = any;
    }
    if (read.entries.isEmpty) {
      throw const StatementParseException('statement.err.noRows');
    }

    final entries = read.entries;
    final sd = _stmtDate.firstMatch(flat);
    DateTime? statementDate;
    if (sd != null) {
      final mon = _monthNames[sd.group(1)!.substring(0, 3).toLowerCase()];
      if (mon != null) {
        statementDate = DateTime(
          int.parse(sd.group(3)!),
          mon,
          int.parse(sd.group(2)!),
        );
      }
    }
    if (statementDate != null && statementDate.isBefore(entries.last.date)) {
      statementDate = null;
    }

    final sum = _summation.firstMatch(flat);
    final printed = sum
        ?.group(1)!
        .trim()
        .split(' ')
        .where((x) => x.isNotEmpty)
        .map((x) => double.parse(x.replaceAll(',', '')))
        .toList();

    final named = manager ?? _fromFundName(flat);
    return StatementData(
      printedTotals: printed,
      managerKey: named?.key ?? 'unknown',
      managerName: named?.name ?? '',
      currency: _currency(flat),
      accountNo: _accountNo.firstMatch(flat)?.group(1),
      memberNo: _memberNo.firstMatch(flat)?.group(1),
      statementDate: statementDate,
      entries: entries,
      warnings: read.warnings,
    );
  }

  /// Few rows that did not reconcile, and enough rows to mean something.
  static bool _trustworthy(_Read r) =>
      r.entries.length >= 2 && r.warnings.length <= r.entries.length * 0.25;

  static double _score(_Read r) => r.entries.length - 3.0 * r.warnings.length;

  static StatementManager? _manager(String flat, List<StatementManager> all) {
    for (final m in all) {
      if (m.pattern.hasMatch(flat)) return m;
    }
    return null;
  }

  /// Of the tracked managers, the one named first on the statement: the
  /// header names the fund's manager before any footer names a regulator or
  /// a bank.
  static StatementManager? _earliest(String flat, List<StatementManager> all) {
    StatementManager? best;
    var at = flat.length;
    for (final m in all) {
      final hit = m.pattern.firstMatch(flat);
      if (hit != null && hit.start < at) {
        at = hit.start;
        best = m;
      }
    }
    return best;
  }

  /// The words before "Money Market Fund" (or another fund type), less the
  /// corporate tail: "ZETA ASSET MANAGERS MONEY MARKET FUND" reads as "Zeta".
  static StatementManager? _fromFundName(String flat) {
    final m = _fundType.firstMatch(flat);
    if (m == null) return null;
    final before = flat
        .substring(math.max(0, m.start - 80), m.start)
        .trim()
        .split(' ');
    final words = <String>[];
    for (final w in before.reversed) {
      final clean = w.replaceAll(RegExp(r"[^A-Za-z&'\-]"), '');
      if (clean.isEmpty || _nameStop.contains(clean.toLowerCase())) break;
      words.insert(0, clean);
      if (words.length == 4) break;
    }
    while (words.isNotEmpty && _nameTail.contains(words.last.toLowerCase())) {
      words.removeLast();
    }
    if (words.isEmpty) return null;
    final name = words.map(_title).join(' ');
    final key =
        'auto_${name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_')}';
    return StatementManager(key, name, RegExp(RegExp.escape(name)));
  }

  /// "ZETA" reads as "Zeta"; mixed case stays as printed.
  static String _title(String w) => w == w.toUpperCase() && w.length > 3
      ? '${w[0]}${w.substring(1).toLowerCase()}'
      : w;

  /// KES unless the statement talks in dollars more than in shillings.
  static String _currency(String flat) {
    // The numbered layout names it on its totals row; trust that first.
    final printed = _ccy.firstMatch(flat)?.group(1);
    if (printed != null) return printed.toUpperCase();
    final usd = _usd.allMatches(flat).length;
    final kes = _kes.allMatches(flat).length;
    return usd > kes ? 'USD' : 'KES';
  }

  // ── Numbered reader ──────────────────────────────────────────────────────

  /// Transaction number, date, description, then numbers. Interest rows
  /// (description starts "INTEREST") read gross, tax, balance; every other
  /// row reads amount, balance, and the balance change gives its sign.
  static _Read _numbered(String flat) {
    final heads = _row.allMatches(flat).toList();
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
      final date = _isoOrSlash(m.group(2)!);
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
    return (entries: entries, warnings: warnings);
  }

  /// `2025-03-28` or `28/03/2025`.
  static DateTime? _isoOrSlash(String s) {
    if (s.contains('-')) return DateTime.tryParse(s);
    final p = s.split('/');
    if (p.length != 3) return null;
    return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
  }

  // ── Any-layout reader ────────────────────────────────────────────────────

  /// Finds every dated line, then reconciles them against the running
  /// balance. Falls back to reading signed amounts when the statement prints
  /// no balance column.
  static _Read _anyLayout(String flat) {
    final lines = _lines(flat);
    if (lines.isEmpty) return (entries: const [], warnings: const []);
    final open = _openingAmount.firstMatch(flat);
    final opening = open == null
        ? null
        : double.parse(open.group(1)!.replaceAll(',', ''));

    final withBalance = _withBalance(lines, opening);
    if (_trustworthy(withBalance)) return withBalance;
    final signed = _signedOnly(lines, opening);
    return _score(signed) > _score(withBalance) ? signed : withBalance;
  }

  /// Every line that starts with a date and carries money, oldest first.
  static List<_Line> _lines(String flat) {
    final dates = _anyDate.allMatches(flat).toList();
    final out = <_Line>[];
    for (var i = 0; i < dates.length; i++) {
      final date = _anyDateOf(dates[i]);
      if (date == null) continue;
      final end = i + 1 < dates.length ? dates[i + 1].start : flat.length;
      final toks = flat
          .substring(dates[i].end, end)
          .trim()
          .split(' ')
          .where((s) => s.isNotEmpty);

      final desc = <String>[];
      final nums = <double>[];
      for (final tok in toks) {
        final a = _amount(tok);
        if (a != null) {
          nums.add(a);
        } else if (_filler.hasMatch(tok)) {
          continue;
        } else if (nums.isEmpty) {
          desc.add(tok);
        } else {
          // Words after the amounts are the next block (a footer, a page
          // header), not part of this line.
          break;
        }
      }
      final text = desc.join(' ');
      if (nums.isEmpty || _opening.hasMatch(text) || _closing.hasMatch(text)) {
        continue;
      }
      final ref = desc.firstWhere(
        (w) => w.length >= 4 && _refToken.hasMatch(w),
        orElse: () =>
            '${date.toIso8601String().substring(0, 10)}|${nums.last.toStringAsFixed(2)}',
      );
      out.add(_Line(date, text, nums, ref));
    }
    // Some managers list newest first.
    if (out.length >= 2 && out.first.date.isAfter(out.last.date)) {
      return out.reversed.toList();
    }
    return out;
  }

  /// Last number is the running balance; the change from the previous
  /// balance is what moved, and the line's other numbers must explain it.
  static _Read _withBalance(List<_Line> lines, double? opening) {
    final entries = <StatementEntry>[];
    final warnings = <String>[];
    double? prev = opening;

    for (final l in lines) {
      final bal = l.nums.last.abs();
      final others = [
        for (final n in l.nums.sublist(0, l.nums.length - 1)) n.abs(),
      ];
      final isTax = _tax.hasMatch(l.text);
      final isInterest = !isTax && _interest.hasMatch(l.text);
      final isOut = isTax || _out.hasMatch(l.text);

      if (prev == null) {
        // No opening balance printed: the first line's own amount is its move.
        final first = others.firstWhere((x) => x > 0, orElse: () => bal);
        prev = bal - (isOut ? -first : first);
      }
      final flow = _r2(bal - prev);
      prev = bal;
      if (flow.abs() < 0.005) continue;

      // Tax on its own line belongs to the interest it was taken from.
      if (isTax && flow < 0) {
        final at = entries.lastIndexWhere(
          (e) => e.kind == StatementEntryKind.interest,
        );
        if (at >= 0) {
          final e = entries[at];
          entries[at] = StatementEntry(
            ref: e.ref,
            date: e.date,
            description: e.description,
            kind: e.kind,
            amount: e.amount,
            tax: _r2(e.tax - flow),
            balance: at == entries.length - 1 ? bal : e.balance,
          );
          continue;
        }
      }

      if (isInterest && flow > 0) {
        var gross = flow;
        var tax = 0.0;
        if (!others.any((x) => _near(x, flow))) {
          final pair = _grossAndTax(others, flow);
          if (pair == null) {
            warnings.add(l.ref);
          } else {
            gross = pair.$1;
            tax = pair.$2;
          }
        }
        entries.add(
          StatementEntry(
            ref: l.ref,
            date: l.date,
            description: l.text,
            kind: StatementEntryKind.interest,
            amount: gross,
            tax: tax,
            balance: bal,
          ),
        );
        continue;
      }

      if (!others.any((x) => _near(x, flow.abs()))) warnings.add(l.ref);
      entries.add(
        StatementEntry(
          ref: l.ref,
          date: l.date,
          description: l.text,
          kind: flow >= 0
              ? StatementEntryKind.deposit
              : StatementEntryKind.withdrawal,
          amount: flow,
          tax: 0,
          balance: bal,
        ),
      );
    }
    return (entries: entries, warnings: warnings);
  }

  /// No balance column: each line's amount is the move, signed by its column
  /// (debit then credit) or by its words, and the balance is summed.
  static _Read _signedOnly(List<_Line> lines, double? opening) {
    final entries = <StatementEntry>[];
    var bal = opening ?? 0.0;
    for (final l in lines) {
      final isTax = _tax.hasMatch(l.text);
      final isInterest = !isTax && _interest.hasMatch(l.text);
      double move;
      if (l.nums.length == 2 && (l.nums[0] == 0) != (l.nums[1] == 0)) {
        // Debit and credit columns, one of them empty.
        move = l.nums[1] != 0 ? l.nums[1].abs() : -l.nums[0].abs();
      } else {
        final a = l.nums.firstWhere((x) => x != 0, orElse: () => 0);
        move = a < 0 || isTax || _out.hasMatch(l.text) ? -a.abs() : a.abs();
      }
      if (move == 0) continue;

      if (isTax && move < 0) {
        final at = entries.lastIndexWhere(
          (e) => e.kind == StatementEntryKind.interest,
        );
        if (at >= 0) {
          bal = _r2(bal + move);
          final e = entries[at];
          entries[at] = StatementEntry(
            ref: e.ref,
            date: e.date,
            description: e.description,
            kind: e.kind,
            amount: e.amount,
            tax: _r2(e.tax - move),
            balance: at == entries.length - 1 ? bal : e.balance,
          );
          continue;
        }
      }
      bal = _r2(bal + move);
      entries.add(
        StatementEntry(
          ref: l.ref,
          date: l.date,
          description: l.text,
          kind: isInterest && move > 0
              ? StatementEntryKind.interest
              : move >= 0
              ? StatementEntryKind.deposit
              : StatementEntryKind.withdrawal,
          amount: move,
          tax: 0,
          balance: bal,
        ),
      );
    }
    // Nothing reconciles without a balance, so these count as unverified.
    return (
      entries: entries,
      warnings: [
        for (final e in entries) e.ref,
      ].take(entries.length ~/ 3).toList(),
    );
  }

  /// Gross and tax among [nums] whose difference is the [net] that moved.
  static (double, double)? _grossAndTax(List<double> nums, double net) {
    for (final g in nums) {
      for (final t in nums) {
        if (g > t && t >= 0 && _near(g - t, net)) return (g, t);
      }
    }
    return null;
  }

  static bool _near(double a, double b) => (a - b).abs() <= 0.05;

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));

  static double? _amount(String tok) {
    final m = _money.firstMatch(tok);
    if (m == null) return null;
    final v = double.parse(m.group(3)!.replaceAll(',', ''));
    final neg =
        m.group(1) != null ||
        m.group(2) != null ||
        (tok.startsWith('(') && tok.endsWith(')')) ||
        (m.group(4)?.toUpperCase() == 'DR');
    return neg ? -v : v;
  }

  /// A date match as a day. Day-first, as Kenyan statements print it; a
  /// month-first date is accepted only when the day-first reading is invalid.
  static DateTime? _anyDateOf(Match m) {
    int y;
    int mo;
    int d;
    if (m.group(1) != null) {
      y = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      d = int.parse(m.group(3)!);
    } else if (m.group(4) != null) {
      d = int.parse(m.group(4)!);
      mo = int.parse(m.group(5)!);
      y = int.parse(m.group(6)!);
      if (mo > 12 && d <= 12) {
        final s = d;
        d = mo;
        mo = s;
      }
    } else if (m.group(7) != null) {
      d = int.parse(m.group(7)!);
      mo = _monthNames[m.group(8)!.substring(0, 3).toLowerCase()] ?? 0;
      y = int.parse(m.group(9)!);
    } else {
      mo = _monthNames[m.group(10)!.substring(0, 3).toLowerCase()] ?? 0;
      d = int.parse(m.group(11)!);
      y = int.parse(m.group(12)!);
    }
    if (y < 100) y += 2000;
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) {
      return null;
    }
    return DateTime(y, mo, d);
  }
}

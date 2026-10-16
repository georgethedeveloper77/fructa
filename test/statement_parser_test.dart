import 'package:flutter_test/flutter_test.dart';
import 'package:fructa/engine/statement/statement_model.dart';
import 'package:fructa/engine/statement/statement_parser.dart';

/// Statement text as PDF extraction returns it: one run of words, columns
/// gone. Each fixture is a different manager's layout.
void main() {
  group('numbered layout (transaction number, then date)', () {
    const text =
        'LOFTY-CORBAN MONEY MARKET FUND Statement Date: Sep 30, 2026 '
        'Member No: M123 Account No: 00012345 '
        '100231 2026-09-01 DEPOSIT MPESA 10,000.00 10,000.00 '
        '100232 2026-09-30 INTEREST 90.00 13.50 10,076.50 '
        'Summation (KES) 10,000.00 90.00 0.00 13.50 10,076.50';

    test('reads as before', () {
      final d = StatementParser.parse(text);
      expect(d.managerKey, 'lofty_corban');
      expect(d.currency, 'KES');
      expect(d.accountNo, '00012345');
      expect(d.entries, hasLength(2));
      expect(d.entries[0].kind, StatementEntryKind.deposit);
      expect(d.entries[1].kind, StatementEntryKind.interest);
      expect(d.entries[1].amount, 90.00);
      expect(d.entries[1].tax, 13.50);
      expect(d.closingBalance, 10076.50);
      expect(d.statementDate, DateTime(2026, 9, 30));
    });
  });

  group('debit, credit and balance columns, tax on its own line', () {
    const text =
        'ZETA ASSET MANAGERS MONEY MARKET FUND Statement of Account '
        'Period: 01-Sep-2026 to 30-Sep-2026 Client No: Z-77881 '
        'Date Description Debit Credit Balance '
        '01-Sep-2026 Balance b/f 50,000.00 '
        '05-Sep-2026 Deposit via M-Pesa 0.00 20,000.00 70,000.00 '
        '15-Sep-2026 Withdrawal to bank 5,000.00 0.00 65,000.00 '
        '30-Sep-2026 Interest earned 0.00 650.00 65,650.00 '
        '30-Sep-2026 Withholding tax 97.50 0.00 65,552.50 '
        'Closing Balance 65,552.50';

    test('reconciles against the running balance', () {
      final d = StatementParser.parse(text);
      expect(d.managerName, 'Zeta');
      expect(d.memberNo, 'Z-77881');
      expect(d.entries.map((e) => e.kind), [
        StatementEntryKind.deposit,
        StatementEntryKind.withdrawal,
        StatementEntryKind.interest,
      ]);
      expect(d.entries[1].amount, -5000.00);
      expect(d.entries[2].amount, 650.00);
      expect(d.entries[2].tax, 97.50);
      expect(d.closingBalance, 65552.50);
      expect(d.warnings, isEmpty);
    });
  });

  group('newest first, net interest, CR balances', () {
    const text =
        'Unit Holder Statement Beta Capital Fixed Income Fund '
        'Account Number 55443322 Statement period 01/08/2026 - 31/08/2026 '
        'Value Date Narration Amount Balance '
        '31/08/2026 Interest capitalised 412.33 30,412.33CR '
        '20/08/2026 Redemption 10,000.00 30,000.00CR '
        '03/08/2026 Top up 40,000.00 40,000.00CR';

    test('puts lines oldest first and reads each move', () {
      final d = StatementParser.parse(text);
      expect(d.managerName, 'Beta Capital');
      expect(d.accountNo, '55443322');
      expect(d.from, DateTime(2026, 8, 3));
      expect(d.entries.map((e) => e.amount), [40000.00, -10000.00, 412.33]);
      expect(d.entries.last.kind, StatementEntryKind.interest);
      expect(d.closingBalance, 30412.33);
    });
  });

  group('no balance column, amounts in brackets, dollars', () {
    const text =
        'Gamma Investments USD Money Market Fund Investor Statement '
        'Currency: USD Date Details Amount (USD) '
        '02 Sep 2026 Contribution 1,500.00 '
        '15 Sep 2026 Partial withdrawal (300.00) '
        '30 Sep 2026 Interest earned 9.75 '
        '30 Sep 2026 WHT on interest (1.46)';

    test('signs each amount and sums the balance', () {
      final d = StatementParser.parse(text);
      expect(d.managerName, 'Gamma');
      expect(d.currency, 'USD');
      expect(d.entries, hasLength(3));
      expect(d.entries[1].amount, -300.00);
      expect(d.entries[2].kind, StatementEntryKind.interest);
      expect(d.entries[2].tax, 1.46);
      expect(d.closingBalance, 1208.29);
    });
  });

  group('two date columns, gross and tax on one line', () {
    const text =
        'Delta MMF statement Transaction Date Value Date Description Amount '
        'Running Balance 2026-09-01 2026-09-02 Opening balance 0.00 '
        '2026-09-03 2026-09-03 Purchase 25,000.00 25,000.00 '
        '2026-09-30 2026-09-30 Interest Income 220.50 33.08 25,187.42';

    test('finds gross and tax from the balance change', () {
      final d = StatementParser.parse(text);
      expect(d.managerName, 'Delta');
      expect(d.entries, hasLength(2));
      expect(d.entries[1].amount, 220.50);
      expect(d.entries[1].tax, 33.08);
    });
  });

  test('a tracked manager is named from the snapshot', () {
    final d = StatementParser.parse(
      'OLD MUTUAL Statement 2026-09-03 Purchase 5,000.00 5,000.00 '
      '2026-09-30 Interest 40.00 5,040.00',
      known: [
        StatementManager(
          'old_mutual',
          'Old Mutual Investment Group',
          RegExp(r'\bOld[\s\-]*Mutual\b', caseSensitive: false),
        ),
      ],
    );
    expect(d.managerKey, 'old_mutual');
    expect(d.entries, hasLength(2));
  });

  test('text with no dated lines is refused', () {
    expect(
      () => StatementParser.parse('Dear investor, thank you.'),
      throwsA(isA<StatementParseException>()),
    );
  });
}

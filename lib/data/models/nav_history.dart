/// One dated unit price for a `basis == 'nav'` fund, from `nav_history` (0070).
///
/// Mirrors [RateHistory] rather than reusing it, for the reason 0070 gave when
/// it created the table: a price and a yield are different objects that happen
/// to share a numeric type. A yield is a percentage, compounds, is taxed, and
/// cannot sensibly be negative or zero. A price is an amount in the fund's own
/// currency, does none of those things, and a zero is a missing reading rather
/// than a cheap fund.
class NavHistory {
  const NavHistory({required this.asOf, required this.price});

  /// YYYY-MM-DD. Kept as the raw ISO string, as [RateHistory] does, so a bad
  /// date in one row cannot throw while parsing a whole series.
  final String asOf;

  /// Unit price in the FUND'S OWN currency. Never converted, and never assumed
  /// to be shillings: `lofty-corban-fi-usd` quotes its NAV in dollars. The unit
  /// is `funds.currency`, on the fund's own row.
  final double price;

  factory NavHistory.fromJson(Map<String, dynamic> j) => NavHistory(
    asOf: j['as_of'] as String,
    price: (j['price'] as num).toDouble(),
  );
}

class RateHistory {
  final String asOf; // YYYY-MM-DD
  final double rate;

  const RateHistory({required this.asOf, required this.rate});

  factory RateHistory.fromJson(Map<String, dynamic> j) => RateHistory(
    asOf: j['as_of'] as String,
    rate: (j['rate'] as num).toDouble(),
  );
}

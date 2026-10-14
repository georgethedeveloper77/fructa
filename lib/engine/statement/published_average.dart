import '../../data/models/rate_history.dart';

/// Average published rate between [from] and [to], inclusive, treating
/// [history] as a step series: a rate holds from its as-of date until the
/// next one. Null when the history does not reach back to [from], because an
/// average that silently starts late would understate or overstate the gap.
double? publishedAverage(
  List<RateHistory> history,
  DateTime from,
  DateTime to,
) {
  if (history.isEmpty || to.isBefore(from)) return null;
  final pts = [
    for (final h in history)
      if (DateTime.tryParse(h.asOf) case final d?) (d, h.rate),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (pts.isEmpty || pts.first.$1.isAfter(from)) return null;

  var sum = 0.0;
  var days = 0;
  var k = 0;
  for (
    var d = DateTime(from.year, from.month, from.day);
    !d.isAfter(to);
    d = d.add(const Duration(days: 1))
  ) {
    while (k + 1 < pts.length && !pts[k + 1].$1.isAfter(d)) {
      k++;
    }
    sum += pts[k].$2;
    days++;
  }
  return days == 0 ? null : sum / days;
}

/// Alerts Fructa works out on the phone from the user's own data: their
/// statements, holdings and follows. Nothing here is sent to a server.
enum SmartAlertType {
  /// A checked statement shows the fund credited less than it published.
  underpaid,

  /// Another fund of the same kind would pay the user's balance meaningfully
  /// more a year, after tax and the days money spends in transit.
  betterFund,

  /// A followed fund dropped out of its category's top 5.
  rankDrop,

  /// A checked statement has a month with no interest credited.
  noInterest,
}

class SmartAlert {
  const SmartAlert({
    required this.key,
    required this.type,
    required this.title,
    required this.body,
    required this.at,
    this.target,
  });

  /// Stable identity, so the same finding is raised once, ever.
  final String key;
  final SmartAlertType type;
  final String title;
  final String body;
  final DateTime at;

  /// Where a tap goes: `portfolio`, `alerts` or `fund/<id>`.
  final String? target;

  Map<String, dynamic> toMap() => {
    'key': key,
    'type': type.name,
    'title': title,
    'body': body,
    'at': at.toIso8601String(),
    'target': target,
  };

  static SmartAlert fromMap(Map m) => SmartAlert(
    key: m['key'] as String,
    type: SmartAlertType.values.byName(m['type'] as String),
    title: m['title'] as String,
    body: m['body'] as String,
    at: DateTime.parse(m['at'] as String),
    target: m['target'] as String?,
  );
}

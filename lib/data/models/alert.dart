class RateAlert {
  final String fundId;
  final double oldRate;
  final double newRate;
  final DateTime at;

  const RateAlert({
    required this.fundId,
    required this.oldRate,
    required this.newRate,
    required this.at,
  });

  bool get up => newRate > oldRate;

  Map<String, dynamic> toMap() => {
    'fundId': fundId,
    'old': oldRate,
    'new': newRate,
    'at': at.toIso8601String(),
  };

  factory RateAlert.fromMap(Map m) => RateAlert(
    fundId: m['fundId'] as String,
    oldRate: (m['old'] as num).toDouble(),
    newRate: (m['new'] as num).toDouble(),
    at: DateTime.parse(m['at'] as String),
  );
}

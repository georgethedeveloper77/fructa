class MarketEvent {
  final String type; // rate_change | leader_change | auction_result | coupon
  final String? category;
  final String? fundId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const MarketEvent({
    required this.type,
    this.category,
    this.fundId,
    this.payload = const {},
    required this.createdAt,
  });

  factory MarketEvent.fromJson(Map<String, dynamic> j) => MarketEvent(
    type: j['type'] as String,
    category: j['category'] as String?,
    fundId: j['fund_id'] as String?,
    payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  /// Headline for the news feed: explicit payload headline, else a fallback.
  String get headline =>
      (payload['headline'] as String?) ??
      switch (type) {
        'auction_result' => 'New T-bill auction result',
        'leader_change' => 'A category leader changed',
        'coupon' => 'Coupon / maturity update',
        _ => 'Rate update',
      };

  /// 7-day style delta if the payload carries one (rate_change).
  double? get delta {
    final d = payload['delta'];
    if (d is num) return d.toDouble();
    final o = payload['old'], n = payload['new'];
    if (o is num && n is num) return (n - o).toDouble();
    return null;
  }
}

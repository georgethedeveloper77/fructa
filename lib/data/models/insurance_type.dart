/// One card on the Insure home grid, admin-managed (table `insurance_types`,
/// published in the snapshot). [icon] is a material icon NAME resolved to an
/// IconData at the screen layer (never an emoji). [status] is 'live' (has a
/// comparison flow) or 'soon' (coming-soon card).
class InsuranceType {
  final String key; // 'motor' | 'travel' | free-form
  final String label;
  final String? icon; // material icon name
  final String status; // 'live' | 'soon'
  final int ord;
  final String? sub; // optional static subtitle override
  final String? lottieUrl; // optional animated icon (material icon is fallback)

  const InsuranceType({
    required this.key,
    required this.label,
    this.icon,
    this.status = 'soon',
    this.ord = 0,
    this.sub,
    this.lottieUrl,
  });

  bool get isLive => status == 'live';

  factory InsuranceType.fromJson(Map<String, dynamic> j) => InsuranceType(
        key: (j['key'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        icon: j['icon'] as String?,
        status: (j['status'] ?? 'soon') as String,
        ord: (j['ord'] as num?)?.toInt() ?? 0,
        sub: j['sub'] as String?,
        lottieUrl: j['lottie_url'] as String?,
      );

  /// Baked fallback used when the snapshot carries no types (e.g. before the
  /// first publish): the two flows the app can price. Matches the mockup.
  static const fallback = [
    InsuranceType(key: 'motor', label: 'Motor', icon: 'motor', status: 'live', ord: 0),
    InsuranceType(key: 'travel', label: 'Travel', icon: 'travel', status: 'live', ord: 1),
  ];
}

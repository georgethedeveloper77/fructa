class Agent {
  final String id;
  final String name;
  final String? role;
  final String? phone;
  final bool whatsapp;
  final String? photoUrl;
  final bool isFree;
  final List<String> companyIds;

  const Agent({
    required this.id,
    required this.name,
    this.role,
    this.phone,
    this.whatsapp = false,
    this.photoUrl,
    this.isFree = false,
    this.companyIds = const [],
  });

  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
    id: j['id'] as String,
    name: (j['name'] ?? '') as String,
    role: j['role'] as String?,
    phone: j['phone'] as String?,
    whatsapp: (j['whatsapp'] ?? false) as bool,
    photoUrl: j['photo_url'] as String?,
    isFree: (j['is_free'] ?? false) as bool,
    companyIds: ((j['company_ids'] as List?) ?? const []).cast<String>(),
  );
}

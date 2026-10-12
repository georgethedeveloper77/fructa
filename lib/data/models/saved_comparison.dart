class SavedComparison {
  final String id;
  final List<String> fundIds;
  final bool notify;
  final String? leaderId; // last-seen highest-yield member, for flip detection
  final DateTime createdAt;

  const SavedComparison({
    required this.id,
    required this.fundIds,
    this.notify = true,
    this.leaderId,
    required this.createdAt,
  });

  SavedComparison copyWith({bool? notify, String? leaderId}) => SavedComparison(
    id: id,
    fundIds: fundIds,
    notify: notify ?? this.notify,
    leaderId: leaderId ?? this.leaderId,
    createdAt: createdAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'fundIds': fundIds,
    'notify': notify,
    'leaderId': leaderId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedComparison.fromMap(Map m) => SavedComparison(
    id: m['id'] as String,
    fundIds: (m['fundIds'] as List).cast<String>(),
    notify: (m['notify'] ?? true) as bool,
    leaderId: m['leaderId'] as String?,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}

/// A blog post from the snapshot (`posts`). snapshot.ts maps the DB's 0035
/// names (excerpt/cover_url) to this app shape (summary/hero_image_url), and
/// publishes only `published` rows, pinned first. All optional beyond
/// slug/title, so a sparse post still renders.
class Post {
  final String slug;
  final String? kind; // article | brief
  final String title;
  final String? summary;
  final String? body; // markup / markdown
  final String? heroImageUrl;
  final String? author;
  final List<String> tags;
  final String? fundId;
  final String? companyId;
  final bool pinned;
  final int? readingMinutes;
  final DateTime? publishedAt;

  const Post({
    required this.slug,
    required this.title,
    this.kind,
    this.summary,
    this.body,
    this.heroImageUrl,
    this.author,
    this.tags = const [],
    this.fundId,
    this.companyId,
    this.pinned = false,
    this.readingMinutes,
    this.publishedAt,
  });

  bool get isBrief => kind == 'brief';

  factory Post.fromJson(Map<String, dynamic> j) => Post(
    slug: (j['slug'] ?? '') as String,
    kind: j['kind'] as String?,
    title: (j['title'] ?? '') as String,
    summary: j['summary'] as String?,
    body: j['body'] as String?,
    heroImageUrl: j['hero_image_url'] as String?,
    author: j['author'] as String?,
    tags: ((j['tags'] as List?) ?? const []).whereType<String>().toList(),
    fundId: j['fund_id'] as String?,
    companyId: j['company_id'] as String?,
    pinned: (j['pinned'] ?? false) as bool,
    readingMinutes: (j['reading_minutes'] as num?)?.toInt(),
    publishedAt: DateTime.tryParse(
      (j['published_at'] ?? '') as String,
    )?.toLocal(),
  );
}

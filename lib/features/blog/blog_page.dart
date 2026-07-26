import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/post.dart';
import '../../data/snapshot_providers.dart';
import 'blog_post_page.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime? d) =>
    d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

class BlogPage extends ConsumerWidget {
  const BlogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final posts = ref.watch(postsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          'Blog',
          style: TextStyle(
            color: c.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: posts.isEmpty
          ? _Empty(c: c)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: posts.length,
              itemBuilder: (_, i) => _PostCard(post: posts[i]),
            ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = <String>[
      if (post.author != null && post.author!.isNotEmpty) post.author!,
      if (post.readingMinutes != null) '${post.readingMinutes} min',
      if (post.publishedAt != null) _date(post.publishedAt),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BlogPostPage(post: post)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.heroImageUrl != null && post.heroImageUrl!.isNotEmpty)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: post.heroImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: c.s2),
                  errorWidget: (_, _, _) => Container(color: c.s2),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (post.pinned) ...[
                        Icon(Icons.push_pin, size: 13, color: c.accentInk),
                        const SizedBox(width: 6),
                      ],
                      if (post.isBrief)
                        Text(
                          'BRIEF',
                          style: TextStyle(
                            color: c.faint,
                            fontFamily: fructaFonts.mono,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  if (post.pinned || post.isBrief) const SizedBox(height: 8),
                  Text(
                    post.title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 17,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (post.summary != null && post.summary!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      post.summary!,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      meta.join('  \u00b7  '),
                      style: TextStyle(
                        color: c.faint,
                        fontFamily: fructaFonts.mono,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.c});

  final fructaColors c;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(
              'No posts yet',
              style: TextStyle(
                color: c.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Guides and market notes will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

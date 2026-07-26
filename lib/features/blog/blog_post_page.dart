import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/in_app_web_page.dart';
import '../../data/models/post.dart';
import 'blog_markup.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _date(DateTime? d) =>
    d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

class BlogPostPage extends StatelessWidget {
  const BlogPostPage({super.key, required this.post});

  final Post post;

  void _openLink(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InAppWebPage(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = <String>[
      if (post.author != null && post.author!.isNotEmpty) post.author!,
      if (post.readingMinutes != null) '${post.readingMinutes} min read',
      if (post.publishedAt != null) _date(post.publishedAt),
    ];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        scrolledUnderElevation: 0,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
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
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.isBrief) ...[
                  Text(
                    'BRIEF',
                    style: TextStyle(
                      color: c.accentInk,
                      fontFamily: fructaFonts.mono,
                      fontSize: 10.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  post.title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 25,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    meta.join('  \u00b7  '),
                    style: TextStyle(
                      color: c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (post.tags.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in post.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: c.s2,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.line),
                          ),
                          child: Text(
                            t,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Divider(color: c.line, height: 1),
                const SizedBox(height: 18),
                if ((post.body ?? '').trim().isNotEmpty)
                  MarkdownView(
                    post.body!,
                    onTapLink: (url) => _openLink(context, url),
                  )
                else if (post.summary != null)
                  Text(
                    post.summary!,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15.5,
                      height: 1.65,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

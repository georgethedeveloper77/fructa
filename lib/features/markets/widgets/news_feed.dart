import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../markets_controller.dart';

/// News feed (v5): a "News" header with a count badge, then rows with a
/// coloured dot, title, optional description, and the timestamp pushed to the
/// right. First 2 visible; "Show N more" reveals the rest. Renders nothing
/// while the source is empty.
class NewsFeed extends StatefulWidget {
  const NewsFeed(this.items, {super.key});
  final List<NewsItem> items;

  @override
  State<NewsFeed> createState() => _NewsFeedState();
}

class _NewsFeedState extends State<NewsFeed> {
  bool _expanded = false;

  // per-item accent, cycled by index (mock assigns colours per event)
  static const _dots = [
    Color(0xFF3DDC97), // up
    Color(0xFFE7B24C), // gold
    Color(0xFF9A8BF3), // violet
    Color(0xFF4E8FE8), // blue
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();

    final visible = _expanded ? items : items.take(2).toList();
    final hidden = items.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 2),
          child: Row(
            children: [
              Text(
                'News',
                style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: c.accent,
                    fontFamily: fructaFonts.mono,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // rows
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++)
                _Row(
                  item: visible[i],
                  dot: _dots[i % _dots.length],
                  last: i == visible.length - 1,
                ),
            ],
          ),
        ),
        if (hidden > 0 && !_expanded)
          Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Show $hidden more',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down, size: 16, color: c.accent),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.dot, required this.last});
  final NewsItem item;
  final Color dot;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                if (item.body != null && item.body!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.body!,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              timeAgo(item.at),
              style: TextStyle(
                color: c.faint,
                fontFamily: fructaFonts.mono,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

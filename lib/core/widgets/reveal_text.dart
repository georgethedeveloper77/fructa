import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// Long copy, short by default.
///
/// Collapsed, the text shows at most [collapsedLines] lines with a "More" link;
/// a tap shows all of it, another tap collapses it. The house rule for any
/// explanation longer than two lines: the number and one sentence first, the
/// reasoning one tap away.
///
/// Deliberately measures nothing during layout. An earlier version used a
/// LayoutBuilder and an AnimatedSize, which asked for a new layout while the
/// framework was collecting semantics and tripped a debug assertion in lists.
/// Whether the link is needed is decided from the text's length instead.
class RevealText extends StatefulWidget {
  const RevealText(this.text, {super.key, this.style, this.collapsedLines = 2});

  final String text;
  final TextStyle? style;
  final int collapsedLines;

  /// Roughly how many characters fit on one line of a phone-width column at
  /// body sizes. Erring short only means "More" appears on a slightly long
  /// text that would just have fitted.
  static const _charsPerLine = 46;

  @override
  State<RevealText> createState() => _RevealTextState();
}

class _RevealTextState extends State<RevealText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style =
        widget.style ?? TextStyle(color: c.muted, fontSize: 13, height: 1.45);
    final long =
        widget.text.length > widget.collapsedLines * RevealText._charsPerLine;
    if (!long) return Text(widget.text, style: style);

    return Semantics(
      button: true,
      expanded: _open,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _open ? null : widget.collapsedLines,
              // Whole lines are clipped, never an ellipsis: the link below
              // says there is more.
              overflow: _open ? TextOverflow.visible : TextOverflow.clip,
            ),
            const SizedBox(height: 4),
            Text(
              t(_open ? 'common.less' : 'common.more'),
              style: TextStyle(
                color: c.accentInk,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

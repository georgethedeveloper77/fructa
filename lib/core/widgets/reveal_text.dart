import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';

/// Long copy, short by default.
///
/// Shows the first [collapsedLines] lines and a "More" link; a tap expands it
/// in place, another collapses it. Text that already fits shows no link. This
/// is the house rule for any explanation longer than two lines: the number and
/// one sentence first, the reasoning one tap away.
class RevealText extends StatefulWidget {
  const RevealText(this.text, {super.key, this.style, this.collapsedLines = 2});

  final String text;
  final TextStyle? style;
  final int collapsedLines;

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
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.collapsedLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = painter.didExceedMaxLines;
        if (!overflows) return Text(widget.text, style: style);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_open)
                  Text(widget.text, style: style)
                else
                  // Clip to whole lines, never an ellipsis: the link says
                  // there is more.
                  ClipRect(
                    child: SizedBox(
                      height: painter.height,
                      child: Text(widget.text, style: style),
                    ),
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
      },
    );
  }
}

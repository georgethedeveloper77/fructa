import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme.dart';

/// A short label that opens its explanation on tap.
///
/// For the notes, sources and caveats a reader needs once, not every time the
/// screen opens: the label says what the note is about in a few words, the
/// body holds the full text. Opens without animation under reduced motion.
class RevealNote extends StatefulWidget {
  const RevealNote({
    super.key,
    required this.label,
    required this.body,
    this.padding = EdgeInsets.zero,
    this.actionLabel,
    this.onAction,
  });

  final String label;

  /// The full text. Separate paragraphs with a blank line.
  final String body;
  final EdgeInsets padding;

  /// An optional link shown under the opened text, such as a fuller sheet.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<RevealNote> createState() => _RevealNoteState();
}

class _RevealNoteState extends State<RevealNote> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final calm = reduceMotion(context);
    return Padding(
      padding: widget.padding,
      child: Semantics(
        button: true,
        expanded: _open,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _open = !_open),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: c.faint),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.label,
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: Duration(milliseconds: calm ? 0 : 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: c.faint,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: Duration(milliseconds: calm ? 0 : 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: _open
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(21, 0, 4, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.body,
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 12.5,
                                height: 1.5,
                              ),
                            ),
                            if (widget.actionLabel != null &&
                                widget.onAction != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 40),
                                  foregroundColor: c.accentInk,
                                ),
                                onPressed: widget.onAction,
                                child: Text(
                                  widget.actionLabel!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

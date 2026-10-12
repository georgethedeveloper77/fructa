import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A compact Markdown renderer, in the spirit of core/widgets/markup.dart but
/// for full article bodies. Handles the block set the admin editor advertises
/// (headings, paragraphs, bullet + numbered lists, blockquotes, rules) and
/// inline `**bold**`, `*italic*`, `` `code` `` and `[text](url)` links. Links
/// call [onTapLink]; their recognizers are disposed with the widget.
///
/// Not a full CommonMark implementation on purpose  no new dependency, and the
/// app owns exactly what it renders.
class MarkdownView extends StatefulWidget {
  const MarkdownView(this.data, {super.key, required this.onTapLink});

  final String data;
  final void Function(String url) onTapLink;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  static final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _bullet = RegExp(r'^\s*[-*]\s+(.*)$');
  static final _numbered = RegExp(r'^\s*(\d+)\.\s+(.*)$');
  static final _quote = RegExp(r'^>\s?(.*)$');
  static final _rule = RegExp(r'^(-{3,}|\*{3,})$');

  // Order matters: bold before italic; code and link before single-star.
  static final _inline = RegExp(
    r'\*\*(.+?)\*\*|`([^`]+)`|\[(.+?)\]\((.+?)\)|\*(.+?)\*',
  );

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final c = context.c;
    final lines = widget.data.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];

    List<String>? para;
    void flushPara() {
      if (para == null || para!.isEmpty) {
        para = null;
        return;
      }
      blocks.add(_paragraph(c, para!.join(' ')));
      para = null;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flushPara();
        continue;
      }

      final h = _heading.firstMatch(trimmed);
      if (h != null) {
        flushPara();
        blocks.add(_headingWidget(c, h.group(1)!.length, h.group(2)!));
        continue;
      }

      if (_rule.hasMatch(trimmed)) {
        flushPara();
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: c.line, height: 1),
          ),
        );
        continue;
      }

      if (_quote.hasMatch(trimmed)) {
        flushPara();
        final buf = <String>[];
        while (i < lines.length && _quote.hasMatch(lines[i].trim())) {
          buf.add(_quote.firstMatch(lines[i].trim())!.group(1) ?? '');
          i++;
        }
        i--;
        blocks.add(_blockquote(c, buf.join(' ')));
        continue;
      }

      if (_bullet.hasMatch(trimmed) || _numbered.hasMatch(trimmed)) {
        flushPara();
        final items = <(_ListKind, String)>[];
        while (i < lines.length) {
          final t = lines[i].trim();
          final b = _bullet.firstMatch(t);
          final n = _numbered.firstMatch(t);
          if (b != null) {
            items.add((_ListKind.bullet, b.group(1)!));
          } else if (n != null) {
            items.add((_ListKind.numbered, n.group(2)!));
          } else {
            break;
          }
          i++;
        }
        i--;
        blocks.add(_list(c, items));
        continue;
      }

      (para ??= []).add(trimmed);
    }
    flushPara();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  // ── blocks ────────────────────────────────────────────────────────────────

  Widget _paragraph(fructaColors c, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: RichText(text: TextSpan(children: _spans(c, text, _bodyStyle(c)))),
  );

  Widget _headingWidget(fructaColors c, int level, String text) {
    final size = level == 1 ? 23.0 : (level == 2 ? 19.0 : 16.5);
    final weight = level == 3 ? FontWeight.w600 : FontWeight.w700;
    return Padding(
      padding: EdgeInsets.only(top: level == 1 ? 6 : 14, bottom: 8),
      child: RichText(
        text: TextSpan(
          children: _spans(
            c,
            text,
            TextStyle(
              color: c.text,
              fontSize: size,
              height: 1.3,
              fontWeight: weight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockquote(fructaColors c, String text) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.accent, width: 3)),
    ),
    child: RichText(
      text: TextSpan(
        children: _spans(
          c,
          text,
          _bodyStyle(c).copyWith(color: c.muted, fontStyle: FontStyle.italic),
        ),
      ),
    ),
  );

  Widget _list(fructaColors c, List<(_ListKind, String)> items) {
    var n = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (kind, text) in items) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      kind == _ListKind.numbered ? '${++n}.' : '\u2022',
                      style: _bodyStyle(c).copyWith(color: c.muted),
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      text: TextSpan(children: _spans(c, text, _bodyStyle(c))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── inline ──────────────────────────────────────────────────────────────

  TextStyle _bodyStyle(fructaColors c) =>
      TextStyle(color: c.text, fontSize: 15.5, height: 1.65);

  List<InlineSpan> _spans(fructaColors c, String text, TextStyle base) {
    final spans = <InlineSpan>[];
    var idx = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > idx) {
        spans.add(TextSpan(text: text.substring(idx, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: base.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: base.copyWith(
              fontFamily: fructaFonts.mono,
              fontSize: base.fontSize! - 1.5,
              backgroundColor: c.s2,
            ),
          ),
        );
      } else if (m.group(3) != null) {
        final label = m.group(3)!;
        final url = m.group(4)!;
        final rec = TapGestureRecognizer()..onTap = () => widget.onTapLink(url);
        _recognizers.add(rec);
        spans.add(
          TextSpan(
            text: label,
            style: base.copyWith(
              color: c.accentInk,
              decoration: TextDecoration.underline,
              decorationColor: c.accentInk.withValues(alpha: 0.5),
            ),
            recognizer: rec,
          ),
        );
      } else if (m.group(5) != null) {
        spans.add(
          TextSpan(
            text: m.group(5),
            style: base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      idx = m.end;
    }
    if (idx < text.length) {
      spans.add(TextSpan(text: text.substring(idx), style: base));
    }
    return spans;
  }
}

enum _ListKind { bullet, numbered }

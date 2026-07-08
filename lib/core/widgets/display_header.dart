import 'package:flutter/material.dart';

import '../theme.dart';

/// v5 `.disp` + `.disp-sub`. Big mono title with an optional muted subline.
///
/// When [live], a clean status tag sits to the RIGHT of the title: a small
/// pulsing-green dot (a real circle, not a glyph) + `LIVE`, optionally followed
/// by a muted `· {time}`. The subline stays quiet  the green lives only on the
/// dot and the word, so the row reads as one calm unit.
class DisplayHeader extends StatelessWidget {
  const DisplayHeader({
    super.key,
    required this.title,
    this.sub,
    this.live = false,
    this.time,
    this.updated,
  });

  final String title;
  final String? sub;
  final bool live;

  /// Optional clock/freshness string shown after `LIVE` (e.g. "12:00 EAT").
  final String? time;

  /// Optional freshness line under the sub (e.g. "Updated today · sources").
  final String? updated;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.2,
                    height: 1.05,
                  ),
                ),
              ),
              if (live) ...[const SizedBox(width: 12), _LiveTag(time: time)],
            ],
          ),
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Text(
              sub!,
              style: TextStyle(color: c.muted, fontSize: 12, height: 1.35),
            ),
          ),
        if (updated != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20, sub != null ? 4 : 6, 20, 0),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 11, color: c.faint),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    updated!,
                    style: TextStyle(
                      color: c.faint,
                      fontFamily: fructaFonts.mono,
                      fontSize: 10.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// `● LIVE · {time}`  dot is a drawn circle; text is mono, quiet, aligned.
class _LiveTag extends StatelessWidget {
  const _LiveTag({this.time});
  final String? time;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c.up, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          'LIVE',
          style: TextStyle(
            color: c.up,
            fontFamily: fructaFonts.mono,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        if (time != null)
          Text(
            ' \u00b7 $time',
            style: TextStyle(
              color: c.muted,
              fontFamily: fructaFonts.mono,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
      ],
    );
  }
}

/// v5 `.h2`. Mono section title with an optional faint Inter [trailing] note.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 9),
            Text(trailing!, style: TextStyle(color: c.faint, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

/// v5 `.disc`. Faint fine-print. [center] supports the centred disclaimers on
/// the Company page.
class Disclaimer extends StatelessWidget {
  const Disclaimer(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(color: c.faint, fontSize: 10.5, height: 1.6),
      ),
    );
  }
}

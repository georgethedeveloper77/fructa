import 'package:flutter/material.dart';

import '../theme.dart';

/// Explanatory text, in a container that says it was placed rather than left
/// over.
///
/// The app already had the right shape for this. `market_by_aum_page` ends on a
/// bordered card with an icon, a heading and a paragraph explaining where the
/// numbers came from, and it reads as part of the page. Everywhere else, the
/// same kind of text was a bare grey paragraph floating on the background:
/// disclaimers, provenance lines, "figures are indicative", the note under a
/// filter that has no published prices. Identical content, and it looked like
/// something that had not been finished.
///
/// Worse on a sparse screen. On an insurer with no benefits and no agents, the
/// disclaimer was the last thing on the page and sat above half a screen of
/// nothing, which made the page look broken rather than brief.
///
/// One widget, so the treatment is consistent and there is one place to tune
/// it. [title] is optional: without one this is an icon and a paragraph, which
/// is enough for a short aside.
class NoteCard extends StatelessWidget {
  const NoteCard(
    this.body, {
    super.key,
    this.title,
    this.icon = Icons.info_outline,
    this.tone,
    this.margin = const EdgeInsets.fromLTRB(16, 20, 16, 0),
  });

  final String body;
  final String? title;
  final IconData icon;

  /// Tint for the icon and heading. Defaults to the quiet treatment, which is
  /// what a disclaimer wants. Pass `c.accent` or `c.down` for a note that is
  /// actually asking for attention.
  final Color? tone;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    final c = context.c;
    final tint = tone ?? c.faint;

    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: tint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: TextStyle(
                        color: tone ?? c.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    body,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme.dart';

/// When a real [Icon] is supplied to a CTA, drop any leading symbol/whitespace
/// run from the label  so a legacy "+ " / "\u2197 " baked into an i18n string
/// can't double up beside the Material icon (and glyphs can't creep back into
/// CTA labels). Only the leading non-alphanumeric run is removed; interior
/// punctuation like the slash in "Fund / top up" is untouched.
String _labelForIcon(String s) =>
    s.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();

/// v5 `.ctafull`  primary action. `c.text` fill, `c.bg` ink, full-width with
/// a 16px side margin. Pass [icon] for a leading Material glyph (never a
/// unicode character); its colour inherits the button's foreground.
class CtaFull extends StatelessWidget {
  const CtaFull({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = icon == null ? label : _labelForIcon(label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: c.text,
            foregroundColor: c.bg,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// v5 `.ctaghost`  secondary action. Transparent, muted text, `line2` border.
/// Pass [icon] for a leading Material glyph; its colour inherits the foreground.
class CtaGhost extends StatelessWidget {
  const CtaGhost({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final text = icon == null ? label : _labelForIcon(label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: c.muted,
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: BorderSide(color: c.line2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

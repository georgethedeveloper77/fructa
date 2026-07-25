import 'package:flutter/material.dart';

import '../theme.dart';
import 'markup.dart';

/// v5 `.srow`  icon tile + title/sub + trailing. Pass an [fructaToggle] (or
/// any widget) as [trailing]; otherwise a chevron shows when [onTap] is set.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.iconTint,
  });

  /// Material icon shown in the 32px tile (never an emoji  house rule).
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  /// Optional tint: when set, the icon tile is washed with this colour and the
  /// icon takes it, used to give a settings section one calm colour. Null keeps
  /// the neutral grey tile.
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: c.line))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconTint == null
                    ? c.s3
                    : iconTint!.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: iconTint ?? c.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!, style: TextStyle(color: c.muted, fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right, color: c.faint, size: 20),
          ],
        ),
      ),
    );
  }
}

/// v5 `.kvrow`  label / mono value with a bottom hairline. Self-contained
/// (owns its 20px side padding); set [showDivider] false on the last row.
class KvRow extends StatelessWidget {
  const KvRow(
    this.k,
    this.v, {
    super.key,
    this.valueColor,
    this.showDivider = true,
  });

  final String k;
  final String v;
  final Color? valueColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: TextStyle(color: c.muted, fontSize: 12.5)),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? c.text,
                fontFamily: fructaFonts.mono,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum SignalTone { positive, negative, neutral }

/// v5 `.sig`  a tone-coloured tag chip + body copy. `**bold**` spans in
/// [text] render as emphasis (`c.text`, w500), matching v5's inline `<b>`.
/// Feed from `core/insights/signal_engine.dart` at the call site.
class SignalRow extends StatelessWidget {
  const SignalRow({
    super.key,
    required this.tag,
    required this.text,
    this.tone = SignalTone.neutral,
    this.showDivider = true,
  });

  final String tag;
  final String text;
  final SignalTone tone;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg) = switch (tone) {
      SignalTone.positive => (c.upSoft, c.up),
      SignalTone.negative => (c.downSoft, c.down),
      SignalTone.neutral => (c.s3, c.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag.toUpperCase(),
              style: TextStyle(
                color: fg,
                fontFamily: fructaFonts.mono,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.77,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: parseBold(
                  text,
                  base: TextStyle(color: c.muted, fontSize: 12.5, height: 1.55),
                  bold: TextStyle(
                    color: c.text,
                    fontSize: 12.5,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// v5 `.agent`  avatar + name/phone + call & WhatsApp actions. Kept decoupled
/// from the Agent model: the Company page maps `Agent` fields into these
/// primitives (avatar falls back to initials in the accent colour).
class AgentRow extends StatelessWidget {
  const AgentRow({
    super.key,
    required this.name,
    required this.phone,
    this.avatarText,
    this.avatarColor,
    this.onCall,
    this.onWhatsApp,
    this.showDivider = true,
  });

  final String name;
  final String phone;
  final String? avatarText;
  final Color? avatarColor;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsApp;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final av = avatarColor ?? c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: c.line)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: av.withValues(alpha: 0.18),
            ),
            child: Text(
              avatarText ?? _initials(name),
              style: TextStyle(
                color: av,
                fontFamily: fructaFonts.mono,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    phone,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11,
                      fontFamily: fructaFonts.mono,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onCall != null)
            ActionSquareButton(
              tooltip: 'Call',
              onTap: onCall!,
              child: Icon(Icons.call, size: 21, color: c.text),
            ),
          if (onWhatsApp != null) ...[
            const SizedBox(width: 10),
            ActionSquareButton(
              tooltip: 'WhatsApp',
              onTap: onWhatsApp!,
              child: const WhatsAppMark(size: 23),
            ),
          ],
        ],
      ),
    );
  }

  static String _initials(String n) {
    final parts = n
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// A square action button: `c.s2` fill, `c.line2` hairline border, 46px, radius
/// 13. Shared chrome for any icon-sized tap target that sits in a row of
/// actions. Used by [AgentRow] (call / WhatsApp) and by the company page's
/// Contact strip, so those buttons stay pixel-identical from one definition.
class ActionSquareButton extends StatelessWidget {
  const ActionSquareButton({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final btn = Material(
      color: c.s2,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: c.line2),
          ),
          child: child,
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Official WhatsApp glyph (Font Awesome brands path), drawn as a vector so it
/// needs no image asset or extra package. [size] is the box side; [color]
/// defaults to the WhatsApp brand green. Not an emoji/unicode glyph, a real
/// vector mark, so it satisfies the "no glyphs as icons" rule.
class WhatsAppMark extends StatelessWidget {
  const WhatsAppMark({
    super.key,
    this.size = 22,
    this.color = const Color(0xFF25D366),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _WhatsAppPainter(color));
}

class _WhatsAppPainter extends CustomPainter {
  const _WhatsAppPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Glyph spans ~0.875 wide x ~0.9375 tall in the unit box; nudge to centre.
    canvas.translate((s - 0.875 * s) / 2, (s - 0.9375 * s) / 2);
    final p = Path()
      ..moveTo(0.74395 * s, 0.18965 * s)
      ..cubicTo(0.66211 * s, 0.10762 * s, 0.55312 * s, 0.06250 * s,
          0.43730 * s, 0.06250 * s)
      ..cubicTo(0.19824 * s, 0.06250 * s, 0.00371 * s, 0.25703 * s,
          0.00371 * s, 0.49609 * s)
      ..cubicTo(0.00371 * s, 0.57246 * s, 0.02363 * s, 0.64707 * s,
          0.06152 * s, 0.71289 * s)
      ..lineTo(0.00000 * s, 0.93750 * s)
      ..lineTo(0.22988 * s, 0.87715 * s)
      ..cubicTo(0.29316 * s, 0.91172 * s, 0.36445 * s, 0.92988 * s,
          0.43711 * s, 0.92988 * s)
      ..lineTo(0.43730 * s, 0.92988 * s)
      ..cubicTo(0.67617 * s, 0.92988 * s, 0.87500 * s, 0.73535 * s,
          0.87500 * s, 0.49629 * s)
      ..cubicTo(0.87500 * s, 0.38047 * s, 0.82578 * s, 0.27168 * s,
          0.74395 * s, 0.18965 * s)
      ..lineTo(0.74395 * s, 0.18965 * s)
      ..close()
      ..moveTo(0.43730 * s, 0.85684 * s)
      ..cubicTo(0.37246 * s, 0.85684 * s, 0.30898 * s, 0.83945 * s,
          0.25371 * s, 0.80664 * s)
      ..lineTo(0.24062 * s, 0.79883 * s)
      ..lineTo(0.10430 * s, 0.83457 * s)
      ..lineTo(0.14062 * s, 0.70156 * s)
      ..lineTo(0.13203 * s, 0.68789 * s)
      ..cubicTo(0.09590 * s, 0.63047 * s, 0.07695 * s, 0.56426 * s,
          0.07695 * s, 0.49609 * s)
      ..cubicTo(0.07695 * s, 0.29746 * s, 0.23867 * s, 0.13574 * s,
          0.43750 * s, 0.13574 * s)
      ..cubicTo(0.53379 * s, 0.13574 * s, 0.62422 * s, 0.17324 * s,
          0.69219 * s, 0.24141 * s)
      ..cubicTo(0.76016 * s, 0.30957 * s, 0.80195 * s, 0.40000 * s,
          0.80176 * s, 0.49629 * s)
      ..cubicTo(0.80176 * s, 0.69512 * s, 0.63594 * s, 0.85684 * s,
          0.43730 * s, 0.85684 * s)
      ..lineTo(0.43730 * s, 0.85684 * s)
      ..close()
      ..moveTo(0.63496 * s, 0.58691 * s)
      ..cubicTo(0.62422 * s, 0.58145 * s, 0.57090 * s, 0.55527 * s,
          0.56094 * s, 0.55176 * s)
      ..cubicTo(0.55098 * s, 0.54805 * s, 0.54375 * s, 0.54629 * s,
          0.53652 * s, 0.55723 * s)
      ..cubicTo(0.52930 * s, 0.56816 * s, 0.50859 * s, 0.59238 * s,
          0.50215 * s, 0.59980 * s)
      ..cubicTo(0.49590 * s, 0.60703 * s, 0.48945 * s, 0.60801 * s,
          0.47871 * s, 0.60254 * s)
      ..cubicTo(0.41504 * s, 0.57070 * s, 0.37324 * s, 0.54570 * s,
          0.33125 * s, 0.47363 * s)
      ..cubicTo(0.32012 * s, 0.45449 * s, 0.34238 * s, 0.45586 * s,
          0.36309 * s, 0.41445 * s)
      ..cubicTo(0.36660 * s, 0.40723 * s, 0.36484 * s, 0.40098 * s,
          0.36211 * s, 0.39551 * s)
      ..cubicTo(0.35937 * s, 0.39004 * s, 0.33770 * s, 0.33672 * s,
          0.32871 * s, 0.31504 * s)
      ..cubicTo(0.31992 * s, 0.29395 * s, 0.31094 * s, 0.29688 * s,
          0.30430 * s, 0.29648 * s)
      ..cubicTo(0.29805 * s, 0.29609 * s, 0.29082 * s, 0.29609 * s,
          0.28359 * s, 0.29609 * s)
      ..cubicTo(0.27637 * s, 0.29609 * s, 0.26465 * s, 0.29883 * s,
          0.25469 * s, 0.30957 * s)
      ..cubicTo(0.24473 * s, 0.32051 * s, 0.21680 * s, 0.34668 * s,
          0.21680 * s, 0.40000 * s)
      ..cubicTo(0.21680 * s, 0.45332 * s, 0.25566 * s, 0.50488 * s,
          0.26094 * s, 0.51211 * s)
      ..cubicTo(0.26641 * s, 0.51934 * s, 0.33730 * s, 0.62871 * s,
          0.44609 * s, 0.67578 * s)
      ..cubicTo(0.51484 * s, 0.70547 * s, 0.54180 * s, 0.70801 * s,
          0.57617 * s, 0.70293 * s)
      ..cubicTo(0.59707 * s, 0.69980 * s, 0.64023 * s, 0.67676 * s,
          0.64922 * s, 0.65137 * s)
      ..cubicTo(0.65820 * s, 0.62598 * s, 0.65820 * s, 0.60430 * s,
          0.65547 * s, 0.59980 * s)
      ..cubicTo(0.65293 * s, 0.59492 * s, 0.64570 * s, 0.59219 * s,
          0.63496 * s, 0.58691 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_WhatsAppPainter old) => old.color != color;
}

/// A rounded card that houses a run of rows (typically [SettingsRow]s). The last
/// child should set `showDivider: false`. Insets from the screen edge so grouped
/// settings read as organized rather than edge-to-edge.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

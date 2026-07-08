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
  });

  /// Material icon shown in the 32px tile (never an emoji  house rule).
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

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
                color: c.s3,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: c.muted),
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
            ),
          ),
          if (onCall != null) _AgentBtn(icon: Icons.call, onTap: onCall!),
          if (onWhatsApp != null) ...[
            const SizedBox(width: 7),
            _AgentBtn(icon: Icons.chat_bubble_outline, onTap: onWhatsApp!),
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

class _AgentBtn extends StatelessWidget {
  const _AgentBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.s2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line2),
        ),
        child: Icon(icon, size: 15, color: c.text),
      ),
    );
  }
}

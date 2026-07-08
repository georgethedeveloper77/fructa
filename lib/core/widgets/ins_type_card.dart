import 'package:flutter/material.dart';

import '../theme.dart';

/// v5 `.instype`. Emoji/glyph tile + label + mono sub. Designed to sit in a
/// 2-column grid (`GridView`/`Row` of two) on Insure and Add-holding.
class InsTypeCard extends StatelessWidget {
  const InsTypeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  /// Material icon shown in the tile (never an emoji  house rule).
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: c.s3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: c.accent),
            ),
            Text(
              label,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              sub,
              style: TextStyle(
                color: c.faint,
                fontSize: 10.5,
                fontFamily: fructaFonts.mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

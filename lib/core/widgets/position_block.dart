import 'package:flutter/material.dart';

import '../theme.dart';

/// v5 `.pos`  a big mono [value] with an optional mono [delta] line that can
/// carry a trailing Inter [sub] (e.g. "(1.3%) this month"). [deltaColor]
/// defaults to `up`; pass `context.c.delta(x)` for sign-aware colouring.
class PositionBlock extends StatelessWidget {
  const PositionBlock({
    super.key,
    required this.value,
    this.delta,
    this.deltaColor,
    this.sub,
  });

  final String value;
  final String? delta;
  final Color? deltaColor;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 27,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
          if (delta != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: deltaColor ?? c.up,
                    fontFamily: fructaFonts.mono,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(text: delta),
                    if (sub != null)
                      TextSpan(
                        text: '  $sub',
                        style: TextStyle(
                          color: c.muted,
                          fontFamily: fructaFonts.sans,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

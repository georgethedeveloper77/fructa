import 'package:flutter/material.dart';

import '../theme.dart';

/// v5 `.tog`. 40×24 pill toggle. Off = `s3` fill / `line2` border / faint
/// thumb; on = `accentSoft` fill / `accent` border / accent thumb slid right.
/// Accent-driven (never hardcoded gold), so it tracks the selected accent.
class fructaToggle extends StatelessWidget {
  const fructaToggle({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 40,
        height: 24,
        decoration: BoxDecoration(
          color: value ? c.accentSoft : c.s3,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: value ? c.accent : c.line2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? c.accent : c.faint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

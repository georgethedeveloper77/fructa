import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/theme_controller.dart';

/// Appearance controls  the payoff of A1. Mode segmented control + accent
/// swatch row, both driving [themeControllerProvider]. Changes animate because
/// fructaColors implements lerp.
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final app = ref.watch(themeControllerProvider);
    final ctrl = ref.read(themeControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ModeSegmented(mode: app.mode, onChanged: ctrl.setMode),
        const SizedBox(height: 16),
        Text(
          'ACCENT',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: c.faint,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final a in fructaAccent.values) ...[
              _Swatch(
                accent: a,
                selected: a == app.accent,
                onTap: () => ctrl.setAccent(a),
              ),
              if (a != fructaAccent.values.last) const SizedBox(width: 12),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'TEXT SIZE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            color: c.faint,
          ),
        ),
        const SizedBox(height: 10),
        _TextSizeSegmented(scale: app.textScale, onChanged: ctrl.setTextScale),
      ],
    );
  }
}

class _TextSizeSegmented extends StatelessWidget {
  const _TextSizeSegmented({required this.scale, required this.onChanged});

  final double scale;
  final ValueChanged<double> onChanged;

  // (multiplier, label). Matches ThemeController._scaleFrom clamp range.
  static const _sizes = <(double, String)>[
    (0.9, 'S'),
    (1.0, 'M'),
    (1.15, 'L'),
    (1.3, 'XL'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.s3,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (mult, label) in _sizes)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(mult),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (scale - mult).abs() < 0.001
                        ? c.s1
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: (scale - mult).abs() < 0.001 ? c.text : c.muted,
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

class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static const _labels = {
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.s3,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final e in _labels.entries)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e.key == mode ? c.s1 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: e.key == mode ? c.text : c.muted,
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

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final fructaAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? c.text : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 18, color: accent.onColor)
            : null,
      ),
    );
  }
}

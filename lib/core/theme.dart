import 'package:flutter/material.dart';

/// fructa design tokens.
///
/// Single source of truth for colour. Ported 1:1 from the locked v5 UI
/// (`fructa_mobile_v5.html` :root) for dark, with a derived light palette.
/// Everything is exposed as a [ThemeExtension] so widgets read tokens via
/// `context.c.<token>` and get light/dark + accent switching for free.
///
/// Migration rule (A1 sweep): replace every hard-coded `Color(0x..)` /
/// `Colors.*` in feature code with `context.c.<token>`. Nothing should read a
/// raw hex outside this file except brand colours (which come from data).

// ─────────────────────────────────────────────────────────────────────────
// Accents  the 5 selectable accents. Each carries the accent colour, the
// ink that sits legibly on top of it, and a soft-fill alpha per brightness.
// All five already exist in the v5 palette, so nothing looks foreign.
// ─────────────────────────────────────────────────────────────────────────

enum fructaAccent { gold, sky, emerald, iris, amber }

extension fructaAccentX on fructaAccent {
  String get label => switch (this) {
    fructaAccent.gold => 'Gold',
    fructaAccent.sky => 'Sky',
    fructaAccent.emerald => 'Emerald',
    fructaAccent.iris => 'Iris',
    fructaAccent.amber => 'Amber',
  };

  /// The accent colour itself.
  Color get color => switch (this) {
    fructaAccent.gold => const Color(0xFFE7B24C),
    fructaAccent.sky => const Color(0xFF4E8FE8),
    fructaAccent.emerald => const Color(0xFF2FB5A0),
    fructaAccent.iris => const Color(0xFF9A8BF3),
    fructaAccent.amber => const Color(0xFFF0B542),
  };

  /// Ink that sits on top of a filled accent surface (buttons, pills).
  Color get onColor => switch (this) {
    // Gold/Amber are light enough to need dark ink (matches --gold-ink).
    fructaAccent.gold => const Color(0xFF191204),
    fructaAccent.amber => const Color(0xFF1A1304),
    // Mid-tone accents take near-white ink.
    fructaAccent.sky ||
    fructaAccent.emerald ||
    fructaAccent.iris => const Color(0xFFFFFFFF),
  };

  /// Soft translucent fill of the accent (chips, glows). Slightly stronger on
  /// light so it stays visible against white surfaces.
  Color soft(Brightness b) =>
      color.withValues(alpha: b == Brightness.dark ? 0.14 : 0.16);
}

// ─────────────────────────────────────────────────────────────────────────
// Token set.
// ─────────────────────────────────────────────────────────────────────────

@immutable
class fructaColors extends ThemeExtension<fructaColors> {
  const fructaColors({
    required this.brightness,
    required this.accentKind,
    // surfaces
    required this.bg,
    required this.s1,
    required this.s2,
    required this.s3,
    // hairlines
    required this.line,
    required this.line2,
    // text
    required this.text,
    required this.muted,
    required this.faint,
    // semantic movement
    required this.up,
    required this.upSoft,
    required this.down,
    required this.downSoft,
    // resolved accent trio (already blended for this brightness)
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentInk,
  });

  final Brightness brightness;
  final fructaAccent accentKind;

  final Color bg;
  final Color s1;
  final Color s2;
  final Color s3;

  final Color line;
  final Color line2;

  final Color text;
  final Color muted;
  final Color faint;

  final Color up;
  final Color upSoft;
  final Color down;
  final Color downSoft;

  final Color accent;
  final Color onAccent;
  final Color accentSoft;

  /// Accent as legible TEXT on a light/soft surface. On dark the accent reads
  /// fine as-is; on light it's darkened so gold/amber stop washing out.
  final Color accentInk;

  bool get isDark => brightness == Brightness.dark;

  /// Sign-aware colour for a delta (rate move, P/L). Zero → muted.
  Color delta(num v) => v > 0 ? up : (v < 0 ? down : muted);
  Color deltaSoft(num v) => v > 0 ? upSoft : (v < 0 ? downSoft : line);

  // ── Dark  ported verbatim from v5 :root ────────────────────────────────
  factory fructaColors.dark(fructaAccent a) => fructaColors(
    brightness: Brightness.dark,
    accentKind: a,
    bg: const Color(0xFF060709),
    s1: const Color(0xFF0D0F13),
    s2: const Color(0xFF13161C),
    s3: const Color(0xFF1A1E26),
    line: const Color(0xFF1B1F27),
    line2: const Color(0xFF282D37),
    text: const Color(0xFFF3F5F8),
    muted: const Color(0xFF9AA2B2),
    faint: const Color(0xFF7A8290),
    up: const Color(0xFF3DDC97),
    upSoft: const Color(0x1C3DDC97), // rgba(61,220,151,.11)
    down: const Color(0xFFFF6B6B),
    downSoft: const Color(0x1CFF6B6B), // rgba(255,107,107,.11)
    accent: a.color,
    onAccent: a.onColor,
    accentSoft: a.soft(Brightness.dark),
    accentInk: a.color,
  );

  // ── Light  derived: same cool-neutral character, inverted for legibility ─
  factory fructaColors.light(fructaAccent a) => fructaColors(
    brightness: Brightness.light,
    accentKind: a,
    bg: const Color(0xFFF4F6FA),
    s1: const Color(0xFFFFFFFF),
    s2: const Color(0xFFEEF1F6),
    s3: const Color(0xFFE4E9F0),
    line: const Color(0xFFE1E5EC),
    line2: const Color(0xFFCDD4DE),
    text: const Color(0xFF0E1116),
    muted: const Color(0xFF5A6472),
    faint: const Color(0xFF7C8492),
    up: const Color(0xFF12A46B), // darker green holds contrast on white
    upSoft: const Color(0x1F12A46B),
    down: const Color(0xFFE5484D),
    downSoft: const Color(0x1FE5484D),
    accent: a.color,
    onAccent: a.onColor,
    accentSoft: a.soft(Brightness.light),
    accentInk: Color.lerp(a.color, const Color(0xFF0E1116), 0.42)!,
  );

  factory fructaColors.resolve(Brightness b, fructaAccent a) =>
      b == Brightness.dark ? fructaColors.dark(a) : fructaColors.light(a);

  @override
  fructaColors copyWith({
    Brightness? brightness,
    fructaAccent? accentKind,
    Color? bg,
    Color? s1,
    Color? s2,
    Color? s3,
    Color? line,
    Color? line2,
    Color? text,
    Color? muted,
    Color? faint,
    Color? up,
    Color? upSoft,
    Color? down,
    Color? downSoft,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? accentInk,
  }) {
    return fructaColors(
      brightness: brightness ?? this.brightness,
      accentKind: accentKind ?? this.accentKind,
      bg: bg ?? this.bg,
      s1: s1 ?? this.s1,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      up: up ?? this.up,
      upSoft: upSoft ?? this.upSoft,
      down: down ?? this.down,
      downSoft: downSoft ?? this.downSoft,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentInk: accentInk ?? this.accentInk,
    );
  }

  @override
  fructaColors lerp(ThemeExtension<fructaColors>? other, double t) {
    if (other is! fructaColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return fructaColors(
      // discrete fields snap at the midpoint
      brightness: t < 0.5 ? brightness : other.brightness,
      accentKind: t < 0.5 ? accentKind : other.accentKind,
      bg: c(bg, other.bg),
      s1: c(s1, other.s1),
      s2: c(s2, other.s2),
      s3: c(s3, other.s3),
      line: c(line, other.line),
      line2: c(line2, other.line2),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      up: c(up, other.up),
      upSoft: c(upSoft, other.upSoft),
      down: c(down, other.down),
      downSoft: c(downSoft, other.downSoft),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentInk: c(accentInk, other.accentInk),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Typography families. v5 uses Inter for text and Space Grotesk for numerics
// (the `.num` class). Add both to pubspec assets (or wire google_fonts) and
// keep these names in sync.
// ─────────────────────────────────────────────────────────────────────────

abstract final class fructaFonts {
  static const sans = 'Inter';
  static const mono = 'SpaceGrotesk'; // tabular-figure face for rates/money
}

// ─────────────────────────────────────────────────────────────────────────
// ThemeData builder  attaches the tokens as an extension and wires the
// Material ColorScheme + common component defaults off the same tokens so
// stock widgets (SnackBar, Switch, dividers…) inherit the look.
// ─────────────────────────────────────────────────────────────────────────

ThemeData buildfructaTheme({
  required Brightness brightness,
  required fructaAccent accent,
}) {
  final c = fructaColors.resolve(brightness, accent);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    surface: c.s1,
    onSurface: c.text,
    surfaceContainerHighest: c.s3,
    error: c.down,
    onError: c.isDark ? const Color(0xFF19060A) : Colors.white,
    outline: c.line2,
    outlineVariant: c.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    fontFamily: fructaFonts.sans,
    splashFactory: NoSplash.splashFactory,
    extensions: [c],
    textTheme: _textTheme(c),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.muted),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.s3,
      contentTextStyle: TextStyle(color: c.text),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.s3,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.s1,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    // v5 `.slider`: a flat 4px `line2` track (no accent fill) with a 19px
    // accent thumb ringed by a 3px `bg` border. Every Slider inherits this.
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: c.line2,
      inactiveTrackColor: c.line2,
      thumbColor: c.accent,
      overlayColor: c.accentSoft,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      trackShape: const RoundedRectSliderTrackShape(),
      thumbShape: _fructaSliderThumb(ring: c.bg, core: c.accent),
    ),
  );
}

/// A 19px thumb: an [core]-filled disc inside a 3px [ring] border  matches
/// v5's `.slider::-webkit-slider-thumb{...;border:3px solid var(--bg)}`.
class _fructaSliderThumb extends SliderComponentShape {
  const _fructaSliderThumb({required this.ring, required this.core});

  final Color ring;
  final Color core;

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) =>
      const Size.fromRadius(9.5);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 9.5, Paint()..color = ring); // 3px bg ring
    canvas.drawCircle(center, 6.5, Paint()..color = core); // accent core
  }
}

TextTheme _textTheme(fructaColors c) {
  final base = TextStyle(color: c.text, fontFamily: fructaFonts.sans);
  return TextTheme(
    displayLarge: base.copyWith(fontFamily: fructaFonts.mono),
    headlineSmall: base.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: base,
    bodyMedium: base.copyWith(color: c.muted),
    labelSmall: base.copyWith(color: c.faint),
  );
}

/// Ergonomic access: `context.c.up`, `context.c.accent`, …
///
/// Falls back to the dark tokens if the theme wasn't built with
/// [buildfructaTheme] (e.g. a Cupertino subtree, or before main.dart is wired).
/// This prevents a null-crash  but if you're seeing dark colours in light
/// mode, it means the extension is missing: build MaterialApp.theme/darkTheme
/// with buildfructaTheme() so switching actually works.
extension fructaColorsContext on BuildContext {
  fructaColors get c =>
      Theme.of(this).extension<fructaColors>() ??
      fructaColors.dark(fructaAccent.gold);
}

// ─────────────────────────────────────────────────────────────────────────
// Backward-compat shim (A1-fix).
//
// Phase 0–5 screens reference the old `AppColors.*`. That class was removed in
// the A1 rewrite; these const values re-expose exactly the members the code
// uses, mapped to the v5 **dark** tokens above  so old screens compile and
// look identical. They're static const, which also restores const widgets that
// used them.
//
// This is a bridge, not the destination: migrate each call site to
// `context.c.<token>` as B1/B2 rewrite those screens (that's what gives them
// light-mode + accent support), then delete this class.
// ─────────────────────────────────────────────────────────────────────────
abstract final class AppColors {
  static const bg = Color(0xFF060709); // → tokens.bg
  static const panel = Color(0xFF0D0F13); // → s1
  static const panel2 = Color(0xFF13161C); // → s2
  static const line = Color(0xFF1B1F27); // → line
  static const ink = Color(0xFFF3F5F8); // → text (primary)
  static const mute = Color(0xFF8A92A3); // → muted
  static const faint = Color(0xFF555D6B); // → faint
  static const gold = Color(0xFFE7B24C); // → gold accent
  static const live = Color(0xFF3DDC97); // → up
  static const bad = Color(0xFFFF6B6B); // → down
}

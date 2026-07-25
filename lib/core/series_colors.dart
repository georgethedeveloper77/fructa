import 'package:flutter/painting.dart';

/// Chart **series** colours  the line identities for multi-fund overlays
/// (Compare) and any future multi-series chart.
///
/// These are *data* colours, not theme tokens: like [AssetClass] and category
/// colours, a series must keep a stable, distinguishable identity across light
/// and dark. Theming them per-mode would let two lines collide or one wash out,
/// so they are intentionally mode-independent. Centralised here so no feature
/// widget carries raw hex, and so the palette has a single place to tune.
/// The first four are unchanged and stay in position: Compare caps at four
/// series (kMaxCompare) and never reaches past index 3, so extending the list
/// cannot move a colour anybody is already looking at.
///
/// Four to eight were added for the portfolio allocation donut, which colours
/// one slice per HOLDING rather than per category. Four colours cycling across
/// six holdings puts two identical slices in one ring, which is the same as not
/// colouring them at all. Every hue below already exists in the app's data
/// palettes (see category_colors.dart): nothing new was invented, they are
/// simply gathered into one ordered ramp.
const List<Color> kSeriesColors = [
  Color(0xFFE7B24C), // gold (accent family)
  Color(0xFF4E8FE8), // sky
  Color(0xFF2FB5A0), // emerald
  Color(0xFF9A8BF3), // iris
  Color(0xFFE7784C), // ember
  Color(0xFF31B7C2), // cyan
  Color(0xFFEC8FB0), // pink
  Color(0xFF34D399), // green
];

/// Colour for series [i], cycling if there are more series than colours.
Color seriesColor(int i) => kSeriesColors[i % kSeriesColors.length];

// ── bar geometry ──────────────────────────────────────────────────────────
//
// Every bar in the app was a flat rectangle of one colour running in a neutral
// grey channel, which made a coloured row read as mostly grey with a dab of
// colour at the left. Two helpers, centralised here beside the palette so no
// feature file carries an alpha value and there is one place to tune the whole
// app's bars.

/// The fill for a bar of [c]: a shade under strength at the root, full at the
/// tip.
///
/// Left to right on purpose. A bar grows from its root, so the brightest part
/// is the end that carries the value, and the eye lands where the number is
/// rather than in the middle of a flat slab.
LinearGradient barFill(Color c) => LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [c.withValues(alpha: 0.55), c],
);

/// The channel a bar of [c] runs in.
///
/// Tinted with the series colour rather than a neutral surface token. This is
/// the change that does most of the work: with a grey track, a row reads as
/// grey furniture that happens to contain some colour; with a tinted one the
/// whole row belongs to its series and the bar is the filled part of something
/// that was already its own.
Color barTrack(Color c) => c.withValues(alpha: 0.13);

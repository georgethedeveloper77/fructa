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

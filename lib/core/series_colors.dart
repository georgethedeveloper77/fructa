import 'package:flutter/painting.dart';

/// Chart **series** colours  the line identities for multi-fund overlays
/// (Compare) and any future multi-series chart.
///
/// These are *data* colours, not theme tokens: like [AssetClass] and category
/// colours, a series must keep a stable, distinguishable identity across light
/// and dark. Theming them per-mode would let two lines collide or one wash out,
/// so they are intentionally mode-independent. Centralised here so no feature
/// widget carries raw hex, and so the palette has a single place to tune.
const List<Color> kSeriesColors = [
  Color(0xFFE7B24C), // gold (accent family)
  Color(0xFF4E8FE8), // sky
  Color(0xFF2FB5A0), // emerald
  Color(0xFF9A8BF3), // iris
];

/// Colour for series [i], cycling if there are more series than colours.
Color seriesColor(int i) => kSeriesColors[i % kSeriesColors.length];

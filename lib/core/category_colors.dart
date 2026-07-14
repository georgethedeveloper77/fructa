import 'package:flutter/material.dart';

/// Legacy `category` keys. Kept because tiles, filters and the compare matrix
/// still key off category for the instrument rows (T-bill, bond, SACCO, stock,
/// insurance).
///
/// THE CIS KEYS HERE MUST AGREE WITH [fundTypeColors], AND THEY DID NOT.
///
/// 'equity' was amber (0xFFF0A24C) here and iris (0xFF9A8BF3) in fundTypeColors,
/// so one equity fund could render in two different colours depending on which
/// map the surface happened to reach for. Worse, 'balanced' here was 0xFF9A8BF3,
/// which is EXACTLY the colour fundTypeColors gives to 'equity': a balanced fund
/// keyed by category was indistinguishable from an equity fund keyed by
/// fund_type. Since fund_type is the authoritative column and the four new asset
/// classes all key on it, the CIS entries below now defer to fundTypeColors and
/// there is one colour per fund type, whichever door a widget comes in by.
const categoryColors = <String, Color>{
  'mmf_kes': Color(0xFFE0B34C), // gold
  'mmf_usd': Color(0xFF6AA6F0), // blue
  'tbill': Color(0xFF4FD0B5), // teal
  'bond': Color(0xFFA99BF5), // purple
  'sacco': Color(0xFF34D399), // green
  'stock': Color(0xFFFB6B6B), // red
  'equity': Color(0xFF9A8BF3), // iris   (matches fundTypeColors['equity'])
  'balanced': Color(0xFFE7784C), // ember  (matches fundTypeColors['balanced'])
  'islamic': Color(0xFF2FB5A0), // emerald
  'reit': Color(0xFF31B7C2), // cyan
  'insurance': Color(0xFF4E8FE8), // sky
};

Color categoryColor(String c) => categoryColors[c] ?? const Color(0xFF8A92A3);

/// Fund-type colours for the market-allocation donut. Data colours (like
/// [categoryColors] and AssetClass), centralised so no widget carries raw hex.
/// Hue assignment mirrors the v6 mockup: MMF gold, FI sky, Equity iris,
/// Balanced ember, Special emerald. Keyed by `funds.fund_type`.
const fundTypeColors = <String, Color>{
  'mmf': Color(0xFFE0B34C), // gold
  'fixed_income': Color(0xFF4E8FE8), // sky
  'equity': Color(0xFF9A8BF3), // iris
  'balanced': Color(0xFFE7784C), // ember
  'special': Color(0xFF2FB5A0), // emerald
};

Color fundTypeColor(String? t) =>
    fundTypeColors[t] ?? const Color(0xFF8A92A3);

/// Asset-class colours for the CMA market-allocation view (where the market's
/// money actually sits). Keyed by the CIS class keys published under
/// `market.asset_classes`. Data colours, centralised like [fundTypeColors] so
/// no widget carries raw hex.
const assetClassColors = <String, Color>{
  'gok': Color(0xFFE0B34C), // gold, government securities
  'fixed_deposits': Color(0xFF4E8FE8), // sky
  'cash': Color(0xFF34D399), // green
  'unlisted': Color(0xFF9A8BF3), // iris
  'listed': Color(0xFF2FB5A0), // emerald
  'offshore': Color(0xFFE7784C), // ember
  'other_cis': Color(0xFF31B7C2), // cyan
  'alternative': Color(0xFFEC8FB0), // pink
};

Color assetClassColor(String? k) =>
    assetClassColors[k] ?? const Color(0xFF8A92A3);

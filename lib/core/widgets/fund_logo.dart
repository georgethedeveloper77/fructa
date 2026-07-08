import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Company logo with a brand-tinted monogram fallback.
///
/// Network logos are cached (cached_network_image) and render on a **white
/// circular chip** so a brand mark reads on both light and dark themes and
/// isn't oddly cropped (BoxFit.contain). House standard: a 512×512 square brand
/// mark. `logoUrl` overrides the domain lookup; `brandColor` tints the monogram
/// (also used as the placeholder/error state).
class FundLogo extends StatelessWidget {
  final String? domain;
  final String? logoUrl;
  final Color? brandColor;
  final String seed; // usually the manager name
  final double size;
  const FundLogo({
    super.key,
    required this.domain,
    required this.seed,
    this.logoUrl,
    this.brandColor,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final monogram = _Monogram(seed: seed, size: size, brand: brandColor);
    // Supabase-hosted logo only. Clearbit's logo API was retired, so a bare
    // domain no longer resolves to an image  fall through to the brand
    // monogram instead of firing a request that always 404s.
    final src = (logoUrl != null && logoUrl!.isNotEmpty) ? logoUrl! : null;
    if (src == null) return monogram;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white, // neutral chip → visible on any theme
        border: Border.all(color: c.line),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: CachedNetworkImage(
          imageUrl: src,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (_, __) => monogram,
          errorWidget: (_, __, ___) => monogram,
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final String seed;
  final double size;
  final Color? brand;
  const _Monogram({required this.seed, required this.size, this.brand});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = brand ?? c.accent;
    final letter = seed.trim().isEmpty ? '?' : seed.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.12),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: tint,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

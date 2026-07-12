import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Company / insurer logo with a brand-tinted monogram fallback.
///
/// Resolution order:
///   1. [logoUrl]  an explicit (usually Supabase-hosted) image, highest quality.
///   2. [domain]   resolved to a logo through Google's favicon service, which
///                 still works and returns a PNG (Clearbit's logo API was
///                 retired, so a bare domain no longer resolves there).
///   3. monogram   brand-tinted initial, shown while loading and on any error.
///
/// Network logos are cached (cached_network_image) and render on a **white
/// circular chip** so a brand mark reads on both light and dark themes and
/// isn't oddly cropped (BoxFit.contain). Because the error state falls back to
/// the monogram, a domain that has no icon degrades cleanly instead of blank.
class FundLogo extends StatelessWidget {
  final String? domain;
  final String? logoUrl;
  final Color? brandColor;
  final String seed; // usually the manager / insurer name
  final double size;
  const FundLogo({
    super.key,
    required this.domain,
    required this.seed,
    this.logoUrl,
    this.brandColor,
    this.size = 40,
  });

  /// Build a logo URL from a bare domain via Google's favicon service. Strips
  /// any scheme, `www.`, and path so a stored value like "https://cic.co.ke/"
  /// still resolves. Returns null when there's nothing usable.
  static String? _fromDomain(String? domain) {
    if (domain == null) return null;
    var d = domain.trim().toLowerCase();
    if (d.isEmpty) return null;
    d = d.replaceFirst(RegExp(r'^https?://'), '');
    d = d.replaceFirst(RegExp(r'^www\.'), '');
    d = d.split('/').first.split('?').first;
    if (d.isEmpty || !d.contains('.')) return null;
    return 'https://www.google.com/s2/favicons?sz=128&domain=$d';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final monogram = _Monogram(seed: seed, size: size, brand: brandColor);

    // Prefer an explicit hosted logo; otherwise resolve the domain to a favicon.
    final src = (logoUrl != null && logoUrl!.isNotEmpty)
        ? logoUrl!
        : _fromDomain(domain);
    if (src == null) return monogram;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white, // neutral chip -> visible on any theme
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

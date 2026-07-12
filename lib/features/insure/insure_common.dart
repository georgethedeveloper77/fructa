import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurer.dart';
import '../../data/models/remote_config.dart';
import '../../data/snapshot_providers.dart';

// ── config-first copy ────────────────────────────────────────────────────
// Admin-editable copy: the config value wins when set, otherwise the baked
// i18n string. So the UI is never blank and every string is release-free
// editable from the Config page.

String rcText(RemoteConfig rc, String key) => rc.string(key, t(key));

List<String> rcBullets(RemoteConfig rc, String key, List<String> fallback) =>
    rc.stringList(key, fallback);

// ── colour + icon helpers ────────────────────────────────────────────────

/// Parse an insurer brand hex ("#RRGGBB" / "RRGGBB") to a Color, or null. This
/// is a data colour (per-insurer), the documented exception to theme-only.
Color? hexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Raw brand colour for an insurer (logo + glow), falling back to the insurance
/// category colour. Use [context.c.brandOnBg] on top for text/stroke legibility.
Color insurerBrand(BuildContext context, Insurer i) =>
    hexColor(i.brandColor) ?? categoryColor('insurance');

/// Material icon for an admin-set type icon name (never an emoji).
IconData insureTypeIcon(String? name) => switch ((name ?? '').toLowerCase()) {
      'motor' || 'car' => Icons.directions_car_outlined,
      'travel' || 'flight' => Icons.flight_outlined,
      'life' => Icons.favorite_outline,
      'medical' || 'health' => Icons.local_hospital_outlined,
      'home' || 'property' => Icons.home_outlined,
      'business' => Icons.business_outlined,
      'marine' => Icons.directions_boat_outlined,
      _ => Icons.shield_outlined,
    };

String regionLabel(String key) => t('insure.region.$key');

/// Category icon: plays [lottieUrl] when set, otherwise (and while the animation
/// loads, or if it fails) shows the Material [icon]. The animation is authored
/// with its own colours; [color] applies only to the Material fallback.
class TypeIcon extends StatelessWidget {
  const TypeIcon({
    super.key,
    required this.icon,
    required this.color,
    this.lottieUrl,
    this.lottieAsset,
    this.size = 21,
  });

  final IconData icon;
  final Color color;
  final String? lottieUrl; // admin-set network animation (wins)
  final String? lottieAsset; // bundled fallback, e.g. assets/lottie/motor.json
  final double size;

  @override
  Widget build(BuildContext context) {
    final box = size * 1.5;
    final material = Icon(icon, size: size, color: color);

    // Bundled asset layer (or the Material icon if no asset ships for this key).
    Widget assetLayer() {
      final a = lottieAsset;
      if (a == null || a.isEmpty) return Center(child: material);
      return Lottie.asset(
        a,
        fit: BoxFit.contain,
        repeat: true,
        frameBuilder: (context, child, composition) =>
            composition == null ? Center(child: material) : child,
        errorBuilder: (context, error, stack) => Center(child: material),
      );
    }

    // Priority: admin URL -> bundled asset -> Material icon. The network layer
    // shows the asset (or icon) while loading and on any failure, so a bad or
    // missing URL degrades gracefully instead of showing nothing.
    final url = lottieUrl;
    final Widget inner = (url != null && url.isNotEmpty)
        ? Lottie.network(
            url,
            fit: BoxFit.contain,
            repeat: true,
            frameBuilder: (context, child, composition) =>
                composition == null ? assetLayer() : child,
            errorBuilder: (context, error, stack) => assetLayer(),
          )
        : assetLayer();

    return SizedBox(width: box, height: box, child: inner);
  }
}

double coverNum(String? cover) {
  final m = RegExp(r'[\d.]+').firstMatch(cover ?? '');
  return m == null ? 0 : (double.tryParse(m.group(0)!) ?? 0);
}

// ── shared widgets ───────────────────────────────────────────────────────

/// The one way an insurer logo is ever drawn.
///
/// Resolves the full chain that [FundLogo] expects: hosted company logo (the
/// `logos` bucket) first, then the insurer's own domain, then a brand-tinted
/// monogram. Every insure surface must use this rather than calling FundLogo
/// with a bare `domain:`, which is what caused every insurer to render as a
/// monogram even when its company had a real mark uploaded.
class InsurerLogo extends ConsumerWidget {
  const InsurerLogo(this.insurer, {super.key, this.size = 42});

  final Insurer insurer;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = insurer;
    return FundLogo(
      logoUrl: ref.watch(insurerLogoUrlProvider(i.companyId)),
      domain: i.logoDomain,
      seed: i.name,
      size: size,
      brandColor: insurerBrand(context, i),
    );
  }
}

/// Row of 5 rating stars (filled to [rating]). Material icons, not glyphs.
class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.size = 12});
  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size, color: c.accent),
      ],
    );
  }
}

/// Section heading matching the mockup `.h2` (mono, optional small trailing).
/// A section header, as the V8 mockup specifies it:
///
///   h2 { font-size:10px; font-weight:750; letter-spacing:1.1px;
///        text-transform:uppercase; color:var(--faint) }
///   h2 em { margin-left:auto }
///
/// This widget was rendering at 20px in mono and in c.text, which made every
/// section title on every insure screen a large black display heading. That
/// single discrepancy is most of why the app did not look like the design:
/// "How this ranks" and "Reach them" shouted where they were meant to whisper,
/// and the eye had no idea what the actual subject of the screen was.
///
/// The header is chrome. The premium, the chart and the rows are the content.
/// Chrome should be quiet.
class InsureH2 extends StatelessWidget {
  const InsureH2(this.title, {super.key, this.small});
  final String title;
  final String? small;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (small != null) ...[
            const SizedBox(width: 10),
            // margin-left:auto in the mockup. A single Expanded with an
            // end-aligned Text does that. A Spacer PLUS a Flexible does not:
            // they are both flex children, so they split the free space in
            // half, and the note ends up wrapping in the middle of the row
            // instead of sitting against the right margin.
            Expanded(
              child: Text(
                small!,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: c.faint,
                  fontSize: 9.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class InsureQuoteRow extends StatelessWidget {
  const InsureQuoteRow({
    super.key,
    required this.name,
    required this.brand,
    required this.priceText,
    required this.onTap,
    this.logoDomain,
    this.logoUrl,
    this.rateLabel,
    this.priceUnit,
    this.barFraction,
    this.meta,
    this.best = false,
  });

  final String name;
  final Color brand;
  final String priceText;
  final VoidCallback onTap;
  final String? logoDomain;
  final String? logoUrl;

  /// The rate mechanics, e.g. "3.00% band, floor 37,500" or "7.00% of value".
  /// Mono, because it is a figure, not prose.
  final String? rateLabel;

  /// e.g. "KES / year". Sits under the price.
  final String? priceUnit;

  /// This row's price as a share of the dearest on screen, 0..1. Null hides the
  /// bar, which is correct for a single-row list where there is no spread to
  /// show.
  final double? barFraction;

  /// Anything else worth a line (claims turnaround, cover ceiling).
  final String? meta;

  final bool best;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(18),
            // The cheapest row is outlined, not merely ticked. It is the answer
            // to the question the screen was opened to ask.
            border: Border.all(color: best ? c.accent : c.line),
          ),
          child: Column(
            children: [
              if (best)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: c.accentSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t('insure.cheapest'),
                        style: TextStyle(
                          color: c.accent,
                          fontSize: 8.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FundLogo(
                    logoUrl: logoUrl,
                    domain: logoDomain,
                    seed: name,
                    size: 38,
                    brandColor: brand,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shortInsurerName(name),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (rateLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            rateLabel!,
                            style: TextStyle(
                              color: c.faint,
                              fontFamily: fructaFonts.mono,
                              fontSize: 10.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (meta != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            meta!,
                            style: TextStyle(
                              color: c.faint,
                              fontSize: 10.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (barFraction != null) ...[
                          const SizedBox(height: 8),
                          _QBar(fraction: barFraction!, best: best),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        priceText,
                        style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (priceUnit != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          priceUnit!,
                          style: TextStyle(color: c.faint, fontSize: 9.5),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The inline price bar. Cheapest gold, everyone else neutral. It grows on
/// entry, so the spread animates into being rather than just sitting there.
class _QBar extends StatelessWidget {
  const _QBar({required this.fraction, required this.best});
  final double fraction;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 4,
        color: c.s3,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FractionallySizedBox(
              widthFactor: v.clamp(0.02, 1.0),
              child: Container(color: best ? c.accent : c.line2),
            ),
          ),
        ),
      ),
    );
  }
}

class CoverRow extends StatelessWidget {
  const CoverRow(this.label, {super.key, required this.tint, this.last = false});
  final String label;
  final Color tint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border:
            last ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: tint, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label,
                style: TextStyle(color: c.muted, fontSize: 12.5)),
          ),
          Icon(Icons.check_rounded, size: 16, color: c.up),
        ],
      ),
    );
  }
}

/// Licensed IRA class chips.
class ClassChips extends StatelessWidget {
  const ClassChips(this.classes, {super.key});
  final List<InsClass> classes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final cl in classes)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.line),
              ),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontFamily: fructaFonts.mono, fontSize: 10, color: c.muted),
                  children: [
                    TextSpan(
                        text: cl.code,
                        style: TextStyle(
                            color: c.text, fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ${cl.label}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small footnote under a section (mockup `.sigfoot`).
class InsureFoot extends StatelessWidget {
  const InsureFoot(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Text(text, style: TextStyle(color: c.faint, fontSize: 9.5)),
    );
  }
}

// ── external launch (tel / wa.me / mailto / web) ─────────────────────────
// Requires url_launcher. Failures are swallowed so a missing handler never
// throws into the UI.

Future<void> _open(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

void openTel(String phone) =>
    _open(Uri.parse('tel:${phone.replaceAll(RegExp(r'\s'), '')}'));
void openWhatsApp(String number) =>
    _open(Uri.parse('https://wa.me/${number.replaceAll(RegExp(r'[^0-9]'), '')}'));
void openMail(String email) => _open(Uri.parse('mailto:$email'));
void openWeb(String site) => _open(
    Uri.parse(site.startsWith('http') ? site : 'https://$site'));

String kes(num v) => 'KES ${withCommas(v.round())}';

/// 104006 -> "104k", 3450000 -> "3.5M". Keeps a bar label or a card figure
/// readable at 10px without an ellipsis, which the house rules forbid anyway.
String kesCompact(num v) {
  final d = v.toDouble();
  if (d >= 1e6) {
    final m = d / 1e6;
    return '${m >= 10 ? m.round() : m.toStringAsFixed(1)}M';
  }
  if (d >= 1000) return '${(d / 1000).round()}k';
  return d.round().toString();
}

/// Trim the corporate tail so an insurer fits a chart label. Only the trailing
/// boilerplate goes; the meaningful part of the name is never cut.
String shortInsurerName(String n) {
  var s = n;
  for (final re in <RegExp>[
    RegExp(r'\s*Insurance\s*Company.*$', caseSensitive: false),
    RegExp(r'\s*Assurance\s*Company.*$', caseSensitive: false),
    RegExp(r'\s*Insurance\s*Limited$', caseSensitive: false),
    RegExp(r'\s*\(K\)\s*Limited$', caseSensitive: false),
    RegExp(r'\s*\(Kenya\)\s*Limited$', caseSensitive: false),
    RegExp(r'\s*Limited$', caseSensitive: false),
    RegExp(r'\s*Insurance$', caseSensitive: false),
    RegExp(r'\s*Assurance$', caseSensitive: false),
  ]) {
    s = s.replaceFirst(re, '');
  }
  return s.trim();
}

/// Landed motor premium: base + levy% of base + flat stamp duty. Kenya's
/// mandatory charges (training 0.2% + PHCF 0.25% = 0.45% of basic premium,
/// plus a flat KES 40 stamp). Defaults match statute; overridable via config.
double landedPremium(double base, {double levyPct = 0.45, double stamp = 40}) =>
    base + base * levyPct / 100 + stamp;

double levyAmount(double base, double levyPct) => base * levyPct / 100;

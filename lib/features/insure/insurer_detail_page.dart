import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/agent.dart';
import '../../data/models/insurer.dart';
import '../../data/models/remote_config.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_shell.dart';
import 'insurer_reviews.dart';
import 'insurer_trust_panel.dart';

// ── what this page is showing ─────────────────────────────────────────────
//
// Three constructors, three shapes, and no combination of flags that means
// nothing. The old version carried `isTravel` and `isInfo` as two independent
// booleans alongside five fields that were dummies in two modes out of three:
// a travel page held `value = 0`, a motor page held `region = null, days = 0,
// pax = 0`, and `isTravel && isInfo` was representable but meaningless. Every
// read of those fields then had to re-derive the mode with a ternary, eleven
// times in one build method.
//
// A sealed hierarchy holds each mode's inputs on the mode itself, so a field
// exists only where it means something and the compiler checks the switch.

sealed class _Mode {
  const _Mode();
}

final class _MotorMode extends _Mode {
  const _MotorMode({
    required this.value,
    required this.cls,
    required this.cover,
  });
  final double value;
  final MotorClass cls;
  final CoverType cover;
}

final class _TravelMode extends _Mode {
  const _TravelMode({
    required this.region,
    required this.days,
    required this.pax,
  });
  final String region;
  final int days;
  final int pax;
}

final class _InfoMode extends _Mode {
  const _InfoMode();
}

/// The resolved priced view of this page, or null when there is no number.
///
/// Null is the load-bearing state. It is what an informational insurer returns,
/// and it is ALSO what a quote constructor returns when the tariff does not
/// cover the inputs it was handed. That second case used to render a 40px "0"
/// under the words "per year", because the premium block was gated on the mode
/// rather than on whether a price existed. Collapsing both to one nullable
/// means the page degrades all the way to facts instead of halfway.
class _Quote {
  const _Quote({
    required this.total,
    required this.lead,
    required this.sub,
    required this.unit,
    required this.ctaLabel,
    this.breakdown,
  });

  final double total;
  final String lead;
  final String sub;
  final String unit;
  final String ctaLabel;

  /// Statutory itemisation. Motor only: travel premiums are quoted whole, with
  /// no levy or stamp of their own to split out.
  final ({double base, double levy, double stamp})? breakdown;
}

class InsurerDetailPage extends ConsumerWidget {
  InsurerDetailPage.motor(
    this.insurer, {
    super.key,
    required double value,
    MotorClass cls = MotorClass.private,
    CoverType cover = CoverType.comprehensive,
  }) : _mode = _MotorMode(value: value, cls: cls, cover: cover);

  InsurerDetailPage.travel(
    this.insurer, {
    super.key,
    required String region,
    required int days,
    required int pax,
  }) : _mode = _TravelMode(region: region, days: days, pax: pax);

  /// Informational mode: the insurer is on the IRA register but publishes no
  /// rate we can price from. There is no premium and no peer ranking, only who
  /// they are, how they stand with the regulator, and how to reach them. This
  /// is the honest state for most of the market, and it is real content (not a
  /// coming-soon teaser), so it satisfies Apple 2.1.
  const InsurerDetailPage.info(this.insurer, {super.key})
    : _mode = const _InfoMode();

  final Insurer insurer;
  final _Mode _mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final i = insurer;
    final brand = insurerBrand(context, i);
    final cfg = ref.watch(remoteConfigProvider);

    final List<Agent> agents = i.companyId == null
        ? const <Agent>[]
        : ref.watch(agentsForCompanyProvider(i.companyId));

    // One resolution, up front. Everything below reads `quote == null` rather
    // than re-deriving the mode, so the quote page and the facts page cannot
    // drift apart section by section the way they had.
    final quote = _resolveQuote(i, cfg);
    final action = _actionFor(i);

    // How much this page has to say once the number is out of the way.
    //
    // Most insurers we can price also carry a cover list, agents, or both, and
    // for those the argument below about not burying them under charts holds.
    // CIC General carries neither: no benefits, no agents, no reviews yet. The
    // page was identity, premium, breakdown, disclaimer, and then half a screen
    // of black. Sections hiding when they are empty is right; a PAGE with no
    // floor under it is not.
    final thin = i.benefits.isEmpty && agents.isEmpty;

    // The trust surface (rating arc, market share, regulatory timeline) is what
    // we always hold, because it comes off the IRA register rather than off the
    // insurer's marketing. It carries the unpriced page, and it now catches the
    // priced page that has nothing else.
    final showTrust = quote == null || thin;

    // The insurer's full switchboard. This used to be gated to the unpriced
    // page on the grounds that the sticky bar was already the act, and that was
    // wrong: the bar dials one number, the grid lists the paybill, the email
    // and the site, which are different questions, not the same one repeated.
    final grid = _hasContact(i);

    // Built here as a nullable widget rather than tested as a bool at the use
    // site. `quote != null && action != null` stored in a bool does not promote
    // either one where the bar is constructed, so the fields would still read
    // as nullable; inside the conditional they promote and the bar can take
    // both non-null.
    final Widget? bar = quote != null && action != null
        ? _StickyQuoteBar(
            price: quote.total,
            label: quote.ctaLabel,
            // var(--accent) in the mockup, not the insurer's brand. Two
            // reasons, and the second is the real one. First, gold is the
            // app's "act" colour everywhere else. Second, brand_color is
            // nullable: an insurer without one falls back to a generic tint,
            // so a CTA painted from it is a button whose colour means nothing
            // and which currently renders blue for all 38.
            tint: c.accent,
            onTap: action,
          )
        : null;

    // The glass nav, not a Material AppBar. The brand wash behind the header
    // is a 260px bloom that starts ABOVE the identity row: an opaque app bar
    // painted over its top half and left a hard horizontal edge across the
    // hero. Content passing under a translucent nav is the whole point of the
    // shape, and it is what the mockup does.
    //
    // The price still follows you down the page. The premium sits at the top,
    // but the cover list, the agents and the reviews are all BELOW it, and
    // they are exactly the things that decide whether someone acts. By the
    // time a reader has finished them the number is a full screen behind, and
    // asking them to scroll back up to act is asking them not to.
    return InsureScaffold(
      navTitle: shortInsurerName(i.name),
      bottomBar: bar,
      children: [
        _Identity(insurer: i, brand: brand),

        // Quote, or facts. Never both, and never neither.
        //
        // The trust surface (the rating arc, the market-share chart, the
        // regulatory timeline) belongs on the page for an insurer we CANNOT
        // price, where the facts are all we have to offer. Stacking it under a
        // live quote buries the agents and the reviews, which are the two
        // things that actually convert, under three sections of chart. The
        // trust signal a quoted insurer needs is the licence badge and the GCR
        // grade, and both are in the header, read in the first second rather
        // than the fortieth.
        if (quote != null) ...[
          _Premium(
            lead: quote.lead,
            amount: withCommas(quote.total.round()),
            unit: quote.unit,
            sub: quote.sub,
          ),
          if (quote.breakdown != null)
            _Breakdown(
              base: quote.breakdown!.base,
              levy: quote.breakdown!.levy,
              stamp: quote.breakdown!.stamp,
            ),
        ],

        if (showTrust) InsurerTrustPanel(i),

        // What the premium buys. This used to be gated to the informational
        // page alongside the trust charts, which meant the one reader looking
        // at an actual price was the one reader never told what it covered.
        // Cover is product content, not a trust signal, and it belongs on both.
        if (i.benefits.isNotEmpty) ...[
          InsureH2(
            _mode is _TravelMode
                ? t('insure.inThePlan')
                : t('insure.whatsCovered'),
          ),
          // CoverRow carries vertical padding only, so it takes the page inset
          // from its parent. Dropped straight into the scaffold list it sat
          // flush against the screen edge while every other section was in 20.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (var b = 0; b < i.benefits.length; b++)
                  CoverRow(
                    i.benefits[b],
                    tint: c.accent,
                    last: b == i.benefits.length - 1,
                  ),
              ],
            ),
          ),
        ],

        // A human who can actually bind the policy, above the switchboard.
        if (agents.isNotEmpty) ...[
          InsureH2(
            t('insure.talkAgent'),
            small: t('insure.agentsNear', {'n': '${agents.length}'}),
          ),
          for (var a = 0; a < agents.length; a++)
            AgentRow(
              name: agents[a].name,
              phone: agents[a].phone ?? '',
              onCall: agents[a].phone == null
                  ? null
                  : () => openTel(agents[a].phone!),
              onWhatsApp: agents[a].phone == null || !agents[a].whatsapp
                  ? null
                  : () => openWhatsApp(agents[a].phone!),
              showDivider: a < agents.length - 1,
            ),
        ],

        if (grid) ...[
          InsureH2(t('insure.reachThem'), small: t('insure.reachSmall')),
          _ContactGrid(insurer: i),
        ],

        // The in-body CTA exists only where neither the sticky bar nor the
        // grid does, and only where we hold a channel to send the tap down. A
        // button that does nothing when pressed is worse than no button, and
        // the old one rendered whenever a price was absent regardless of
        // whether the insurer had a phone or a site behind it.
        if (bar == null && !grid && action != null)
          CtaFull(
            label: quote?.ctaLabel ?? t('insure.getQuote'),
            tint: c.accent,
            icon: Icons.north_east,
            onTap: action,
          ),

        InsurerReviews(i),

        // In a card, not floating. On a thin insurer this is the last thing on
        // the page, and a bare grey paragraph above an empty screen reads as an
        // unfinished layout rather than a deliberate footnote.
        NoteCard(
          rcText(cfg, 'insure.disc.detail'),
          title: t('common.goodToKnow'),
        ),
      ],
    );
  }

  /// The price this page is quoting, or null when there is none to quote.
  _Quote? _resolveQuote(Insurer i, RemoteConfig cfg) {
    switch (_mode) {
      case _InfoMode():
        return null;

      case _TravelMode(:final region, :final days, :final pax):
        final total = i.travelPrice(region, days: days, pax: pax) ?? 0;
        if (total <= 0) return null;
        return _Quote(
          total: total,
          lead: t('insure.travelLead', {
            'region': regionLabel(region),
            'days': '$days',
          }),
          sub: [
            if (i.travelCover != null) i.travelCover!,
            t('insure.travellersN', {'n': '$pax'}),
          ].join(' \u00b7 '),
          unit: t('insure.perTrip'),
          ctaLabel: t('insure.getTravelQuote'),
        );

      case _MotorMode(:final value, :final cls, :final cover):
        final base = i.quote(value, cls: cls, cover: cover) ?? 0;
        if (base <= 0) return null;
        final levyPct = cfg.number('insure.levy_pct', 0.45).toDouble();
        final stamp = cfg.number('insure.stamp_kes', 40).toDouble();
        return _Quote(
          total: landedPremium(base, levyPct: levyPct, stamp: stamp),
          // The lead names the CLASS, not just the product. "Motor
          // comprehensive" was the same string whether you were pricing a
          // private saloon or a PSV matatu, which are different tariffs
          // entirely. "Private, comprehensive" tells you which quote this is.
          lead:
              '${t('insure.class.${cls.key}')}, '
              '${t('insure.cover.${cover.key}')}',
          sub: cover == CoverType.tpo
              ? t('insure.tpoFlat', {'class': t('insure.class.${cls.key}')})
              : t('insure.rateOfValue', {
                  'rate': (i.rateFor(value, cls) ?? 0).toStringAsFixed(2),
                  'excess': i.excessLabel,
                }),
          unit: t('insure.perYear'),
          ctaLabel: t('insure.getQuote'),
          breakdown: (
            base: base,
            levy: levyAmount(base, levyPct),
            stamp: stamp,
          ),
        );
    }
  }

  /// Where the act button sends the tap, or null when we hold no channel at
  /// all for this insurer.
  VoidCallback? _actionFor(Insurer i) {
    final phone = i.phone;
    if (phone != null) return () => openTel(phone);
    final site = i.website;
    if (site != null) return () => openWeb(site);
    return null;
  }
}

bool _hasContact(Insurer i) =>
    i.phone != null ||
    i.whatsapp != null ||
    i.email != null ||
    i.paybill != null ||
    i.website != null;

// ── contact ───────────────────────────────────────────────────────────────

/// WhatsApp's own green, matching [WhatsAppMark]'s default. A brand colour, so
/// it is the documented data-colour exception to theme-only tokens, and it is
/// named once here rather than repeated as a literal at each use.
const Color _whatsAppGreen = Color(0xFF25D366);

class _ContactGrid extends StatelessWidget {
  const _ContactGrid({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;

    // The colour pair is passed straight in. It used to be routed through a
    // five-value enum whose values collapsed to three distinct pairs, so the
    // enum named nothing the call site did not already know.
    final tiles = <Widget>[
      if (i.phone != null)
        _ContactTile(
          icon: Icons.call,
          fg: c.up,
          bg: c.upSoft,
          label: t('insure.contact.call'),
          value: i.phone!,
          onTap: () => openTel(i.phone!),
        ),
      if (i.whatsapp != null)
        _ContactTile(
          whatsApp: true,
          fg: _whatsAppGreen,
          bg: _whatsAppGreen.withValues(alpha: 0.13),
          label: t('insure.contact.whatsapp'),
          value: t('insure.contact.chatNow'),
          onTap: () => openWhatsApp(i.whatsapp!),
        ),
      if (i.email != null)
        _ContactTile(
          icon: Icons.mail_outline,
          fg: c.accent,
          bg: c.accentSoft,
          label: t('insure.contact.email'),
          value: i.email!,
          onTap: () => openMail(i.email!),
        ),
      if (i.paybill != null)
        _ContactTile(
          icon: Icons.receipt_long_outlined,
          fg: c.accent,
          bg: c.accentSoft,
          label: t('insure.contact.paybill'),
          value: i.paybill!,
          onTap: null,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          if (tiles.isNotEmpty)
            // A fixed main-axis extent, NOT childAspectRatio. Aspect ratio
            // derives cell height from cell width, so the height changed with
            // screen size and could not account for the 32px icon tile plus
            // 22px of padding: that is the 4px bottom overflow. 62 clears the
            // 54px content box with headroom for the 1.3x text scale.
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 9,
                crossAxisSpacing: 9,
                mainAxisExtent: 62,
              ),
              children: tiles,
            ),
          if (i.website != null) ...[
            const SizedBox(height: 9),
            _ContactTile(
              icon: Icons.language,
              fg: c.muted,
              bg: c.s3,
              label: t('insure.contact.website'),
              value: i.website!,
              onTap: () => openWeb(i.website!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.label,
    required this.value,
    required this.onTap,
    required this.fg,
    required this.bg,
    this.icon,
    this.whatsApp = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool whatsApp;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: whatsApp
                  ? const WhatsAppMark(size: 17)
                  : Icon(icon, size: 15, color: fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: c.faint,
                      fontSize: 9,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: fructaFonts.mono,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quote bar pinned to the foot of an insurer page.
///
/// Carries the live premium, so the number and the action are never separated
/// by a scroll. Frosted rather than opaque: the content sliding under it is a
/// cue that there is more page, which a solid slab would hide.
class _StickyQuoteBar extends StatelessWidget {
  const _StickyQuoteBar({
    required this.price,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final double price;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.bg.withValues(alpha: 0.94),
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('insure.yourPremium'),
                    style: TextStyle(
                      color: c.faint,
                      fontSize: 9,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    kes(price),
                    style: TextStyle(
                      color: c.text,
                      fontFamily: fructaFonts.mono,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    backgroundColor: tint,
                    foregroundColor: c.inkOn(tint),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label),
                      const SizedBox(width: 7),
                      const Icon(Icons.north_east, size: 15),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── header ────────────────────────────────────────────────────────────────

/// The identity row.
///
///   .lgb  58px, radius 17, brand-tinted drop shadow
///   .inm  19px, weight 750, tracking -0.5
///   .imt  11.5px faint, carrying a licence badge and the GCR grade
///
/// The old version said "General insurer", which every row on the register also
/// is, so it told the reader nothing. What they want to know in the first
/// second is: is this outfit licensed, and is it rated. Both are facts we hold,
/// and now both are in the header instead of buried three sections down.
class _Identity extends StatelessWidget {
  const _Identity({required this.insurer, required this.brand});
  final Insurer insurer;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    // licenseYear (IRA register) is the sourced fact. licensedSince is the
    // older free-text field, kept as a fallback so nothing regresses.
    final year = i.licenseYear ?? i.licensedSince;

    // What we can actually quote them for. The last-resort subtitle, and it
    // reuses keys the directory already ships, so this costs no new copy.
    final products = <String>[
      if (i.hasMotor) t('insure.motor'),
      if (i.hasTravel) t('insure.travel'),
    ];

    return Stack(
      // Clip.none, and this is why the wash rendered as a hard-edged red BOX
      // instead of a soft bloom: a Stack clips to its own bounds by default
      // (Clip.hardEdge), and its bounds are set by the non-positioned child,
      // which is a 70px-tall row. The 260px circle was being sliced into a
      // rectangle by the Stack it lives in.
      clipBehavior: Clip.none,
      children: [
        // .wash: the ambient brand bloom behind the header. IgnorePointer, and
        // it must sit UNDER the row, not around it, or it eats the taps.
        Positioned(
          left: -60,
          top: -90,
          child: IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    brand.withValues(alpha: 0.14),
                    brand.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.32),
                      blurRadius: 26,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: InsurerLogo(i, size: 58),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortInsurerName(i.name),
                      style: TextStyle(
                        color: c.text,
                        fontSize: 19,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (year != null) ...[
                          Icon(Icons.check, size: 12, color: c.up),
                          const SizedBox(width: 4),
                          Text(
                            t('insure.licensed', {'y': '$year'}),
                            style: TextStyle(
                              color: c.up,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (year != null && i.financialRating != null)
                          Text(
                            '  \u00b7  ',
                            style: TextStyle(color: c.faint, fontSize: 11.5),
                          ),
                        if (i.financialRating != null)
                          Text(
                            i.financialRating!,
                            style: TextStyle(
                              color: c.up,
                              fontFamily: fructaFonts.mono,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        // The old fallback said "General insurer", which every
                        // row on the register also is, so it told the reader
                        // nothing and it is what the screenshot shows under CIC
                        // General. Where we hold neither a licence year nor a
                        // grade, name what we CAN price for them instead. That
                        // is specific, it is true, and it is never empty on a
                        // page you reached by pricing something.
                        if (year == null &&
                            i.financialRating == null &&
                            products.isNotEmpty)
                          Text(
                            products.join('  \u00b7  '),
                            style: TextStyle(color: c.faint, fontSize: 11.5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The premium.
///
///   .plead  10px uppercase, tracked
///   .pbig   40px, weight 750, tracking -2, with the unit as a baseline-aligned
///           small rather than glued into the number
///   .psub   12px muted
///
/// Splitting the unit off the figure is not decoration. "KES 104,006" reads as
/// one long token; "104,006" with a quiet "KES / year" beside it reads as a
/// number you can compare against the one on the previous screen.
class _Premium extends StatelessWidget {
  const _Premium({
    required this.lead,
    required this.amount,
    required this.unit,
    required this.sub,
  });

  final String lead;
  final String amount;
  final String unit;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lead.toUpperCase(),
            style: TextStyle(
              color: c.faint,
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  amount,
                  style: TextStyle(
                    color: c.text,
                    fontFamily: fructaFonts.mono,
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            sub,
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Base, levy, stamp, as three cells in one bordered strip.
///
/// The levy (0.45%) and the stamp duty (KES 40) are set by statute, not by the
/// insurer. Folding them into a single quoted figure hides the fact that a
/// slice of every premium in Kenya is identical no matter who you buy from, and
/// that the only part an insurer actually competes on is the base. This strip
/// makes that visible in one glance.
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.base,
    required this.levy,
    required this.stamp,
  });

  final double base;
  final double levy;
  final double stamp;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cells = <({String label, double value})>[
      (label: t('insure.brk.base'), value: base),
      (label: t('insure.brk.levy'), value: levy),
      (label: t('insure.brk.stamp'), value: stamp),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      // IntrinsicHeight, and it is load-bearing.
      //
      // A Row's cross axis is VERTICAL, and inside a ListView the height is
      // unbounded, so CrossAxisAlignment.stretch asked these cells to fill an
      // infinite extent. The sliver then failed to lay out, its geometry stayed
      // null, and the viewport blew up on `child.geometry!` during paint. The
      // crash surfaced as a null-check error in Flutter's own painting code,
      // which is why it looked like it had nothing to do with this widget.
      //
      // stretch is still what we want (the divider must run the full height of
      // the tallest cell); IntrinsicHeight is what makes it legal, by measuring
      // the children first and giving the Row a real bounded height.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < cells.length; k++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  decoration: BoxDecoration(
                    border: k == cells.length - 1
                        ? null
                        : Border(right: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cells[k].label.toUpperCase(),
                        style: TextStyle(
                          color: c.faint,
                          fontSize: 8.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        withCommas(cells[k].value.round()),
                        style: TextStyle(
                          color: c.text,
                          fontFamily: fructaFonts.mono,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

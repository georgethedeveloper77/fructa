import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/series_colors.dart';
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

    // Every insurer we can price at EXACTLY these inputs, cheapest first. The
    // reader arrived from a list of nine quotes and this page threw that away:
    // a premium with nothing to measure it against is a number, not an answer.
    // Nothing new is fetched, because the list screen already priced the whole
    // book to build itself.
    final peers = quote == null
        ? const <double>[]
        : (_peerPrices(ref.watch(insurersProvider), cfg)..sort());

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
            // What the button DOES, not what the reader wants. It dials a
            // phone. "Get this quote" implied fructa was selling the cover,
            // which is the one thing the disclaimer at the foot of this page
            // exists to deny.
            label: t('insure.callThem', {'name': shortInsurerName(i.name)}),
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
          _Position(prices: peers, mine: quote.total),
        ],

        if (showTrust && i.hasTrustData)
          InsurerTrustPanel(i)
        else if (showTrust)
          // InsurerTrustPanel returns nothing at all when hasTrustData is
          // false, which is how a page ended up as a premium and half a screen
          // of black. An insurer who is on the register but publishes no
          // rating, no settlement time and no complaint count has told the
          // reader something, and "not published" is the way to say it.
          _Standing(insurer: i),

        // What the premium buys. This used to be gated to the informational
        // page alongside the trust charts, which meant the one reader looking
        // at an actual price was the one reader never told what it covered.
        // Cover is product content, not a trust signal, and it belongs on both.
        // No benefit list is not nothing. The tariff we priced from carries
        // the cover, the excess and the floor, and saying that CIC publishes no
        // list is itself a fact about CIC worth a buyer's attention.
        if (i.benefits.isEmpty && quote != null)
          _Terms(insurer: i, mode: _mode),

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

  /// Every priced insurer at the SAME inputs as this page, unsorted.
  ///
  /// Recomputed rather than passed in, so the directory (which opens this page
  /// on a default 3.45m private comprehensive) gets a rail measured against
  /// that same default instead of against whatever the motor screen last had.
  /// One rule, applied wherever the page was opened from.
  List<double> _peerPrices(List<Insurer> all, RemoteConfig cfg) {
    switch (_mode) {
      case _InfoMode():
        return const [];

      case _TravelMode(:final region, :final days, :final pax):
        final out = <double>[];
        for (final x in all) {
          final p = x.travelPrice(region, days: days, pax: pax);
          if (p != null && p > 0) out.add(p);
        }
        return out;

      case _MotorMode(:final value, :final cls, :final cover):
        final levyPct = cfg.number('insure.levy_pct', 0.45).toDouble();
        final stamp = cfg.number('insure.stamp_kes', 40).toDouble();
        final out = <double>[];
        for (final x in all) {
          final b = x.quote(value, cls: cls, cover: cover) ?? 0;
          if (b > 0) {
            out.add(landedPremium(b, levyPct: levyPct, stamp: stamp));
          }
        }
        return out;
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
              // BOTH of these, and neither is boilerplate.
              //
              // A GridView is a BoxScrollView, and a BoxScrollView with a NULL
              // padding does not use zero: it reaches for MediaQuery and pads
              // itself with the safe-area insets. On a vertical scroll view
              // that is the notch AND the home indicator, so this grid was
              // silently inserting about a hundred logical pixels of nothing
              // between the REACH THEM header and the first tile, on a page
              // that had already been criticised for looking empty.
              //
              // `primary` defaults to true for a vertical scroll view with no
              // controller, which also has it competing for the
              // PrimaryScrollController the page's own ListView already owns.
              padding: EdgeInsets.zero,
              primary: false,
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

// ── where this quote sits ─────────────────────────────────────────────────

/// This premium against every other premium we can price at the same inputs.
///
/// The single most useful thing a detail page can add to a number the reader
/// has already seen. They came from a ranked list and the page dropped the
/// ranking; a price with nothing beside it cannot be judged, so the reader has
/// to go back and hold nine figures in their head.
///
/// Hides itself below three quotes. A rail with two pips on it is not a market,
/// it is a pair, and "2nd of 2" is a sentence that flatters the dearer one.
class _Position extends StatelessWidget {
  const _Position({required this.prices, required this.mine});

  /// Ascending, every insurer priceable at these inputs.
  final List<double> prices;
  final double mine;

  static const _minPeers = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (prices.length < _minPeers) return const SizedBox.shrink();

    final lo = prices.first;
    final hi = prices.last;
    if (hi <= lo) return const SizedBox.shrink();

    // Rank by how many are strictly cheaper, so identical premiums share a
    // place instead of one of them being arbitrarily "better".
    final rank = prices.where((p) => p < mine).length + 1;
    final over = mine - lo;
    final under = hi - mine;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    t('insure.pos.title'),
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  t('insure.pos.rank', {
                    'r': '$rank',
                    'n': '${prices.length}',
                  }).toUpperCase(),
                  style: TextStyle(
                    color: c.accent,
                    fontFamily: fructaFonts.mono,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 34,
              child: LayoutBuilder(
                builder: (context, cons) {
                  final w = cons.maxWidth;
                  double x(double v) => ((v - lo) / (hi - lo)) * w;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Cheap to dear, left to right, so the good end is where
                      // a reader already looks first.
                      //
                      // THREE STOPS, AT FULL STRENGTH. It was two, green and
                      // red, both at 0.30 alpha. Two problems. Alpha that low
                      // washes to a pastel on a light surface and to a smudge
                      // on a dark one, so the scale carried almost no colour in
                      // either mode. Worse, a straight green to red ramp passes
                      // through the middle of RGB space, which is a desaturated
                      // grey-brown: the centre of the bar, exactly where most
                      // quotes land, was the least legible part of it. Putting
                      // the accent at the midpoint gives a real spectrum with
                      // no dead zone, and the three tokens are theme colours,
                      // so the ramp re-resolves in light and dark rather than
                      // being tuned for one.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 12,
                        height: 9,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            // The midpoint is a DATA colour, not c.accent.
                            // Accent is user selectable: somebody who picks a
                            // red accent would get green to red to red, and a
                            // green one green to green to red, which is a
                            // broken scale in both cases. seriesColor(0) is the
                            // gold from the central ramp, fixed across modes
                            // and immune to the picker, and its only job here
                            // is to bridge the two ends without passing through
                            // the grey that a direct green to red ramp does.
                            gradient: LinearGradient(
                              colors: [c.up, seriesColor(0), c.down],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),

                      // Competing quotes as NOTCHES cut in the page background,
                      // not as pips drawn on top in a border colour.
                      //
                      // c.line2 was furniture: near invisible on the light
                      // surface in the screenshot, and barely better on dark.
                      // A notch is high contrast in both modes by construction,
                      // because it is the page showing through, and it needs no
                      // per-mode tuning at all. It also reads correctly: each
                      // rival quote takes a bite out of the range.
                      for (final p in prices)
                        Positioned(
                          left: (x(p) - 1.25).clamp(0.0, w - 2.5),
                          top: 9,
                          child: Container(
                            width: 2.5,
                            height: 15,
                            decoration: BoxDecoration(
                              color: c.bg,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),

                      // This one, in the ink colour inside a background ring, so
                      // it is the only mark on the rail that is neither the
                      // spectrum nor a hole in it. c.text against c.bg is the
                      // highest contrast pair the theme has, in either mode.
                      Positioned(
                        left: (x(mine) - 5).clamp(0.0, w - 10),
                        top: 3,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 620),
                          curve: Curves.easeOutBack,
                          builder: (_, v, child) => Transform.scale(
                            scaleY: v.clamp(0.0, 1.0),
                            child: child,
                          ),
                          child: Container(
                            width: 10,
                            height: 27,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.bg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Container(
                              width: 4,
                              height: 23,
                              decoration: BoxDecoration(
                                color: c.text,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _end(c, t('insure.pos.cheapest', {'v': withCommas(lo.round())})),
                _end(c, t('insure.pos.dearest', {'v': withCommas(hi.round())})),
              ],
            ),
            const SizedBox(height: 11),
            Text.rich(
              TextSpan(
                style: TextStyle(color: c.muted, fontSize: 12, height: 1.55),
                children: [
                  if (over <= 0)
                    TextSpan(
                      text: t('insure.pos.isCheapest'),
                      style: TextStyle(
                        color: c.up,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else ...[
                    TextSpan(
                      text: t('insure.pos.over', {
                        'v': withCommas(over.round()),
                      }),
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' ${t('insure.pos.overTail', {
                        'v': withCommas(under.round()),
                      })}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// c.muted, not c.faint. These two carry the only absolute numbers on the
  /// rail, so they are content rather than furniture, and faint is a tone the
  /// light theme renders close to its own background.
  Widget _end(fructaColors c, String s) => Text(
    s.toUpperCase(),
    style: TextStyle(
      color: c.muted,
      fontFamily: fructaFonts.mono,
      fontSize: 9.5,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
    ),
  );
}

// ── what you get, when nobody published a list ────────────────────────────

/// The cover, the excess and the floor, straight off the tariff this page just
/// priced from, plus the plain statement that no benefit list exists.
///
/// The old page hid the whole section when `benefits` was empty, which is how a
/// quote screen managed to say nothing at all about what the money buys. Every
/// figure here was already used to compute the premium above it, so this
/// invents nothing.
class _Terms extends StatelessWidget {
  const _Terms({required this.insurer, required this.mode});

  final Insurer insurer;
  final _Mode mode;

  @override
  Widget build(BuildContext context) {
    final i = insurer;
    final rows = <({String k, String v, String? sub})>[];

    switch (mode) {
      case _MotorMode(:final cls, :final cover):
        rows.add((
          k: t('insure.terms.cover'),
          v: '${t('insure.class.${cls.key}')}, '
              '${t('insure.cover.${cover.key}')}',
          sub: null,
        ));
        rows.add((
          k: t('insure.terms.excess'),
          v: i.excessLabel,
          sub: i.minPremiumFor(cls) == null
              ? null
              : t('insure.terms.floor', {
                  'v': withCommas(i.minPremiumFor(cls)!.round()),
                }),
        ));
      case _TravelMode(:final region):
        rows.add((
          k: t('insure.terms.region'),
          v: regionLabel(region),
          sub: null,
        ));
        if (i.travelCover != null) {
          rows.add((
            k: t('insure.terms.ceiling'),
            v: i.travelCover!,
            sub: null,
          ));
        }
      case _InfoMode():
        return const SizedBox.shrink();
    }

    rows.add((
      k: t('insure.terms.benefits'),
      v: '',
      sub: t('insure.terms.noList'),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsureH2(t('insure.whatsCovered'), small: t('insure.terms.small')),
        _FactCard(rows: rows),
      ],
    );
  }
}

// ── will they pay, when we hold none of it ────────────────────────────────

/// The four questions a buyer has about an insurer's standing, each answered or
/// explicitly unanswered.
///
/// Rendered only where [InsurerTrustPanel] renders nothing, which it does
/// whenever `hasTrustData` is false. Absence is the finding: an insurer on the
/// register that publishes no rating, no settlement time and no complaint count
/// has told the reader something about how much it is willing to be measured
/// by, and a blank screen says it far less clearly than a row that reads
/// "not published".
class _Standing extends StatelessWidget {
  const _Standing({required this.insurer});

  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;

    final rows = <({String k, String v, String? sub})>[
      (
        k: t('insure.standing.licence'),
        v: i.canWriteNewBusiness
            ? t('insure.standing.canWrite')
            : t('insure.dir.noNewBusiness'),
        sub: i.licenseYear == null
            ? null
            : t('insure.licensed', {'y': '${i.licenseYear}'}),
      ),
      (
        k: t('insure.standing.strength'),
        v: i.financialRating ?? '',
        sub: i.financialRating == null ? t('insure.standing.unrated') : null,
      ),
      (
        k: t('insure.standing.claims'),
        v: i.claimsDays == null
            ? ''
            : t('insure.claimsDays', {'d': '${i.claimsDays}'}),
        sub: i.claimsDays == null ? t('insure.standing.notPublished') : null,
      ),
      (
        k: t('insure.standing.complaints'),
        v: i.complaintsCount == null ? '' : '${i.complaintsCount}',
        sub: i.complaintsCount == null
            ? t('insure.standing.notPublished')
            : null,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsureH2(
          t('insure.standing.title'),
          small: t('insure.standing.small'),
        ),
        _FactCard(rows: rows, okColor: i.canWriteNewBusiness ? c.up : c.down),
      ],
    );
  }
}

/// Label on the left, value right-aligned, an optional quiet line under it.
/// A row with no value shows only the quiet line, which is how "not published"
/// occupies the same space a real answer would and reads as deliberate.
class _FactCard extends StatelessWidget {
  const _FactCard({required this.rows, this.okColor});

  final List<({String k, String v, String? sub})> rows;
  final Color? okColor;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          children: [
            for (var k = 0; k < rows.length; k++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: k == rows.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        rows[k].k.toUpperCase(),
                        style: TextStyle(
                          color: c.faint,
                          fontFamily: fructaFonts.mono,
                          fontSize: 9.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (rows[k].v.isNotEmpty)
                            Text(
                              rows[k].v,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: k == 0 ? (okColor ?? c.text) : c.text,
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (rows[k].sub != null) ...[
                            if (rows[k].v.isNotEmpty) const SizedBox(height: 3),
                            Text(
                              rows[k].sub!,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: c.faint,
                                fontSize: rows[k].v.isEmpty ? 12.5 : 11,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
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

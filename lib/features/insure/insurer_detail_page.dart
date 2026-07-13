import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/agent.dart';
import '../../data/models/insurer.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_motion.dart';
import 'insure_shell.dart';
import 'insurer_reviews.dart';
import 'insurer_trust_panel.dart';

class InsurerDetailPage extends ConsumerWidget {
  const InsurerDetailPage.motor(
    this.insurer, {
    super.key,
    required this.value,
    this.cls = MotorClass.private,
    this.cover = CoverType.comprehensive,
  })  : isTravel = false,
        isInfo = false,
        region = null,
        days = 0,
        pax = 0;

  const InsurerDetailPage.travel(
    this.insurer, {
    super.key,
    required this.region,
    required this.days,
    required this.pax,
  })  : isTravel = true,
        isInfo = false,
        cls = MotorClass.private,
        cover = CoverType.comprehensive,
        value = 0;

  /// Informational mode: the insurer is on the IRA register but publishes no
  /// rate we can price from. There is no premium and no peer ranking, only who
  /// they are, how they stand with the regulator, and how to reach them. This
  /// is the honest state for most of the market, and it is real content (not a
  /// coming-soon teaser), so it satisfies Apple 2.1.
  const InsurerDetailPage.info(this.insurer, {super.key})
      : isTravel = false,
        isInfo = true,
        cls = MotorClass.private,
        cover = CoverType.comprehensive,
        value = 0,
        region = null,
        days = 0,
        pax = 0;

  final Insurer insurer;
  final bool isTravel;
  final bool isInfo;
  final double value; // motor, comprehensive only
  final MotorClass cls;
  final CoverType cover;
  final String? region; // travel
  final int days;
  final int pax;

  SignalTone _tone(String tag) => switch (tag.toUpperCase()) {
        'STRENGTH' => SignalTone.positive,
        'WATCH' => SignalTone.negative,
        _ => SignalTone.neutral,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final i = insurer;
    final brand = insurerBrand(context, i);
    final List<Agent> agents = i.companyId == null
        ? const <Agent>[]
        : ref.watch(agentsForCompanyProvider(i.companyId));


    final travelPrice =
        isTravel ? (i.travelPrice(region!, days: days, pax: pax) ?? 0) : 0.0;

    final cfg = ref.watch(remoteConfigProvider);
    final levyPct = cfg.number('insure.levy_pct', 0.45).toDouble();
    final stamp = cfg.number('insure.stamp_kes', 40).toDouble();
    final motorBase = isTravel
        ? 0.0
        : (i.quote(value, cls: cls, cover: cover) ?? 0);
    final motorLanded =
        landedPremium(motorBase, levyPct: levyPct, stamp: stamp);

    // Peer set for the ranking chart: same category, same inputs as this quote.
    final shownPrice = isTravel ? travelPrice : motorLanded;

    // The lead now names the CLASS, not just the product. "Motor comprehensive"
    // was the same string whether you were pricing a private saloon or a PSV
    // matatu, which are different tariffs entirely. "Private, comprehensive"
    // tells you which quote you are looking at.
    final premiumLead = isTravel
        ? t('insure.travelLead', {
            'region': regionLabel(region!),
            'days': '$days',
          })
        : '${t('insure.class.${cls.key}')}, ${t('insure.cover.${cover.key}')}';

    final premiumSub = isTravel
        ? [
            if (i.travelCover != null) i.travelCover!,
            t('insure.travellersN', {'n': '$pax'}),
          ].join(' \u00b7 ')
        : cover == CoverType.tpo
              ? t('insure.tpoFlat', {'class': t('insure.class.${cls.key}')})
              : t('insure.rateOfValue', {
                  'rate': (i.rateFor(value, cls) ?? 0).toStringAsFixed(2),
                  'excess': i.excessLabel,
                });

    // The glass nav, not a Material AppBar. The brand wash behind the header
    // is a 260px bloom that starts ABOVE the identity row: an opaque app bar
    // painted over its top half and left a hard horizontal edge across the
    // hero. Content passing under a translucent nav is the whole point of the
    // shape, and it is what the mockup does.
    //
    // The price still follows you down the page. The premium sits at the top,
    // but the trust panel, the peer ranking, the agents and the reviews are all
    // BELOW it, and they are exactly the things that decide whether someone
    // acts. By the time a reader has finished them the number is a full screen
    // behind, and asking them to scroll back up to act is asking them not to.
    //
    // The bar is absent for an unpriced insurer, since a bar reading "Get a
    // quote" with no quote behind it is a lie. Those get an official-site link
    // only, in the body.
    return InsureScaffold(
      navTitle: shortInsurerName(i.name),
      bottomBar: isInfo || shownPrice <= 0
          ? null
          : _StickyQuoteBar(
              price: shownPrice,
              label: isTravel
                  ? t('insure.getTravelQuote')
                  : t('insure.getQuote'),
              // var(--accent) in the mockup, not the insurer's brand. Two
              // reasons, and the second is the real one. First, gold is the
              // app's "act" colour everywhere else. Second, brand_color is
              // nullable: an insurer without one falls back to a generic tint,
              // so a CTA painted from it is a button whose colour means nothing
              // and which currently renders blue for all 38.
              tint: c.accent,
              onTap: () => _primaryAction(i),
            ),
      children: [
        _Identity(insurer: i, brand: brand),
        if (!isInfo)
          _Premium(
            lead: premiumLead,
            amount: withCommas((isTravel ? travelPrice : motorLanded).round()),
            unit: isTravel ? t('insure.perTrip') : t('insure.perYear'),
            sub: premiumSub,
          ),
        // The breakdown as a three-cell strip, not a run-on line of text.
        // "base KES 103,500 · levies KES 466 · stamp KES 40" is three numbers
        // pretending to be a sentence; nobody parses it. A levy and a stamp
        // duty are statutory add-ons the insurer does not set, and separating
        // them out is the difference between a price and an itemised price.
        if (!isTravel && !isInfo)
          _Breakdown(
            base: motorBase,
            levy: levyAmount(motorBase, levyPct),
            stamp: stamp,
          ),
        // ── SCREEN 02 ENDS HERE FOR A PRICED INSURER ──────────────────
        //
        // Everything below this line is gated to the INFORMATIONAL page, and
        // that is the design, not an oversight.
        //
        // A page that is quoting someone a price has exactly one job. The
        // trust surface (the rating arc, the market-share chart, the
        // regulatory timeline, the contact grid) belongs on the page for an
        // insurer we CANNOT price, where the facts are all we have to offer.
        // Stacking it under a live quote buries the agent and the reviews,
        // which are the two things that actually convert, under three
        // sections of chart.
        //
        // The trust signal a quoted insurer needs is the licence badge and
        // the GCR grade, and those are already in the header, where they are
        // read in the first second rather than the fortieth.
        if (isInfo) ...[
          InsurerTrustPanel(i),
          if (_hasContact(i)) ...[
            InsureH2(t('insure.reachThem'), small: t('insure.reachSmall')),
            _ContactGrid(insurer: i),
          ],
          if (i.benefits.isNotEmpty) ...[
            InsureH2(
              isTravel ? t('insure.inThePlan') : t('insure.whatsCovered'),
            ),
            for (var b = 0; b < i.benefits.length; b++)
              CoverRow(
                i.benefits[b],
                tint: c.accent,
                last: b == i.benefits.length - 1,
              ),
          ],
        ],

        // Agents. On screen 02 this is the first thing under the breakdown:
        // a human who can actually bind the policy.
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

        // The in-body CTA exists ONLY where the sticky bar does not: an
        // unpriced insurer has no premium to pin to the foot. Two identical
        // gold buttons a thumb apart is a bug, not emphasis.
        if (isInfo || shownPrice <= 0)
          CtaFull(
            label: isTravel ? t('insure.getTravelQuote') : t('insure.getQuote'),
            tint: c.accent,
            icon: Icons.north_east,
            onTap: () => _primaryAction(i),
          ),
        if (isInfo && i.website != null)
          CtaGhost(
            label: t('insure.officialSite'),
            icon: Icons.language,
            onTap: () => openWeb(i.website!),
          ),

        InsurerReviews(i),
        Disclaimer(rcText(cfg, 'insure.disc.detail')),
      ],
    );
  }

  void _primaryAction(Insurer i) {
    if (i.phone != null) {
      openTel(i.phone!);
    } else if (i.website != null) {
      openWeb(i.website!);
    }
  }
}

bool _hasContact(Insurer i) =>
    i.phone != null ||
    i.whatsapp != null ||
    i.email != null ||
    i.paybill != null ||
    i.website != null;

class _TrustStrip extends StatelessWidget {
  const _TrustStrip({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final i = insurer;
    final dash = t('common.dash');

    Widget statCell(String k, String v, String s,
        {bool first = false, Color? vColor}) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.only(left: first ? 0 : 13),
          decoration: BoxDecoration(
            border: first ? null : Border(left: BorderSide(color: c.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k,
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(v,
                  style: TextStyle(
                      color: vColor ?? c.text,
                      fontFamily: fructaFonts.mono,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(s,
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 9.5,
                      fontFamily: fructaFonts.mono)),
            ],
          ),
        ),
      );
    }

    final hasGauge = i.settlePct != null;
    final children = <Widget>[];
    if (hasGauge) {
      children.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClaimsGauge(pct: i.settlePct!, color: c.up),
            const SizedBox(height: 8),
            Text(t('insure.trust.claimsPaid'),
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(t('insure.trust.iraSource'),
                style: TextStyle(
                    color: c.faint,
                    fontSize: 9,
                    fontFamily: fructaFonts.mono)),
          ],
        ),
      );
      children.add(const SizedBox(width: 18));
      children.add(statCell(
        t('insure.trust.rating'),
        i.rating == null ? dash : '${i.rating}',
        t('insure.trust.ratingSub'),
        first: true,
      ));
      children.add(statCell(
        t('insure.trust.settlement'),
        i.claimsDays == null
            ? dash
            : t('insure.days', {'n': '${i.claimsDays}'}),
        t('insure.trust.settlementSub'),
      ));
    } else {
      children.add(statCell(
        t('insure.trust.claimsPaid'),
        dash,
        t('insure.trust.iraSource'),
        first: true,
        vColor: c.accent,
      ));
      children.add(statCell(
        t('insure.trust.rating'),
        i.rating == null ? dash : '${i.rating}',
        t('insure.trust.ratingSub'),
      ));
      children.add(statCell(
        t('insure.trust.settlement'),
        i.claimsDays == null
            ? dash
            : t('insure.days', {'n': '${i.claimsDays}'}),
        t('insure.trust.settlementSub'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// Claims-paid radial gauge (settlement ratio). Pure CustomPaint, no deps.
class _ClaimsGauge extends StatelessWidget {
  const _ClaimsGauge(
      {required this.pct, required this.color, this.size = 58});
  final double pct;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter:
                _GaugePainter(pct.clamp(0, 100) / 100, color, c.line2),
          ),
          Text('${pct.round()}%',
              style: TextStyle(
                  color: c.text,
                  fontFamily: fructaFonts.mono,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.frac, this.color, this.trackColor);
  final double frac;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * frac, false, arc);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.frac != frac || old.color != color || old.trackColor != trackColor;
}


class _PeerBar extends StatelessWidget {
  const _PeerBar({
    required this.name,
    required this.amountText,
    required this.frac,
    required this.me,
    required this.tint,
  });
  final String name;
  final String amountText;
  final double frac;
  final bool me;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      color: me ? c.text : c.muted,
                      fontSize: 12,
                      fontWeight: me ? FontWeight.w700 : FontWeight.w500)),
            ),
            const SizedBox(width: 10),
            Text(amountText,
                style: TextStyle(
                    color: me ? c.text : c.faint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: fructaFonts.mono)),
          ],
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, cons) => Stack(
            children: [
              Container(
                height: 7,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: 7,
                width: cons.maxWidth * frac.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: me ? tint : c.line2,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactGrid extends StatelessWidget {
  const _ContactGrid({required this.insurer});
  final Insurer insurer;

  @override
  Widget build(BuildContext context) {
    final i = insurer;
    final tiles = <Widget>[
      if (i.phone != null)
        _ContactTile(
          icon: Icons.call,
          tone: _Tone.call,
          label: t('insure.contact.call'),
          value: i.phone!,
          onTap: () => openTel(i.phone!),
        ),
      if (i.whatsapp != null)
        _ContactTile(
          whatsApp: true,
          tone: _Tone.wa,
          label: t('insure.contact.whatsapp'),
          value: t('insure.contact.chatNow'),
          onTap: () => openWhatsApp(i.whatsapp!),
        ),
      if (i.email != null)
        _ContactTile(
          icon: Icons.mail_outline,
          tone: _Tone.mail,
          label: t('insure.contact.email'),
          value: i.email!,
          onTap: () => openMail(i.email!),
        ),
      if (i.paybill != null)
        _ContactTile(
          icon: Icons.receipt_long_outlined,
          tone: _Tone.pay,
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
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
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
              tone: _Tone.web,
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

enum _Tone { call, wa, mail, pay, web }

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.tone,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.whatsApp = false,
  });

  final _Tone tone;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool whatsApp;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg) = switch (tone) {
      _Tone.call => (c.upSoft, c.up),
      _Tone.wa => (const Color(0x2225D366), const Color(0xFF25D366)),
      _Tone.mail => (c.accentSoft, c.accent),
      _Tone.pay => (c.accentSoft, c.accent),
      _Tone.web => (c.s3, c.muted),
    };
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
                  Text(label,
                      style: TextStyle(
                          color: c.faint,
                          fontSize: 9,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: fructaFonts.mono)),
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


// ── V8 detail header ───────────────────────────────────────────────────────

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
                    if (year == null && i.financialRating == null)
                      Text(
                        t('insure.generalInsurer'),
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

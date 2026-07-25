import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/insurance_type.dart';
import '../../data/models/insurer.dart';
import '../../data/models/remote_config.dart';
import '../../data/snapshot_providers.dart';
import 'insure_common.dart';
import 'insure_motion.dart';
import 'insure_motor_page.dart';
import 'insure_travel_page.dart';
import 'insurer_directory_page.dart';

/// Insurance home, V10.
///
/// The signature is a live price-distribution strip: every priced insurer as a
/// tick along a real KES axis, cheapest gold and dearest red. It is the honest
/// picture of price dispersion, it is specific to this data, and it previews
/// the ranked chart below instead of duplicating it. The old gradient number
/// (a ShaderMask 2.3x) is gone, because a big number washed in a gradient is
/// the generic hero and reads cheap on a retina panel.
///
/// Structure: the hook (spread plus strip), then the two things you can do
/// about it, then the evidence that justifies both. The disclaimer is now a
/// real bordered notice widget at the foot, not a stray run of faint text.
///
/// Apple 2.1: a category appears ONLY when a live flow with real data sits
/// behind it. Nothing here is a teaser.
class InsureOverlay extends ConsumerWidget {
  const InsureOverlay({super.key});

  /// A mid-market Kenyan saloon. Used only to make the spread concrete; every
  /// real quote reprices against the user's own value.
  static const double refValue = 3450000;

  bool _runnable(InsuranceType type, List<Insurer> insurers) {
    if (!type.isLive) return false;
    return switch (type.key) {
      'motor' => insurers.any((i) => i.hasMotor),
      'travel' => insurers.any((i) => i.hasTravel),
      _ => false,
    };
  }

  /// Live comprehensive premiums on the reference car, cheapest first.
  ///
  /// quote() returns null, never zero, for an insurer that does not write the
  /// class. Null means "we do not know what they charge", so that insurer is
  /// excluded from the spread rather than ranked cheapest, which would be the
  /// worst possible bug on a page whose whole argument is about price.
  static List<({Insurer insurer, double premium})> _quotes(
    List<Insurer> insurers,
  ) {
    final out = <({Insurer insurer, double premium})>[];
    for (final i in insurers) {
      final q = i.quote(
        refValue,
        cls: MotorClass.private,
        cover: CoverType.comprehensive,
      );
      if (q != null && q > 0) {
        out.add((insurer: i, premium: landedPremium(q)));
      }
    }
    out.sort((a, b) => a.premium.compareTo(b.premium));
    return out;
  }

  void _openType(BuildContext context, InsuranceType type) {
    final Widget? page = switch (type.key) {
      'motor' => const InsureMotorPage(),
      'travel' => const InsureTravelPage(),
      _ => null,
    };
    if (page == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rc = ref.watch(remoteConfigProvider);
    final insurers = ref.watch(insurersProvider);
    final types = ref
        .watch(insuranceTypesProvider)
        .where((t) => _runnable(t, insurers))
        .toList();

    if (insurers.isEmpty) {
      return _shell(context, [
        DisplayHeader(title: t('insure.title')),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            t('insure.emptyHome'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      ]);
    }

    final quotes = _quotes(insurers);
    final flagged = insurers.where((i) => !i.canWriteNewBusiness).length;

    // Every live category is a row now, uniform and scannable, no hero card.
    // Order follows the type list, so Motor sits first on its own.

    // Children are intentionally unkeyed. A keyed list moves elements
    // (deactivate then reactivate) when its shape changes, and reactivating a
    // Stagger re-runs SingleTickerProviderStateMixin._updateTickerModeNotifier,
    // the method in the crash trace. Unkeyed, the list updates children in
    // place and never calls it.
    return _shell(
      context,
      [
        DisplayHeader(title: t('insure.title')),
        _SpreadHero(quotes: quotes, insurers: insurers),
        if (quotes.length >= 2) _DistributionStrip(quotes: quotes),
        for (var k = 0; k < types.length; k++)
          Stagger(
            index: k,
            child: _CategoryRow(
              type: types[k],
              insurers: insurers,
              onTap: () => _openType(context, types[k]),
            ),
          ),
        Stagger(
          index: types.length,
          child: _DirectoryCard(
            insurers: insurers,
            flagged: flagged,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InsurerDirectoryPage()),
            ),
          ),
        ),
        if (quotes.length >= 2) ...[
          _SectionHead(
            title: t('insure.proof.title'),
            small: t('insure.proof.sub'),
          ),
          _SpreadChart(quotes: quotes),
        ],
        _CombinedRatioChart(rc: rc),
        _Notice(text: rcText(rc, 'insure.disc.home')),
      ],
      trailing: const _LivePill(),
    );
  }

  Widget _shell(
    BuildContext context,
    List<Widget> children, {
    Widget? trailing,
  }) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: trailing == null
            ? null
            : [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(child: trailing),
                ),
              ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 10),
        children: children,
      ),
    );
  }
}

/// A quiet "live data" marker for the app bar. IRA is a proper noun, so it is
/// not translated.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.up, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            'IRA',
            style: TextStyle(
              color: c.faint,
              fontFamily: fructaFonts.mono,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// hero ----------------------------------------------------------------------
/// The spread, stated as a plain fact.
///
/// Falls back to a licensed count when fewer than two insurers publish a rate.
/// It never falls back to a slogan: if we cannot prove a gap, we do not claim
/// one.
class _SpreadHero extends StatelessWidget {
  const _SpreadHero({required this.quotes, required this.insurers});

  final List<({Insurer insurer, double premium})> quotes;
  final List<Insurer> insurers;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final has = quotes.length >= 2;
    final multiple = has ? quotes.last.premium / quotes.first.premium : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.up,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                has
                    ? t('insure.hero.kicker', {'n': '${quotes.length}'})
                    : t('insure.hero.kickerNone'),
                style: TextStyle(
                  color: c.accent,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // A flat mono figure in the brand gold. No ShaderMask: the strip below
          // carries the colour, the number just states it.
          Text(
            has ? '${multiple!.toStringAsFixed(1)}x' : '${insurers.length}',
            style: TextStyle(
              color: has ? c.accent : c.text,
              fontFamily: fructaFonts.mono,
              fontSize: 58,
              height: 0.95,
              fontWeight: FontWeight.w800,
              letterSpacing: -3,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 300,
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.55),
                children: has
                    ? [
                        TextSpan(text: t('insure.hero.leadA')),
                        TextSpan(
                          text: t('insure.hero.leadB'),
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: t('insure.hero.leadC')),
                      ]
                    : [TextSpan(text: t('insure.hero.leadNone'))],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// signature: distribution strip ---------------------------------------------
/// Every priced insurer as a tick along a real KES axis, cheapest gold and
/// dearest red, the two endpoints labelled with amount and name.
///
/// The axis runs from the cheapest to the dearest premium, so the gap on screen
/// is the gap in price. Interior insurers are hairline ticks; only the two
/// endpoints, the numbers a reader acts on, get a value.
///
/// A car drives the axis once on entry, from the dearest end to the cheapest,
/// and parks above the gold node, its tint drifting from red to gold as it
/// arrives. The distance it covers IS the price gap, and it settles on the best
/// price we found, so the motion carries the argument rather than decorating it.
class _DistributionStrip extends StatefulWidget {
  const _DistributionStrip({required this.quotes});

  final List<({Insurer insurer, double premium})> quotes;

  @override
  State<_DistributionStrip> createState() => _DistributionStripState();
}

/// Deliberately a hand-rolled TickerProvider, NOT SingleTickerProviderStateMixin.
/// The mixin makes the state a dependent of the route's TickerMode and
/// re-resolves it (via _updateTickerModeNotifier) whenever the route transitions.
/// That re-resolution is the call in the crash trace: it looks up an inherited
/// widget, and during a pop the element can already be deactivated. A one-shot
/// entrance does not need TickerMode muting, so we provide a bare Ticker and the
/// crash surface goes with it.
class _DistributionStripState extends State<_DistributionStrip>
    implements TickerProvider {
  Ticker? _ticker;
  late final AnimationController _drive;
  late final Animation<double> _t;
  bool _kicked = false;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _ticker = Ticker(onTick, debugLabel: 'fructa.spread.car');
    return _ticker!;
  }

  @override
  void initState() {
    super.initState();
    _drive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _t = CurvedAnimation(parent: _drive, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    // Disposing the controller disposes the ticker it built via vsync. No
    // context is read here, so teardown never touches the element tree.
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Reduced motion is read in build, the correct place for a MediaQuery
    // dependency. The drive is kicked once, after the first frame.
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_kicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_kicked || !mounted) return;
        _kicked = true;
        if (reduce) {
          _drive.value = 0.12;
        } else {
          // Continuous, gentle shuttle. The glyph is a front-view car, so
          // sliding back and forth never looks like it is reversing.
          _drive.repeat(reverse: true);
        }
      });
    }
    final quotes = widget.quotes;
    final lo = quotes.first.premium;
    final hi = quotes.last.premium;
    final span = hi - lo;
    final interior = quotes.length > 2
        ? quotes.sublist(1, quotes.length - 1)
        : const <({Insurer insurer, double premium})>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
      child: SizedBox(
        height: 72,
        child: LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth;
            const node = 11.0;
            double px(double v) => span <= 0 ? w / 2 : ((v - lo) / span) * w;
            double clampX(double x, double size) => x.clamp(0.0, w - size);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // the road
                Positioned(
                  left: 0,
                  right: 0,
                  top: 52,
                  child: Container(height: 1, color: c.line2),
                ),
                // the other insurers
                for (final q in interior)
                  Positioned(
                    left: px(q.premium) - 0.75,
                    top: 46,
                    child: Container(
                      width: 1.5,
                      height: 13,
                      decoration: BoxDecoration(
                        color: c.faint.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                // endpoints
                Positioned(
                  left: clampX(px(hi) - node / 2, node),
                  top: 52 - node / 2,
                  child: _node(c.down, c.downSoft, c.bg),
                ),
                Positioned(
                  left: clampX(px(lo) - node / 2, node),
                  top: 52 - node / 2,
                  child: _node(c.accent, c.accentSoft, c.bg),
                ),
                // endpoint labels
                Positioned(
                  left: 0,
                  top: 0,
                  child: _flag(
                    context,
                    amount: kesCompact(lo),
                    who: shortInsurerName(quotes.first.insurer.name),
                    color: c.accent,
                    align: CrossAxisAlignment.start,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: _flag(
                    context,
                    amount: kesCompact(hi),
                    who: shortInsurerName(quotes.last.insurer.name),
                    color: c.down,
                    align: CrossAxisAlignment.end,
                  ),
                ),
                // the car, a front-view glyph so it has no facing to get wrong.
                // It shuttles the axis continuously and its tint tracks its
                // position, gold at the cheap end, red at the dear end. A plain
                // Icon moved by a mixin-free controller, no ticker-crash risk.
                AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) {
                    final v = _t.value.clamp(0.0, 1.0);
                    final x = px(lo) + (px(hi) - px(lo)) * v;
                    const carSize = 22.0;
                    return Positioned(
                      left: clampX(x - carSize / 2, carSize),
                      top: 52 - carSize,
                      child: Icon(
                        Icons.directions_car_filled,
                        size: carSize,
                        color: Color.lerp(c.accent, c.down, v),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _node(Color fill, Color halo, Color ring) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
        boxShadow: [BoxShadow(color: halo, blurRadius: 0, spreadRadius: 2)],
      ),
    );
  }

  Widget _flag(
    BuildContext context, {
    required String amount,
    required String who,
    required Color color,
    required CrossAxisAlignment align,
  }) {
    final c = context.c;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          amount,
          style: TextStyle(
            color: color,
            fontFamily: fructaFonts.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(who, style: TextStyle(color: c.faint, fontSize: 9.5)),
      ],
    );
  }
}

// category rows -------------------------------------------------------------
/// One live category as a row. Motor swaps the Material icon for the car sprite
/// pulled from the uploaded scene; every other class keeps its glyph.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.type,
    required this.insurers,
    required this.onTap,
  });

  final InsuranceType type;
  final List<Insurer> insurers;
  final VoidCallback onTap;

  String _sub() {
    if (type.key != 'motor') return type.sub ?? '';
    final motor = insurers.where((i) => i.hasMotor).length;
    double? minRate;
    for (final i in insurers) {
      final r = i.motorRate;
      if (r != null && (minRate == null || r < minRate)) minRate = r;
    }
    return minRate == null
        ? t('insure.card.nInsurers', {'n': '$motor'})
        : t('insure.card.motorSub', {
            'n': '$motor',
            'rate': minRate.toStringAsFixed(2),
          });
  }

  @override
  Widget build(BuildContext context) {
    return _SecondaryCard(
      icon: insureTypeIcon(type.key),
      title: type.label,
      sub: _sub(),
      onTap: onTap,
    );
  }
}

// secondary cards -----------------------------------------------------------
class _SecondaryCard extends StatelessWidget {
  const _SecondaryCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.trailing,
    this.child,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 11, 20, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.s3,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: c.muted),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 7),
                          trailing!,
                        ],
                      ],
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        style: TextStyle(color: c.faint, fontSize: 11),
                      ),
                    ],
                    if (child != null) ...[
                      const SizedBox(height: 10),
                      child!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The register card. The FLAGGED count is the hook: nothing else in Kenya
/// tells a retail buyer which insurer the regulator seized.
class _DirectoryCard extends StatelessWidget {
  const _DirectoryCard({
    required this.insurers,
    required this.flagged,
    required this.onTap,
  });

  final List<Insurer> insurers;
  final int flagged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _SecondaryCard(
      icon: Icons.verified_outlined,
      title: t('insure.dir.title'),
      sub: t('insure.dir.entry', {'n': '${insurers.length}'}),
      onTap: onTap,
      trailing: flagged == 0
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: c.downSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t('insure.dir.flaggedN', {'n': '$flagged'}),
                style: TextStyle(
                  color: c.down,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      child: _LogoWall(insurers: insurers),
    );
  }
}

/// Overlapping marks, capped with a "+N". Ringed in the panel colour so the
/// discs read as separate discs without a dark halo.
class _LogoWall extends StatelessWidget {
  const _LogoWall({required this.insurers});
  final List<Insurer> insurers;

  static const double _size = 26;
  static const double _step = 19;
  static const int _cap = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Lead with the ones we can price: they are the ones with real marks, and a
    // wall of monograms says nothing.
    final ranked = [...insurers]..sort((a, b) {
      final pa = (a.hasMotor || a.hasTravel) ? 0 : 1;
      final pb = (b.hasMotor || b.hasTravel) ? 0 : 1;
      return pa.compareTo(pb);
    });
    final shown = ranked.take(_cap).toList();
    final extra = insurers.length - shown.length;
    final slots = shown.length + (extra > 0 ? 1 : 0);

    return SizedBox(
      height: _size,
      width: _size + _step * (slots - 1),
      child: Stack(
        children: [
          for (var k = 0; k < shown.length; k++)
            Positioned(
              left: _step * k,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.s1, width: 1.5),
                ),
                child: InsurerLogo(shown[k], size: _size),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: _step * shown.length,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.s3,
                  border: Border.all(color: c.s1, width: 1.5),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// evidence ------------------------------------------------------------------
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.small});
  final String title;
  final String small;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              small,
              style: TextStyle(color: c.faint, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpreadChart extends StatelessWidget {
  const _SpreadChart({required this.quotes});
  final List<({Insurer insurer, double premium})> quotes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dearest = quotes.last.premium;
    final cheapest = quotes.first.premium;
    final last = quotes.length - 1;

    return Stagger(
      index: 0,
      child: BarChart(
        title: t('insure.proof.chartTitle'),
        subtitle: t('insure.proof.chartSub', {
          'value': kesCompact(InsureOverlay.refValue),
        }),
        bars: [
          for (var k = 0; k < quotes.length; k++)
            BarDatum(
              label: shortInsurerName(quotes[k].insurer.name),
              value: quotes[k].premium / dearest,
              display: kesCompact(quotes[k].premium),
              color: k == 0
                  ? c.accent
                  : k == last
                      ? c.down
                      : c.line2,
              highlight: k == 0 || k == last,
            ),
        ],
        foot: t('insure.proof.chartFoot', {
          'gap': kesCompact(dearest - cheapest),
          'cheap': shortInsurerName(quotes.first.insurer.name),
          'dear': shortInsurerName(quotes.last.insurer.name),
        }),
      ),
    );
  }
}

/// Combined ratio by class, from remote config.
///
/// This is the only chart on the page that cannot come from insurer rows, and
/// it is worth being explicit about why. Kenya publishes NO per-insurer
/// combined ratio, only these class-wide IRA figures. So the honest ceiling of
/// what we can say about underwriting profitability is "the motor book loses
/// money", never "this insurer's book loses money".
///
/// An unset key renders no bar. All four unset, and the section vanishes.
class _CombinedRatioChart extends StatelessWidget {
  const _CombinedRatioChart({required this.rc});
  final RemoteConfig rc;

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final rows = <({String label, double value})>[
      (
        label: t('insure.cr.motorCommercial'),
        value: rc.number('insure.cr.motor_commercial', 0),
      ),
      (
        label: t('insure.cr.motorPrivate'),
        value: rc.number('insure.cr.motor_private', 0),
      ),
      (label: t('insure.cr.medical'), value: rc.number('insure.cr.medical', 0)),
      (label: t('insure.cr.marine'), value: rc.number('insure.cr.marine', 0)),
    ].where((r) => r.value > 0).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    final worst = rows.map((r) => r.value).reduce((a, b) => a > b ? a : b);

    return Stagger(
      index: 1,
      child: BarChart(
        title: t('insure.cr.title'),
        subtitle: t('insure.cr.sub'),
        labelWidth: 88,
        bars: [
          for (final r in rows)
            BarDatum(
              label: r.label,
              value: r.value / worst,
              display: r.value.toStringAsFixed(0),
              // Above 100 the class pays out more than it takes in. The colour
              // carries that threshold, so a reader who skips the footnote
              // still gets the point.
              color: r.value >= 110
                  ? c.down
                  : r.value >= 100
                      ? c.accent
                      : c.up,
              highlight: r.value >= 110,
            ),
        ],
        foot: t('insure.cr.foot'),
      ),
    );
  }
}

// notice --------------------------------------------------------------------
/// The disclaimer as a real bordered notice, not a stray run of faint text. It
/// carries the remote-config disclaimer plus the on-device privacy note.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 40),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 16, color: c.faint),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '$text ${t('insure.privacyNote')}',
                style: TextStyle(color: c.faint, fontSize: 11, height: 1.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

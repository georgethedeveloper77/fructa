import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../data/models/insurer.dart';
import '../../../data/snapshot_providers.dart';
import '../../insure/insure_common.dart';

/// Insurance spotlight on Markets, V10.
///
/// Matches the house card pattern (external mono eyebrow, s1 panel, line border,
/// radius 18) and now shares the home screen's signature: a compact
/// price-distribution strip. A tap from here lands on a screen that already
/// looks familiar.
///
/// The eyebrow is just "INSURANCE". We carry more than motor, so the card must
/// not brand itself around one class or a fixed licensed count. The body is
/// data-driven: when the market publishes a comprehensive spread we lead with
/// it, otherwise we fall back to the plainest true statement and a logo stack.
/// The old radial gradient wash is gone.
class InsuranceSpotlight extends ConsumerWidget {
  const InsuranceSpotlight({super.key, required this.onTap});

  final VoidCallback onTap;

  /// A mid-market saloon. Only ever used to make the spread concrete; the real
  /// quote screen reprices against the user's own value.
  static const double _refValue = 3450000;

  static String compact(num v) {
    final d = v.toDouble();
    if (d >= 1e6) {
      final m = d / 1e6;
      return '${m >= 10 ? m.round() : m.toStringAsFixed(1)}M';
    }
    if (d >= 1000) return '${(d / 1000).round()}k';
    return d.round().toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final insurers = ref.watch(insurersProvider);
    if (insurers.isEmpty) return const SizedBox.shrink();

    final flow = insurers.where((i) => i.hasMotor || i.hasTravel).toList();

    // Live comprehensive quotes on one reference car. quote() returns null,
    // never zero, for an insurer that does not write the class, so an unknown
    // price is excluded rather than ranked cheapest.
    final premiums = <double>[];
    for (final i in insurers) {
      final q = i.quote(
        _refValue,
        cls: MotorClass.private,
        cover: CoverType.comprehensive,
      );
      if (q != null && q > 0) premiums.add(landedPremium(q));
    }
    premiums.sort();

    final hasSpread = premiums.length >= 2;
    final cheapest = hasSpread ? premiums.first : null;
    final dearest = hasSpread ? premiums.last : null;
    final multiple = hasSpread ? dearest! / cheapest! : null;

    // Headline: the spread when we can prove one, otherwise the plainest true
    // statement we can make. Never a slogan.
    final headline = hasSpread
        ? 'The same car, ${multiple!.toStringAsFixed(1)}x apart'
        : 'Compare cover from ${flow.length} insurers';

    final sub = hasSpread
        ? 'KES ${compact(cheapest!)} to KES ${compact(dearest!)} '
              'for identical comprehensive cover'
        : 'Published rates only, never an estimate';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // External eyebrow. Just the class name and the action: no fixed
          // licensed count, no motor-only framing.
          Row(
            children: [
              Text(
                'INSURANCE',
                style: TextStyle(
                  color: c.faint,
                  fontFamily: fructaFonts.mono,
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Compare',
                style: TextStyle(
                  color: c.accentInk,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: c.accentInk),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.shield_outlined, color: c.accent),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              headline,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 14.5,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sub,
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // The signature strip when we can prove a spread, otherwise a
                  // logo stack so the card is never empty.
                  if (hasSpread)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _CompactStrip(premiums: premiums),
                    )
                  else if (flow.length >= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: _AvatarStack(insurers: flow),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The home screen's distribution strip, shrunk to a card. Endpoints only,
/// interior insurers as hairline ticks. Nodes ring in the PANEL colour (s1),
/// not the page colour, so they do not draw a dark halo on the card fill.
///
/// The same car sprite as the home strip drives slowly start to end. Its
/// controller is driven by a hand-rolled TickerProvider, never
/// SingleTickerProviderStateMixin, so a card scrolling out of the list cannot
/// re-run the ticker lookup that crashes on teardown.
class _CompactStrip extends StatefulWidget {
  const _CompactStrip({required this.premiums});
  final List<double> premiums;

  @override
  State<_CompactStrip> createState() => _CompactStripState();
}

class _CompactStripState extends State<_CompactStrip>
    implements TickerProvider {
  Ticker? _ticker;
  late final AnimationController _drive;
  late final Animation<double> _t;
  bool _kicked = false;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _ticker = Ticker(onTick, debugLabel: 'fructa.spread.car.card');
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
    _drive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_kicked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_kicked || !mounted) return;
        _kicked = true;
        if (reduce) {
          _drive.value = 0.12;
        } else {
          _drive.repeat(reverse: true);
        }
      });
    }

    final premiums = widget.premiums;
    final lo = premiums.first;
    final hi = premiums.last;
    final span = hi - lo;
    final interior = premiums.length > 2
        ? premiums.sublist(1, premiums.length - 1)
        : const <double>[];

    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth;
          const node = 9.0;
          double px(double v) => span <= 0 ? w / 2 : ((v - lo) / span) * w;
          double clampX(double x, double size) => x.clamp(0.0, w - size);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Text(
                  InsuranceSpotlight.compact(lo),
                  style: TextStyle(
                    color: c.accent,
                    fontFamily: fructaFonts.mono,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Text(
                  InsuranceSpotlight.compact(hi),
                  style: TextStyle(
                    color: c.down,
                    fontFamily: fructaFonts.mono,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 30,
                child: Container(height: 1, color: c.line2),
              ),
              for (final v in interior)
                Positioned(
                  left: px(v) - 0.75,
                  top: 26,
                  child: Container(
                    width: 1.5,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.faint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              Positioned(
                left: clampX(px(hi) - node / 2, node),
                top: 30 - node / 2,
                child: _dot(c.down, c.s1),
              ),
              Positioned(
                left: clampX(px(lo) - node / 2, node),
                top: 30 - node / 2,
                child: _dot(c.accent, c.s1),
              ),
              AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  final v = _t.value.clamp(0.0, 1.0);
                  final x = px(lo) + (px(hi) - px(lo)) * v;
                  const carSize = 16.0;
                  return Positioned(
                    left: clampX(x - carSize / 2, carSize),
                    top: 30 - carSize,
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
    );
  }

  Widget _dot(Color fill, Color ring) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
      ),
    );
  }
}

/// Overlapping insurer logos, capped with a "+N" bubble. Ringed in the PANEL
/// colour (s1), not the page colour, now that the card has a fill: ringing in
/// c.bg on an s1 card drew a visible dark halo around every disc.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.insurers});
  final List<Insurer> insurers;

  static const double _size = 24;
  static const double _step = 16;
  static const int _cap = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shown = insurers.take(_cap).toList();
    final extra = insurers.length - shown.length;
    final slots = shown.length + (extra > 0 ? 1 : 0);
    final width = _size + _step * (slots - 1);

    return SizedBox(
      height: _size,
      width: width,
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
                // InsurerLogo, not FundLogo: it resolves the hosted company
                // logo before falling back to the domain, which the old call
                // never did. That is why every insurer here rendered as a
                // monogram even when a real mark was uploaded.
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

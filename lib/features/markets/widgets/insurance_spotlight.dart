import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/kit.dart';
import '../../../data/models/insurer.dart';
import '../../../data/snapshot_providers.dart';
import '../../insure/insure_common.dart';

/// Insurance spotlight -> Insure home. Everything on this card is composed from
/// live insurer data (admin-controlled): the headline names whichever covers
/// actually have a runnable flow, the "from" figure is the cheapest entry point
/// across them, and the avatar stack shows who's in. Nothing is hardcoded, so
/// when a new cover (health, ...) goes live it joins the headline automatically.
class InsuranceSpotlight extends ConsumerWidget {
  const InsuranceSpotlight({super.key, required this.onTap});

  final VoidCallback onTap;

  static String _kes(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return 'KES ${b.toString()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final insurers = ref.watch(insurersProvider);

    final motor = insurers.where((i) => i.hasMotor).toList();
    final travel = insurers.where((i) => i.hasTravel).toList();

    // Live categories drive the headline text.
    final cats = <String>[
      if (motor.isNotEmpty) 'motor',
      if (travel.isNotEmpty) 'travel',
    ];
    final headline = cats.isEmpty
        ? 'Compare insurance cover'
        : 'Compare ${cats.join(' & ')} cover';

    // Cheapest entry point across whatever is live: motor floor first (annual),
    // else the cheapest travel plan.
    num? motorFrom;
    for (final i in motor) {
      final p = i.minPremium;
      if (p != null && (motorFrom == null || p < motorFrom!)) motorFrom = p;
    }
    num? travelFrom;
    for (final i in travel) {
      for (final TravelPlan p in i.plans) {
        if (travelFrom == null || p.price < travelFrom!) travelFrom = p.price;
      }
    }
    String? fromText;
    if (motorFrom != null) {
      fromText = 'from ${_kes(motorFrom!)}/yr';
    } else if (travelFrom != null) {
      fromText = 'from ${_kes(travelFrom!)}';
    }

    final flow = insurers.where((i) => i.hasMotor || i.hasTravel).toList();
    final n = flow.length;
    final subParts = <String>[
      if (n > 0) '$n ${n == 1 ? 'insurer' : 'insurers'}',
      if (fromText != null) fromText,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Accent ambient glow, matching the gold insurance surface.
              Positioned(
                left: -80,
                top: -60,
                bottom: -60,
                child: Container(
                  width: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        c.accent.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
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
                        Text('INSURANCE',
                            style: TextStyle(
                                color: c.accent,
                                fontSize: 9.5,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(headline,
                            style: TextStyle(
                                color: c.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        if (subParts.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(subParts.join(' \u00b7 '),
                              style: TextStyle(
                                  color: c.muted, fontSize: 10.5)),
                        ],
                        if (flow.length >= 3) ...[
                          const SizedBox(height: 9),
                          _AvatarStack(insurers: flow),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.faint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overlapping insurer logos (a partner wall in miniature), capped with a
/// "+N" bubble. Ringed in the page background so they read as separate discs.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.insurers});
  final List<Insurer> insurers;

  static const double _size = 22;
  static const double _step = 15;
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
                  border: Border.all(color: c.bg, width: 1.5),
                ),
                child: FundLogo(
                  domain: shown[k].logoDomain,
                  seed: shown[k].name,
                  size: _size,
                  brandColor: insurerBrand(context, shown[k]),
                ),
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
                  border: Border.all(color: c.bg, width: 1.5),
                ),
                child: Text('+$extra',
                    style: TextStyle(
                        color: c.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

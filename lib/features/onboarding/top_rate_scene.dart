import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loader.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// Onboarding opener: the single number. Before we ask the user anything, we
/// show them the best KES money market rate in the country right now, count it
/// up from zero, and draw its own recent series underneath it.
///
/// This is the first thing a new install sees, and it is deliberately the same
/// composition as Play Store frame 01, so a device capture of this screen is
/// the store asset. One artifact, two jobs, and the number can never drift from
/// what the app actually served.
///
/// Gross is the large figure and net sits directly under it. The distance
/// between the two is the product's whole argument, so burying net would waste
/// the best screen we have. Flip [_heroIsGross] to lead with net instead.
///
/// No AnimationController lives here. The count-up and the curve draw both run
/// on TweenAnimationBuilder, which cannot reach the deactivated-ticker crash
/// path and, usefully, begins at zero the moment data lands, so a slow snapshot
/// produces the count-up rather than a jump.
class TopRateScene extends ConsumerWidget {
  const TopRateScene({super.key, required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// Which figure gets the display size. Gross reads as the headline the market
  /// advertises; net sits under it as the correction.
  static const bool _heroIsGross = true;

  /// Highest current yield among retail KES money market funds.
  ///
  /// `currency` is filtered explicitly and not inferred from the id: at least
  /// one fund carries a `-kes` suffix while actually being a USD share class,
  /// and quoting a dollar yield as "Kenya's best rate" would be a lie the user
  /// discovers thirty seconds later in the markets list.
  ///
  /// The type is pinned to mmf for the same reason. A fixed income fund can
  /// out-print an MMF, but it is not the thing this screen claims to show, and
  /// a headline the user cannot then find under Money Market costs us trust on
  /// the first screen of the app.
  Fund? _topKesMmf(List<Fund> funds) {
    Fund? best;
    for (final f in funds) {
      final r = f.currentRate;
      if (f.retail &&
          f.showsYield &&
          f.fundType == 'mmf' &&
          f.currency == 'KES' &&
          r != null) {
        if (best == null || r > (best.currentRate ?? 0)) best = f;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];

    final top = _topKesMmf(funds);
    final loading = funds.isEmpty;

    final wht = cfg.whtPct;
    final gross = top?.currentRate;
    final net = top?.netRate(wht);

    final hero = _heroIsGross ? gross : net;
    final under = _heroIsGross ? net : gross;

    // Funds tracked, stated honestly: the retail cut is what the user can
    // actually browse, not the full dormant tail in the table.
    final tracked = funds.where((f) => f.retail).length;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _LiveEyebrow(),
                      const SizedBox(height: 12),
                      Text(
                        cfg.string(
                          'onboarding.topRateTitle',
                          'Kenya\u2019s best rate today',
                        ),
                        style: TextStyle(
                          fontFamily: fructaFonts.mono,
                          fontSize: 29,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: c.text,
                        ),
                      ),

                      const SizedBox(height: 28),

                      if (loading || hero == null)
                        _LoadingBlock(tracked: tracked)
                      else ...[
                        _BigRate(value: hero),
                        const SizedBox(height: 10),
                        _UnderRate(
                          value: under,
                          whtPct: wht,
                          heroIsGross: _heroIsGross,
                          taxFree: top?.taxFree ?? false,
                        ),
                        const SizedBox(height: 26),
                        _FundIdentity(fund: top!),
                        const SizedBox(height: 20),
                        _RateCurve(series: top.spark, line: c.accent),
                      ],

                      const SizedBox(height: 26),
                      _Facts(tracked: tracked),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(
                    cfg.string(
                      'onboarding.topRateCta',
                      'See what it would earn you',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: c.faint),
                  child: Text(
                    cfg.string('onboarding.skip', 'I just want the rates'),
                    style: const TextStyle(fontSize: 12.5),
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

/// Manager mark, fund name, and the terms a reader checks next.
///
/// A separate ConsumerWidget so the logo and brand-colour lookups are not
/// conditional watches inside the parent's build: the parent only reaches this
/// once a fund exists, and this widget owns its own subscriptions.
///
/// [FundLogo] paints a seeded monogram immediately and swaps in the remote mark
/// when it arrives, so a cold install with no image cache still renders a solid
/// identity block on the first frame rather than a grey square.
class _FundIdentity extends ConsumerWidget {
  const _FundIdentity({required this.fund});
  final Fund fund;

  /// "Money market, KES, min KES 100,000". Parts the fund does not carry are
  /// left out rather than printed as a placeholder.
  String _meta() {
    final parts = <String>['Money market', fund.currency];
    final min = fund.minInvest;
    if (min != null && min > 0) {
      parts.add('min ${fund.currency} ${withCommas(min)}');
    }
    return parts.join('  \u00B7  ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final logoUrl = ref.watch(logoUrlProvider(fund.id));
    final tint =
        ref.watch(brandColorProvider(fund.id)) ?? categoryColor(fund.category);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FundLogo(
          domain: fund.logoDomain,
          logoUrl: logoUrl,
          seed: fund.manager,
          size: 42,
          brandColor: tint,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fund.name,
                softWrap: true,
                style: TextStyle(
                  color: c.text,
                  fontSize: 17,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _meta(),
                softWrap: true,
                style: TextStyle(
                  color: c.faint,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Pulsing-free live marker, matching the gap scene's eyebrow so the two
/// opening screens read as one sequence.
class _LiveEyebrow extends StatelessWidget {
  const _LiveEyebrow();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c.up, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          'LIVE RATES \u00B7 TODAY',
          style: TextStyle(
            color: c.up,
            fontSize: 11,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The display figure. Counts up from zero over 900ms.
///
/// FittedBox rather than a fixed size, because a user on the 1.3 text scale set
/// in the appearance scene would otherwise overflow this row on a narrow phone.
class _BigRate extends StatelessWidget {
  const _BigRate({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: v.toStringAsFixed(2)),
              TextSpan(
                text: '%',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w600,
                  color: c.accent.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          style: TextStyle(
            fontFamily: fructaFonts.mono,
            fontSize: 76,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -2.5,
            color: c.accent,
          ),
        ),
      ),
    );
  }
}

/// The correction line under the hero figure. This is the sentence the rest of
/// the market does not print.
class _UnderRate extends StatelessWidget {
  const _UnderRate({
    required this.value,
    required this.whtPct,
    required this.heroIsGross,
    required this.taxFree,
  });

  final double? value;
  final double whtPct;
  final bool heroIsGross;
  final bool taxFree;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = value;
    if (v == null) return const SizedBox.shrink();

    // A tax-free fund has no gap to show, so claiming one would be wrong.
    if (taxFree) {
      return Text(
        'Tax free, so this is what you keep',
        style: TextStyle(color: c.up, fontSize: 13.5, fontWeight: FontWeight.w600),
      );
    }

    final label = heroIsGross
        ? 'You keep ${v.toStringAsFixed(2)}% after ${whtPct.toStringAsFixed(0)}% withholding tax'
        : 'Advertised as ${v.toStringAsFixed(2)}% before tax';

    return Text(
      label,
      style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4),
    );
  }
}

/// The fund's own recent series, drawn on left to right.
///
/// Real data, not a decorative shape: an invented curve under a real number is
/// the kind of detail that reads as fine until someone checks it.
class _RateCurve extends StatelessWidget {
  const _RateCurve({required this.series, required this.line});

  final List<double> series;
  final Color line;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => CustomPaint(
          painter: _CurvePainter(series: series, progress: t, line: line),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.series,
    required this.progress,
    required this.line,
  });

  final List<double> series;
  final double progress;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    var lo = series.first, hi = series.first;
    for (final v in series) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    // A flat series would divide by zero; give it a mid-height straight line.
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;

    // Inset vertically so the extremes do not sit hard against the edges.
    double y(double v) => h * 0.9 - ((v - lo) / span) * (h * 0.8);
    double x(int i) => w * i / (series.length - 1);

    final path = Path()..moveTo(x(0), y(series[0]));
    for (var i = 1; i < series.length; i++) {
      path.lineTo(x(i), y(series[i]));
    }

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.first;
    final len = m.length * progress.clamp(0.0, 1.0);
    if (len <= 0) return;

    final drawn = m.extractPath(0, len);
    final tip = m.getTangentForOffset(len)?.position;

    if (tip != null) {
      final area = Path.from(drawn)
        ..lineTo(tip.dx, h)
        ..lineTo(x(0), h)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [line.withValues(alpha: 0.20), line.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (tip != null && progress > 0.98) {
      canvas.drawCircle(tip, 4.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.progress != progress || old.line != line || old.series != series;
}

/// Shown while the snapshot is still in flight.
///
/// The splash is a fixed 2800ms animation with no data dependency, so on a cold
/// install over a poor connection this scene can mount before rates land. A
/// spinner sitting where the headline number belongs would be the worst
/// possible first frame, so the block keeps the scene's shape and says plainly
/// what it is waiting for.
class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.tracked});
  final int tracked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
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
              const AppLoader(size: 22),
              const SizedBox(width: 10),
              Text(
                'Getting today\u2019s rates',
                style: TextStyle(color: c.muted, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pulling live yields from every licensed fund manager in Kenya.',
            style: TextStyle(color: c.faint, fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Three standing facts, divided the way the Play frame divides them.
class _Facts extends StatelessWidget {
  const _Facts({required this.tracked});
  final int tracked;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = <({String k, String v})>[
      (k: tracked > 0 ? '$tracked' : 'Every', v: 'funds tracked'),
      (k: 'Daily', v: 'rate updates'),
      (k: 'None', v: 'signup needed'),
    ];

    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: c.line,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].k,
                    style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      color: c.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    items[i].v,
                    softWrap: true,
                    style: TextStyle(color: c.faint, fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_colors.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loader.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// Onboarding opener, the gap. Slide to a balance and watch three rates race in
/// from zero: the best money market fund the balance can actually open, the
/// 91-day T-bill as a reference, and a bank savings rate. Bars sit on a fixed
/// axis (a rate ceiling), so a full bar is never implied and the gap between
/// them is the message. The money-market rate is minimum-aware, and the balance
/// and payoff count as the slider moves.
class GapScene extends ConsumerStatefulWidget {
  const GapScene({super.key, required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  ConsumerState<GapScene> createState() => _GapSceneState();
}

class _GapSceneState extends ConsumerState<GapScene> {
  // Log slider: low amounts get real room on the track, so a low-income user can
  // dial down to 10k or less instead of it being a cramped sliver at the far
  // left of a linear range that reaches 5M.
  static const _minAmt = 1000.0;
  static const _maxAmt = 5000000.0;

  // Slider position, 0..1; the balance is derived from it on a log scale.
  late double _pos;

  double get _amount {
    final raw = _minAmt * math.pow(_maxAmt / _minAmt, _pos);
    return (raw / 1000).round() * 1000.0; // clean thousands
  }

  @override
  void initState() {
    super.initState();
    final seed = ref
        .read(remoteConfigProvider)
        .number('onboarding.gapSeed', 250000)
        .toDouble()
        .clamp(_minAmt, _maxAmt);
    _pos = (math.log(seed / _minAmt) / math.log(_maxAmt / _minAmt)).clamp(
      0.0,
      1.0,
    );
  }

  /// Best MMF the user can actually open at [amount]: highest current rate among
  /// retail money-market funds whose minimum is at or below the balance.
  Fund? _eligibleTop(List<Fund> funds, double amount) {
    Fund? best;
    for (final f in funds) {
      final r = f.currentRate;
      final min = f.minInvest ?? 0;
      if (f.retail &&
          f.showsYield &&
          f.fundType == 'mmf' &&
          r != null &&
          min <= amount) {
        if (best == null || r > (best!.currentRate ?? 0)) best = f;
      }
    }
    return best;
  }

  /// Overall top MMF ignoring the minimum, to name what a larger deposit unlocks.
  Fund? _overallTop(List<Fund> funds) {
    Fund? best;
    for (final f in funds) {
      final r = f.currentRate;
      if (f.retail && f.showsYield && f.fundType == 'mmf' && r != null) {
        if (best == null || r > (best!.currentRate ?? 0)) best = f;
      }
    }
    return best;
  }

  /// Most accessible MMF (lowest minimum), to tell a small balance where it can
  /// start.
  Fund? _mostAccessible(List<Fund> funds) {
    Fund? m;
    for (final f in funds) {
      if (f.retail &&
          f.showsYield &&
          f.fundType == 'mmf' &&
          f.currentRate != null) {
        if (m == null || (f.minInvest ?? 0) < (m!.minInvest ?? 0)) m = f;
      }
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final funds = ref.watch(ratesProvider).value ?? const <Fund>[];

    final eligible = _eligibleTop(funds, _amount);
    final mostAccessible = _mostAccessible(funds);
    final overall = _overallTop(funds);

    // The MMF bar shows the best fund the balance can open; if the balance is
    // below every floor it falls back to the most accessible fund, flagged.
    final mmfFund = eligible ?? mostAccessible;
    final canOpen = eligible != null;

    final mmf = mmfFund?.currentRate ?? 0;
    final tbill = cfg.tbill91Pct;
    final bank = cfg.number('onboarding.bankRate', 2.5).toDouble();
    final wht = cfg.number('onboarding.gapWht', 0.15).toDouble();

    final loading = funds.isEmpty;

    // A higher-rate fund the balance cannot reach, named so the user sees what a
    // larger deposit unlocks (only relevant once they can open something).
    final locked =
        (canOpen &&
            overall != null &&
            (overall.minInvest ?? 0) > _amount &&
            overall.id != eligible!.id)
        ? overall
        : null;

    // Fixed rate axis: bars fill proportionally to their rate against a ceiling,
    // so none reaches the end (a full bar would imply 100%). The gap between
    // them is the message. One config value moves the ceiling.
    final axisMax = cfg.number('onboarding.gapAxisMax', 20).toDouble();
    double factor(double r) => (r / axisMax).clamp(0.0, 1.0);

    final netGain = _amount * (mmf - bank) / 100 * (1 - wht);

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
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: c.up,
                              shape: BoxShape.circle,
                            ),
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
                      ),
                      const SizedBox(height: 12),
                      Text(
                        cfg.string(
                          'onboarding.gapTitle',
                          'See what your cash could earn',
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
                      const SizedBox(height: 10),
                      Text(
                        cfg.string(
                          'onboarding.gapSub',
                          'See the market against your bank. Slide to your balance.',
                        ),
                        style: TextStyle(
                          color: c.muted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text(
                        'You have',
                        style: TextStyle(color: c.faint, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: _amount),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        builder: (_, v, __) => Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'KES ',
                                style: TextStyle(
                                  color: c.faint,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: _grouped(v)),
                            ],
                          ),
                          style: TextStyle(
                            fontFamily: fructaFonts.mono,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: c.accent,
                          inactiveTrackColor: c.s3,
                          thumbColor: c.accent,
                          overlayColor: c.accent.withValues(alpha: 0.14),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 20,
                          ),
                        ),
                        child: Slider(
                          value: _pos,
                          onChanged: (v) => setState(() => _pos = v),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KES 1K',
                              style: TextStyle(
                                color: c.faint,
                                fontFamily: fructaFonts.mono,
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              'KES 5M',
                              style: TextStyle(
                                color: c.faint,
                                fontFamily: fructaFonts.mono,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      if (loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Row(
                            children: [
                              const AppLoader(size: 22),
                              const SizedBox(width: 10),
                              Text(
                                'Getting today\u2019s rates',
                                style: TextStyle(color: c.muted, fontSize: 13.5),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _Bar(
                          label: 'Money market fund',
                          rate: mmf,
                          factor: factor(mmf),
                          fill: c.accent,
                          rateColor: c.accent,
                          track: c.s2,
                        ),
                        const SizedBox(height: 16),
                        _Bar(
                          label: '91-day T-bill',
                          rate: tbill,
                          factor: factor(tbill),
                          fill: categoryColor('tbill'),
                          rateColor: categoryColor('tbill'),
                          track: c.s2,
                        ),
                        const SizedBox(height: 16),
                        _Bar(
                          label: 'Bank savings',
                          rate: bank,
                          factor: factor(bank),
                          fill: c.down,
                          rateColor: c.down,
                          track: c.s2,
                        ),
                        const SizedBox(height: 12),
                        if (canOpen)
                          Text(
                            'Top fund you can open: ${eligible!.name}',
                            style: TextStyle(
                              color: c.faint,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          )
                        else if (mostAccessible != null)
                          Text(
                            'You need KES ${_grouped(mostAccessible.minInvest ?? 0)} to open ${mostAccessible.name}.',
                            style: TextStyle(
                              color: c.faint,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        if (locked != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${locked.name.split(' ').first} pays ${(locked.currentRate ?? 0).toStringAsFixed(2)}% but needs KES ${_grouped(locked.minInvest ?? 0)} minimum.',
                            style: TextStyle(
                              color: c.faint,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.only(top: 18),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: c.line)),
                          ),
                          child: canOpen
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'A money market fund would earn you',
                                      style: TextStyle(
                                        color: c.muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(end: netGain),
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      curve: Curves.easeOut,
                                      builder: (_, v, __) => Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'KES ',
                                              style: TextStyle(
                                                color: c.faint,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(text: _grouped(v)),
                                            TextSpan(
                                              text: '  / year',
                                              style: TextStyle(
                                                color: c.muted,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        style: TextStyle(
                                          fontFamily: fructaFonts.mono,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -1,
                                          color: c.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'After ${(wht * 100).toStringAsFixed(0)}% withholding tax, versus bank savings.',
                                      style: TextStyle(
                                        color: c.faint,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'Slide up to your balance to see what a fund would earn you.',
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: widget.onNext,
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
                    cfg.string('onboarding.gapCta', 'See where to start'),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: widget.onSkip,
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

/// One labeled bar on the fixed rate axis. The fill races in slowly and
/// gradually on first build, then re-settles quickly when the slider changes
/// the rate; it never reaches the end.
class _Bar extends StatefulWidget {
  const _Bar({
    required this.label,
    required this.rate,
    required this.factor,
    required this.fill,
    required this.rateColor,
    required this.track,
  });

  final String label;
  final double rate;
  final double factor;
  final Color fill;
  final Color rateColor;
  final Color track;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  // Slow, gradual first fill; quick, responsive re-settle on slider moves.
  static const _raceIn = Duration(milliseconds: 1500);
  static const _settle = Duration(milliseconds: 320);

  late final AnimationController _c;
  late Animation<double> _anim;

  double get _target => widget.factor.clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _raceIn);
    _anim = Tween<double>(
      begin: 0,
      end: _target,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic));
    _c.forward();
  }

  @override
  void didUpdateWidget(covariant _Bar old) {
    super.didUpdateWidget(old);
    final target = _target;
    if (target != old.factor.clamp(0.0, 1.0)) {
      _c.duration = _settle;
      _anim = Tween<double>(
        begin: _anim.value,
        end: target,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: TextStyle(color: c.muted, fontSize: 14)),
            Text(
              '${widget.rate.toStringAsFixed(2)}%',
              style: TextStyle(
                fontFamily: fructaFonts.mono,
                color: widget.rateColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Container(
            height: 12,
            color: widget.track,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _anim.value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.fill.withValues(alpha: 0.75),
                        widget.fill,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _grouped(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

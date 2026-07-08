import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import '../../data/models/fund.dart';
import '../../data/providers.dart';
import '../../data/snapshot_providers.dart';

/// Onboarding stage 3 — make it yours. Accent + text size, previewed on a real
/// rate card so theming lands on the product's own object, not an abstract
/// swatch. Writes straight through `themeController`; light/dark still follows
/// the system (we never force a mode here).
class AppearanceScene extends ConsumerWidget {
  const AppearanceScene({super.key, required this.onNext});
  final VoidCallback onNext;

  Fund? _sampleFund(List<Fund> funds) {
    Fund? best;
    for (final f in funds) {
      if (f.retail && f.showsYield && f.currentRate != null) {
        if (best == null || f.currentRate! > best!.currentRate!) best = f;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final cfg = ref.watch(remoteConfigProvider);
    final accent = ref.watch(accentProvider);
    final scale = ref.watch(textScaleProvider);
    final funds = ref.watch(ratesProvider).valueOrNull ?? const <Fund>[];
    final sample = _sampleFund(funds);

    final name = sample?.name ?? 'Etica Money Market';
    final rate = sample?.currentRate ?? 10.67;
    final net = (sample?.taxFree ?? false) ? rate : rate * 0.85;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Rail(step: 1),
              const SizedBox(height: 22),
              Text('MAKE IT YOURS',
                  style: TextStyle(
                      color: c.faint,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Pick your look',
                  style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: c.text)),
              const SizedBox(height: 8),
              Text(
                cfg.string('onboarding.lookSub',
                    "Light or dark follows your phone. Choose an accent and a comfortable size — here's how a rate card will read."),
                style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 20),

              // Live sample card — recolors with accent, resizes with the
              // chosen scale (explicit textScaler → truthful preview).
              MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: _SampleCard(name: name, rate: rate, net: net),
              ),
              const SizedBox(height: 24),

              Text('Accent',
                  style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final a in fructaAccent.values)
                    _Swatch(
                      color: a.color,
                      ink: a.onColor,
                      selected: a == accent,
                      onTap: () =>
                          ref.read(themeControllerProvider.notifier).setAccent(a),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              Text('Text size',
                  style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Row(
                children: [
                  Text('A',
                      style: TextStyle(
                          fontFamily: fructaFonts.mono,
                          fontSize: 13,
                          color: c.muted)),
                  Expanded(
                    child: Slider(
                      value: scale.clamp(0.9, 1.3),
                      min: 0.9,
                      max: 1.3,
                      divisions: 8,
                      onChanged: (v) => ref
                          .read(themeControllerProvider.notifier)
                          .setTextScale(v),
                    ),
                  ),
                  Text('A',
                      style: TextStyle(
                          fontFamily: fructaFonts.mono,
                          fontSize: 20,
                          color: c.muted)),
                ],
              ),

              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: c.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: Text(cfg.string('onboarding.lookCta', 'Looks good')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.name, required this.rate, required this.net});
  final String name;
  final double rate;
  final double net;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.s2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: fructaFonts.mono,
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('Money market · net ${net.toStringAsFixed(2)}%',
                        style: TextStyle(color: c.faint, fontSize: 11)),
                  ],
                ),
              ),
              Text('${rate.toStringAsFixed(2)}%',
                  style: TextStyle(
                      fontFamily: fructaFonts.mono,
                      color: c.accent,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: CustomPaint(painter: _MiniCurve(c.accent)),
          ),
        ],
      ),
    );
  }
}

class _MiniCurve extends CustomPainter {
  _MiniCurve(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pts = [0.86, 0.8, 0.82, 0.62, 0.66, 0.44, 0.5, 0.28, 0.18];
    final path = Path()..moveTo(0, h * pts.first);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(w * i / (pts.length - 1), h * pts[i]);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MiniCurve old) => old.color != color;
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.ink,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final Color ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? c.text : Colors.transparent, width: 2),
        ),
        child: selected
            ? Icon(Icons.check_rounded, color: ink, size: 22)
            : null,
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i <= step ? c.accent : c.s3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

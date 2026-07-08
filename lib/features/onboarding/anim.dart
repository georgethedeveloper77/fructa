import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A Lottie animation from assets, with a graceful [fallback] shown if the file
/// isn't present yet — so onboarding never breaks while the .json art is still
/// being sourced. Drop files at `assets/lottie/<name>.json` and declare the
/// folder in pubspec; until then the fallback (an icon or painter) renders.
class LottieHero extends StatelessWidget {
  const LottieHero({
    super.key,
    required this.asset,
    required this.fallback,
    this.size = 120,
    this.repeat = true,
  });

  final String asset; // e.g. 'assets/lottie/coin.json'
  final Widget fallback;
  final double size;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        asset,
        repeat: repeat,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(child: fallback),
      ),
    );
  }
}
